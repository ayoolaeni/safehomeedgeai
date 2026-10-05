import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/device_state.dart';
import '../services/mqtt_service.dart';
import '../services/voice_service.dart';
import '../widgets/broker_dialog.dart';
import '../widgets/log_list.dart';
import '../widgets/mode_selector.dart';
import '../widgets/proposal_card.dart';
import '../widgets/status_tile.dart';
import '../widgets/wifi_sheet.dart';

/// The whole app is one scrollable screen, no navigation - see
/// AGENT_BUILD_SPEC.md section 5.3. Everything the user might need,
/// including the manual override buttons, is visible without digging
/// through menus.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VoiceService _voiceService = VoiceService();
  bool _voiceReady = false;
  bool _listening = false;
  DateTime? _lastConnectedChangeAt;
  bool? _lastConnectedSeen;

  late final MqttService _mqttService;
  bool? _lastConfirmedLightOn;

  @override
  void initState() {
    super.initState();
    _voiceService.init().then((ok) => setState(() => _voiceReady = ok));

    // Separate from the context.watch() used for rebuilding the UI below -
    // this listener drives a one-off SnackBar the moment the ESP32 actually
    // confirms the lamp changed state (not just when a command was sent),
    // so it only ever fires once real hardware is connected and reporting
    // home/light/state.
    _mqttService = context.read<MqttService>();
    _lastConfirmedLightOn = _mqttService.deviceState.lightOn;
    _mqttService.addListener(_onMqttStateChanged);
  }

  void _onMqttStateChanged() {
    final lightOn = _mqttService.deviceState.lightOn;
    if (_lastConfirmedLightOn != null && _lastConfirmedLightOn != lightOn && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lightOn ? 'Light is now ON' : 'Light is now OFF'),
          backgroundColor: lightOn ? Colors.green.shade700 : Colors.grey.shade800,
        ),
      );
    }
    _lastConfirmedLightOn = lightOn;
  }

  /// Publishes the command and shows an immediate "sent" confirmation.
  /// This fires the instant you tap a button or a voice command is
  /// understood - it confirms the app acted on your input, not that the
  /// physical lamp has changed yet. The real confirmation ("Light is now
  /// ON/OFF", above) only appears once the ESP32 reports back.
  void _sendLightCommand(bool turnOn) {
    _mqttService.sendLightCommand(turnOn);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Command sent: turn light ${turnOn ? 'ON' : 'OFF'}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _editBroker(MqttService mqtt) async {
    final result = await showDialog<BrokerSettings>(
      context: context,
      builder: (context) => BrokerDialog(
        host: mqtt.brokerIp,
        user: mqtt.brokerUser,
        pass: mqtt.brokerPass,
      ),
    );
    if (result != null && result.host.trim().isNotEmpty) {
      await mqtt.setBrokerSettings(
        host: result.host,
        user: result.user,
        pass: result.pass,
      );
    }
  }

  Future<void> _onVoiceStart() async {
    if (!_voiceReady) return;
    setState(() => _listening = true);
    await _voiceService.startListening(onCommand: _onVoiceCommand);
  }

  Future<void> _onVoiceStop() async {
    if (!_listening) return;
    setState(() => _listening = false);
    await _voiceService.stopListening(onCommand: _onVoiceCommand);
  }

  void _onVoiceCommand(VoiceCommand command) {
    switch (command) {
      case VoiceCommand.lightOn:
        _sendLightCommand(true);
        break;
      case VoiceCommand.lightOff:
        _sendLightCommand(false);
        break;
      case VoiceCommand.unrecognized:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sorry, I only understand turning the light on or off.'),
            ),
          );
        }
        break;
    }
  }

  @override
  void dispose() {
    _mqttService.removeListener(_onMqttStateChanged);
    _voiceService.stopListening(onCommand: (_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final state = mqtt.deviceState;

    if (_lastConnectedSeen != state.connected) {
      _lastConnectedSeen = state.connected;
      _lastConnectedChangeAt = DateTime.now();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('SAFE HOME EDGE AI')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildConnectionTile(mqtt, state),
              const SizedBox(height: 8),
              _buildWifiTile(mqtt),
              const SizedBox(height: 16),
              _buildStatusRow(state),
              const SizedBox(height: 16),
              _buildLightButtons(),
              const SizedBox(height: 16),
              _buildVoiceButton(),
              const SizedBox(height: 20),
              Text('Mode', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ModeSelector(
                currentMode: state.mode,
                onModeSelected: mqtt.setMode,
              ),
              const SizedBox(height: 16),
              _buildAutonomyBanner(state),
              const SizedBox(height: 16),
              if (mqtt.pendingProposal != null)
                ProposalCard(
                  proposal: mqtt.pendingProposal!,
                  receivedAt: mqtt.pendingProposalReceivedAt ?? DateTime.now(),
                  onApprove: () => mqtt.respondToProposal(true),
                  onDecline: () => mqtt.respondToProposal(false),
                  onExpire: () => mqtt.clearExpiredProposal(mqtt.pendingProposal!.id),
                ),
              const SizedBox(height: 20),
              Text('Activity log', style: Theme.of(context).textTheme.titleMedium),
              const Divider(),
              LogList(entries: mqtt.logs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionTile(MqttService mqtt, DeviceState state) {
    final since = _lastConnectedChangeAt;
    final sinceText = since == null ? '' : DateFormat.Hms().format(since);
    return Card(
      color: state.connected ? Colors.green.shade50 : Colors.red.shade50,
      child: ListTile(
        leading: Icon(
          state.connected ? Icons.wifi : Icons.wifi_off,
          color: state.connected ? Colors.green : Colors.red,
        ),
        title: Text(state.connected ? 'CONNECTED' : 'DISCONNECTED'),
        subtitle: Text(
          !mqtt.brokerConfigured
              ? 'Tap to enter your laptop address'
              : 'Laptop ${mqtt.brokerIp}'
                  '${mqtt.resolvedIp == null ? '' : ' (${mqtt.resolvedIp})'}'
                  '${sinceText.isEmpty ? '' : ' · since $sinceText'}',
        ),
        trailing: const Icon(Icons.edit, size: 18),
        onTap: () => _editBroker(mqtt),
      ),
    );
  }

  Widget _buildWifiTile(MqttService mqtt) {
    final reason = mqtt.wifiSwitchReason;
    final showReason = mqtt.wifiSwitchState == 'REVERTED' ||
        mqtt.wifiSwitchState == 'REJECTED' ||
        mqtt.wifiSwitchState == 'CONNECTING';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.router),
        title: Text('Wi-Fi: ${mqtt.wifiSsid ?? 'unknown'}'),
        subtitle: Text(
          showReason && reason.isNotEmpty
              ? '${mqtt.wifiSwitchState}: $reason'
              : (mqtt.wifiIp == null ? 'Tap to choose another network' : 'IP ${mqtt.wifiIp} · tap to change'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => WifiSheet.show(context),
      ),
    );
  }

  Widget _buildStatusRow(DeviceState state) {
    return Row(
      children: [
        StatusTile(
          label: 'Light',
          value: state.lightOn ? 'ON' : 'OFF',
          icon: Icons.lightbulb,
          color: state.lightOn ? Colors.amber.shade800 : Colors.grey,
        ),
        StatusTile(
          label: 'Motion',
          value: state.motionDetected ? 'DETECTED' : 'NONE',
          icon: Icons.directions_walk,
          color: state.motionDetected ? Colors.blue : Colors.grey,
        ),
        StatusTile(
          label: 'Light level',
          value: state.isDark ? 'DARK' : 'BRIGHT',
          icon: Icons.brightness_4,
          color: state.isDark ? Colors.indigo : Colors.orange,
        ),
      ],
    );
  }

  Widget _buildLightButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => _sendLightCommand(true),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('TURN ON', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _sendLightCommand(false),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: Colors.grey.shade800,
              foregroundColor: Colors.white,
            ),
            child: const Text('TURN OFF', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceButton() {
    return GestureDetector(
      onTapDown: (_) => _onVoiceStart(),
      onTapUp: (_) => _onVoiceStop(),
      onTapCancel: () => _onVoiceStop(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _listening ? Colors.red.shade600 : Colors.blue.shade700,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _listening ? Colors.red.shade900 : Colors.blue.shade900),
        ),
        child: Column(
          children: [
            Icon(_listening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 32),
            const SizedBox(height: 4),
            Text(
              _voiceReady
                  ? (_listening ? 'Listening...' : 'Hold to speak')
                  : 'Voice unavailable (check mic permission)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutonomyBanner(DeviceState state) {
    final status = state.agentStatus;
    final requestedAutonomyNotReady =
        state.mode == OperatingMode.autonomous && !status.isAutonomousReady;

    Color color;
    if (requestedAutonomyNotReady) {
      color = Colors.red;
    } else if (status.isAutonomousReady) {
      color = Colors.green;
    } else {
      color = Colors.amber.shade800;
    }

    String headline;
    if (requestedAutonomyNotReady) {
      headline = 'Not yet earned — still asking first';
    } else if (status.isAutonomousReady) {
      headline = '${status.stateName} · autonomy active';
    } else if (status.state == 'S1') {
      headline =
          '${status.stateName} · ${status.proposals}/100 proposals · ${status.approvalRate.toStringAsFixed(0)}% approved';
    } else {
      headline =
          '${status.stateName} · ${status.approvalRate.toStringAsFixed(0)}% approved overall';
    }

    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              headline,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              status.lastChange,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
