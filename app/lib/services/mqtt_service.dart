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
import '../models/home_state.dart';
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

  // Whole-home digital twin (the home server on the laptop).
  HomeState? _home;
  DateTime? _homeFreshAt;
  Timer? _staleTimer;
  final List<Map<String, dynamic>> _answers = [];
  final StreamController<String> _acks = StreamController<String>.broadcast();

  /// Latest whole-home snapshot, or null if the home server never answered.
  HomeState? get home => _home;

  /// True while live snapshots keep arriving. A retained snapshot left over
  /// from a server that has since stopped does not count.
  bool get serverOnline =>
      _homeFreshAt != null && DateTime.now().difference(_homeFreshAt!).inSeconds < 8;

  /// Questions and answers from the home assistant, newest first.
  List<Map<String, dynamic>> get answers => List.unmodifiable(_answers);

  /// One short line per command the server has carried out (or refused).
  Stream<String> get acks => _acks.stream;

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
    // Rebuild every few seconds so "server offline" shows up even when no
    // message arrives to trigger a rebuild.
    _staleTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_disposed) notifyListeners();
    });
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
      'thdt/state',
      'thdt/answer',
      'thdt/ack',
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
      final payload = utf8.decode(recMess.payload.message, allowMalformed: true);
      _handlePayload(topic, payload, retained: recMess.header?.retain ?? false);
    }
  }

  void _handlePayload(String topic, String payload, {bool retained = false}) {
    try {
      switch (topic) {
        case 'thdt/state':
          _home = HomeState(asMap(jsonDecode(payload)));
          if (!retained) _homeFreshAt = DateTime.now();
          break;
        case 'thdt/answer':
          final ans = asMap(jsonDecode(payload));
          final i = _answers.indexWhere((a) => a['id'] == ans['id']);
          if (i >= 0) {
            _answers[i] = ans;
          } else {
            _answers.insert(0, ans);
          }
          break;
        case 'thdt/ack':
          final ack = asMap(jsonDecode(payload));
          final result = ack['result']?.toString() ?? '';
          if (result.isNotEmpty && !retained) _acks.add(result);
          return;
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

  // ---------------------------------------------------------------------
  // Whole-home commands. Each goes to the home server on thdt/cmd, which
  // passes it through the Terse AI layer before anything is switched.
  // ---------------------------------------------------------------------

  void sendHomeCommand(Map<String, dynamic> cmd) => _publish('thdt/cmd', jsonEncode(cmd));

  /// Lets widget tests render the screens from a recorded server snapshot.
  @visibleForTesting
  void debugSetHome(Map<String, dynamic> raw) {
    _home = HomeState(raw);
    _homeFreshAt = DateTime.now();
    notifyListeners();
  }

  void setHomeDevice(String deviceId, bool on) =>
      sendHomeCommand({'type': 'device', 'device': deviceId, 'on': on});

  void setTwinMode(String twin, String mode) =>
      sendHomeCommand({'type': 'mode', 'twin': twin, 'mode': mode});

  void respondHome(String proposalId, bool approve) =>
      sendHomeCommand({'type': 'respond', 'id': proposalId, 'approve': approve});

  void runScenario(String name, {String? room, String? value}) => sendHomeCommand({
        'type': 'scenario',
        'name': name,
        if (room != null) 'room': room,
        if (value != null) 'value': value,
      });

  void resetAlarm() => sendHomeCommand({'type': 'reset_alarm'});
  void restorePower() => sendHomeCommand({'type': 'restore_power'});
  void markHazardSuite(String twin) => sendHomeCommand({'type': 'hazard_suite', 'twin': twin});
  void startDistillation() => sendHomeCommand({'type': 'distill'});
  void verifyAudit() => sendHomeCommand({'type': 'verify_audit'});
  void setPowerSource(String source) => sendHomeCommand({'type': 'set_source', 'source': source});

  /// Sends a typed or spoken question to the home assistant. The answer
  /// arrives on thdt/answer and replaces the "thinking" placeholder.
  void ask(String text) {
    final id = 'q${DateTime.now().millisecondsSinceEpoch}';
    _answers.insert(0, {'id': id, 'question': text, 'answer': null, 'source': 'thinking'});
    notifyListeners();
    sendHomeCommand({'type': 'ask', 'id': id, 'text': text});
  }

  @override
  void dispose() {
    _disposed = true;
    _staleTimer?.cancel();
    _acks.close();
    _reconnectTimer?.cancel();
    _client?.disconnect();
    super.dispose();
  }
}
