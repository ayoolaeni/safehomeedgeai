import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_state.dart';
import '../models/log_entry.dart';
import '../models/proposal.dart';
import '../models/wifi_network.dart';

/// Talks to the Mosquitto broker over MQTT and exposes the whole system
/// state as a ChangeNotifier so the UI just listens and rebuilds. This is
/// the only file in the app that touches the mqtt_client package - screens
/// and widgets never see a topic string directly.
///
/// See AGENT_BUILD_SPEC.md section 3 for the full topic contract and
/// section 5.4 for the behaviour this class is required to implement:
/// connect on start, retry every 5s forever, subscribe to everything on
/// connect, publish with QoS 1, never crash on a malformed payload, and use
/// a unique client id per run.
class MqttService extends ChangeNotifier {
  static const String _prefsBrokerIpKey = 'broker_ip';
  static const String _prefsBrokerUserKey = 'broker_user';
  static const String _prefsBrokerPassKey = 'broker_pass';
  static const int _brokerPort = 1883;
  static const int _maxLogEntries = 20;

  // Empty until the user enters the laptop's address in the app's settings.
  String _brokerIp = '';
  String _brokerUser = '';
  String _brokerPass = '';
  String? _resolvedIp;
  MqttServerClient? _client;
  Timer? _reconnectTimer;
  bool _connecting = false;
  bool _disposed = false;

  DeviceState _deviceState = const DeviceState();
  Proposal? _pendingProposal;
  DateTime? _pendingProposalReceivedAt;
  final List<LogEntry> _logs = [];

  List<WifiNetwork> _wifiNetworks = const [];
  String _wifiSwitchState = 'NONE';
  String _wifiSwitchReason = '';
  String? _wifiSsid;
  String? _wifiIp;

  DeviceState get deviceState => _deviceState;

  /// Networks from the last scan the ESP32 published. Empty until the first
  /// scan result arrives after requestWifiScan().
  List<WifiNetwork> get wifiNetworks => List.unmodifiable(_wifiNetworks);

  /// The ESP32's own report of its Wi-Fi: NONE, CONNECTING, CONNECTED,
  /// REVERTED or REJECTED, with a short reason for the last three.
  String get wifiSwitchState => _wifiSwitchState;
  String get wifiSwitchReason => _wifiSwitchReason;
  String? get wifiSsid => _wifiSsid;
  String? get wifiIp => _wifiIp;
  Proposal? get pendingProposal => _pendingProposal;
  DateTime? get pendingProposalReceivedAt => _pendingProposalReceivedAt;
  List<LogEntry> get logs => List.unmodifiable(_logs);
  String get brokerIp => _brokerIp;
  String get brokerUser => _brokerUser;
  String get brokerPass => _brokerPass;
  bool get brokerConfigured => _brokerIp.isNotEmpty;

  /// The literal IP the last connection attempt actually used, after
  /// resolving `brokerIp` if it was a hostname (e.g. "AYOOLA001.local").
  /// Null until a resolution has happened. Shown in the UI so it's obvious
  /// what address mDNS resolved to, which is handy for debugging.
  String? get resolvedIp => _resolvedIp;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _brokerIp = prefs.getString(_prefsBrokerIpKey) ?? '';
    _brokerUser = prefs.getString(_prefsBrokerUserKey) ?? '';
    _brokerPass = prefs.getString(_prefsBrokerPassKey) ?? '';
    unawaited(_connect());
  }

  /// Called from the broker settings dialog. Saves the laptop's address and
  /// the broker login on the phone, so they are entered once, then
  /// reconnects straight away. An empty username means the broker has no login.
  Future<void> setBrokerSettings({
    required String host,
    required String user,
    required String pass,
  }) async {
    if (host.trim().isEmpty) return;
    _brokerIp = host.trim();
    _brokerUser = user.trim();
    _brokerPass = pass;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBrokerIpKey, _brokerIp);
    await prefs.setString(_prefsBrokerUserKey, _brokerUser);
    await prefs.setString(_prefsBrokerPassKey, _brokerPass);

    _client?.disconnect();
    _deviceState = _deviceState.copyWith(connected: false);
    notifyListeners();
    unawaited(_connect());
  }

  /// If `_brokerIp` is a plain IP address, returns it unchanged. Otherwise
  /// treats it as an mDNS hostname (e.g. "AYOOLA001" or "AYOOLA001.local")
  /// and tries to resolve it fresh via multicast DNS, the same way the
  /// ESP32 firmware resolves the broker by hostname instead of a fixed IP -
  /// so this keeps working even if the laptop's IP changes. Falls back to
  /// the raw entered value if resolution fails, so typing a real IP always
  /// still works with no mDNS involved at all.
  Future<String> _resolveHost(String host) async {
    if (InternetAddress.tryParse(host) != null) {
      return host;
    }

    final name = host.endsWith('.local') ? host : '$host.local';
    final client = MDnsClient();
    try {
      await client.start();
      await for (final record in client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(name),
        timeout: const Duration(seconds: 4),
      )) {
        return record.address.address;
      }
    } catch (e) {
      debugPrint('MqttService: mDNS lookup for $name failed: $e');
    } finally {
      client.stop();
    }
    debugPrint('MqttService: mDNS lookup for $name found nothing, trying "$host" directly');
    return host;
  }

  Future<void> _connect() async {
    if (_disposed || _connecting) return;
    // Nothing to connect to until the user has entered the laptop's address.
    if (!brokerConfigured) return;
    _connecting = true;

    final resolvedHost = await _resolveHost(_brokerIp);
    _resolvedIp = resolvedHost != _brokerIp ? resolvedHost : null;

    final clientId =
        'safehome-app-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';
    final client = MqttServerClient(resolvedHost, clientId);
    client.port = _brokerPort;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = false; // we drive our own 5s retry loop below
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;

    var connectMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);
    if (_brokerUser.isNotEmpty) {
      connectMessage = connectMessage.authenticateAs(_brokerUser, _brokerPass);
    }
    client.connectionMessage = connectMessage;

    _client = client;

    try {
      await client.connect();
    } catch (e) {
      debugPrint('MqttService: connect failed: $e');
      client.disconnect();
    }

    _connecting = false;

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      unawaited(_connect());
    });
  }

  void _onConnected() {
    debugPrint('MqttService: connected to $_brokerIp');
    _deviceState = _deviceState.copyWith(connected: true);
    notifyListeners();

    final client = _client;
    if (client == null) return;

    client.updates!.listen(_onMessage);

    for (final topic in const [
      'home/light/state',
      'home/sensors/motion',
      'home/sensors/light',
      'home/mode/state',
      'home/agent/proposal',
      'home/agent/status',
      'home/agent/log',
      'home/wifi/scans',
      'home/wifi/status',
    ]) {
      client.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void _onDisconnected() {
    debugPrint('MqttService: disconnected from $_brokerIp');
    if (_disposed) return;
    _deviceState = _deviceState.copyWith(connected: false);
    notifyListeners();
    _scheduleReconnect();
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final recMess = event.payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      _handlePayload(topic, payload);
    }
  }

  void _handlePayload(String topic, String payload) {
    try {
      switch (topic) {
        case 'home/light/state':
          _deviceState = _deviceState.copyWith(lightOn: payload.trim() == 'ON');
          break;
        case 'home/sensors/motion':
          _deviceState =
              _deviceState.copyWith(motionDetected: payload.trim() == 'TRUE');
          break;
        case 'home/sensors/light':
          final json = jsonDecode(payload) as Map<String, dynamic>;
          _deviceState = _deviceState.copyWith(
            isDark: json['level']?.toString() == 'DARK',
            ldrRaw: (json['raw'] as num?)?.toInt() ?? _deviceState.ldrRaw,
          );
          break;
        case 'home/mode/state':
          _deviceState = _deviceState.copyWith(
            mode: operatingModeFromString(payload.trim()),
          );
          break;
        case 'home/agent/proposal':
          final json = jsonDecode(payload) as Map<String, dynamic>;
          _pendingProposal = Proposal.fromJson(json);
          _pendingProposalReceivedAt = DateTime.now();
          break;
        case 'home/agent/status':
          final json = jsonDecode(payload) as Map<String, dynamic>;
          _deviceState = _deviceState.copyWith(
            agentStatus: AgentStatus.fromJson(json),
          );
          break;
        case 'home/agent/log':
          final json = jsonDecode(payload) as Map<String, dynamic>;
          _addLog(LogEntry.fromJson(json));
          break;
        case 'home/wifi/scans':
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final list = (json['networks'] as List?) ?? const [];
          _wifiNetworks = [
            for (final item in list)
              WifiNetwork.fromJson(item as Map<String, dynamic>),
          ];
          break;
        case 'home/wifi/status':
          final json = jsonDecode(payload) as Map<String, dynamic>;
          _wifiSwitchState = json['state']?.toString() ?? _wifiSwitchState;
          _wifiSwitchReason = json['reason']?.toString() ?? '';
          _wifiSsid = json['ssid']?.toString();
          _wifiIp = json['ip']?.toString();
          break;
      }
    } catch (e, st) {
      // A malformed payload must never crash the app - log it and move on.
      debugPrint('MqttService: malformed payload on $topic: $e\n$st');
      return;
    }
    notifyListeners();
  }

  void _addLog(LogEntry entry) {
    // Replayed history on reconnect can include entries we've already
    // seen; de-duplicate by sequence number.
    if (_logs.any((e) => e.seq == entry.seq)) return;
    _logs.insert(0, entry);
    if (_logs.length > _maxLogEntries) {
      _logs.removeRange(_maxLogEntries, _logs.length);
    }
  }

  void _publish(String topic, String payload) {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) {
      debugPrint('MqttService: cannot publish to $topic, not connected');
      return;
    }
    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  /// Publishes to home/light/cmd. Always allowed, in every mode - the ESP32
  /// obeys it immediately regardless of the current mode or autonomy state.
  void sendLightCommand(bool turnOn) {
    _publish('home/light/cmd', turnOn ? 'LIGHT_ON' : 'LIGHT_OFF');
  }

  /// Publishes to home/mode/set. The chip the UI actually shows as
  /// selected still comes from home/mode/state (the ESP32's confirmation),
  /// not from this call - see home_screen.dart.
  void setMode(OperatingMode mode) {
    _publish('home/mode/set', operatingModeToString(mode));
  }

  /// Publishes to home/agent/response. `approve` true -> "APPROVE", false
  /// -> "DECLINE". Clears the local pending proposal immediately so the
  /// card disappears without waiting for a round trip.
  void respondToProposal(bool approve) {
    final proposal = _pendingProposal;
    if (proposal == null) return;
    final payload = jsonEncode({
      'id': proposal.id,
      'answer': approve ? 'APPROVE' : 'DECLINE',
    });
    _publish('home/agent/response', payload);
    _pendingProposal = null;
    _pendingProposalReceivedAt = null;
    notifyListeners();
  }

  /// Asks the ESP32 to scan for Wi-Fi networks. The answer arrives on
  /// home/wifi/scans and lands in wifiNetworks.
  void requestWifiScan() {
    _publish('home/wifi/scan/request', 'SCAN');
  }

  /// Asks the ESP32 to move to another network. The ESP32 accepts this only
  /// in MANUAL mode. It drops the broker connection while it switches, and
  /// reverts to the previous network if it can't reach the broker within
  /// about a minute. The password is sent over the broker connection, so it
  /// is not stored by the app.
  void switchWifi(String ssid, String password) {
    _wifiSwitchState = 'CONNECTING';
    _wifiSwitchReason = 'sent switch request for "$ssid"';
    _publish('home/wifi/set', jsonEncode({'ssid': ssid, 'password': password}));
    notifyListeners();
  }

  /// Called by a countdown timer in the UI once a proposal's on-device
  /// timeout (PROPOSAL_TIMEOUT_MS) has passed, so the card disappears
  /// locally even if the ESP32's own ESCALATION log entry arrives a moment
  /// later.
  void clearExpiredProposal(String id) {
    if (_pendingProposal?.id == id) {
      _pendingProposal = null;
      _pendingProposalReceivedAt = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _client?.disconnect();
    super.dispose();
  }
}
