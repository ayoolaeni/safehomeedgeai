import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/device_state.dart';
import '../services/mqtt_service.dart';
import '../services/voice_service.dart';
import '../widgets/broker_dialog.dart';
import '../widgets/home_widgets.dart';
import '../widgets/log_list.dart';
import '../widgets/proposal_card.dart';
import '../widgets/wifi_sheet.dart';

/// Controls for the real ESP32 lamp in the sitting room, opened from the
/// Rooms and Home tabs. The lamp runs its own on-device agent, so this
/// screen talks to it directly on the original home/... topics and keeps
/// working even when the whole-home server is not running.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

const _amber = Color(0xFFF59E0B);
const _green = Color(0xFF059669);
const _red = Color(0xFFDC2626);

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
    _voiceService.init().then((ok) {
      if (mounted) setState(() => _voiceReady = ok);
    });

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
      appBar: AppBar(
        title: const Text('Sitting room lamp'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tag('REAL ESP32', Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _buildLampHero(state),
                const SizedBox(height: 12),
                _buildStatusRow(state),
                const SizedBox(height: 12),
                _buildVoiceButton(),
                if (mqtt.pendingProposal != null) ...[
                  const SectionTitle('Lamp asks'),
                  ProposalCard(
                    proposal: mqtt.pendingProposal!,
                    receivedAt: mqtt.pendingProposalReceivedAt ?? DateTime.now(),
                    onApprove: () => mqtt.respondToProposal(true),
                    onDecline: () => mqtt.respondToProposal(false),
                    onExpire: () => mqtt.clearExpiredProposal(mqtt.pendingProposal!.id),
                  ),
                ],
                const SectionTitle('Mode'),
                ModeChips(
                  current: operatingModeToString(state.mode),
                  onSelected: (m) => mqtt.setMode(operatingModeFromString(m)),
                ),
                const SizedBox(height: 10),
                _buildAutonomyBanner(state),
                const SectionTitle('Connection'),
                Card(
                  child: Column(children: [
                    _buildConnectionTile(mqtt, state),
                    const Divider(height: 1, indent: 70),
                    _buildWifiTile(mqtt),
                  ]),
                ),
                const SectionTitle('Activity log'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: LogList(entries: mqtt.logs),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // The lamp itself: a glowing bulb, its state, and On / Off buttons.
  Widget _buildLampHero(DeviceState state) {
    final on = state.lightOn;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: on
              ? [const Color(0xFFFBBF24), const Color(0xFFD97706)]
              : [const Color(0xFF334155), const Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: on ? 0.95 : 0.08),
              boxShadow: on
                  ? [BoxShadow(color: Colors.yellow.withValues(alpha: 0.7), blurRadius: 40, spreadRadius: 6)]
                  : null,
            ),
            child: Icon(
              on ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
              size: 60,
              color: on ? _amber : Colors.white54,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            on ? 'The lamp is on' : 'The lamp is off',
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            state.connected ? 'Confirmed by the ESP32' : 'Waiting for the laptop connection',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _sendLightCommand(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB45309),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.power_settings_new_rounded),
                  label: const Text('Turn on', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _sendLightCommand(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.power_off_rounded),
                  label: const Text('Turn off', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(DeviceState state) {
    Widget tile(StatTile t) => Expanded(child: t);
    return Row(
      children: [
        tile(StatTile(
          icon: state.lightOn ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
          label: 'Light',
          value: state.lightOn ? 'ON' : 'OFF',
          color: state.lightOn ? _amber : Colors.blueGrey,
        )),
        const SizedBox(width: 10),
        tile(StatTile(
          icon: Icons.directions_walk_rounded,
          label: 'Motion',
          value: state.motionDetected ? 'YES' : 'NONE',
          color: state.motionDetected ? const Color(0xFF0EA5E9) : Colors.blueGrey,
        )),
        const SizedBox(width: 10),
        tile(StatTile(
          icon: state.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          label: 'Light level',
          value: state.isDark ? 'DARK' : 'BRIGHT',
          color: state.isDark ? const Color(0xFF6366F1) : _amber,
        )),
      ],
    );
  }

  Widget _buildVoiceButton() {
    final colors = !_voiceReady
        ? [Colors.blueGrey.shade400, Colors.blueGrey.shade600]
        : _listening
            ? [const Color(0xFFEF4444), const Color(0xFFB91C1C)]
            : [const Color(0xFF6366F1), const Color(0xFF4338CA)];
    return GestureDetector(
      onTapDown: (_) => _onVoiceStart(),
      onTapUp: (_) => _onVoiceStop(),
      onTapCancel: () => _onVoiceStop(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
              child: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _voiceReady ? (_listening ? 'Listening...' : 'Hold to speak') : 'Voice unavailable',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    _voiceReady ? 'Say "turn on the light" or "turn off the light"' : 'Check the microphone permission',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutonomyBanner(DeviceState state) {
    final status = state.agentStatus;
    final requestedAutonomyNotReady = state.mode == OperatingMode.autonomous && !status.isAutonomousReady;

    Color color;
    IconData icon;
    if (requestedAutonomyNotReady) {
      color = _red;
      icon = Icons.front_hand_rounded;
    } else if (status.isAutonomousReady) {
      color = _green;
      icon = Icons.verified_rounded;
    } else {
      color = _amber;
      icon = Icons.school_rounded;
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
      headline = '${status.stateName} · ${status.approvalRate.toStringAsFixed(0)}% approved overall';
    }

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: IconBubble(icon, color),
        title: Text(headline, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        subtitle: Text(status.lastChange),
      ),
    );
  }

  Widget _buildConnectionTile(MqttService mqtt, DeviceState state) {
    final since = _lastConnectedChangeAt;
    final sinceText = since == null ? '' : DateFormat.Hms().format(since);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: IconBubble(
        state.connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
        state.connected ? _green : _red,
      ),
      title: Text(state.connected ? 'Connected' : 'Disconnected', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        !mqtt.brokerConfigured
            ? 'Tap to enter your laptop address'
            : 'Laptop ${mqtt.brokerIp}'
                '${mqtt.resolvedIp == null ? '' : ' (${mqtt.resolvedIp})'}'
                '${sinceText.isEmpty ? '' : ' · since $sinceText'}',
      ),
      trailing: const Icon(Icons.edit_rounded, size: 18),
      onTap: () => _editBroker(mqtt),
    );
  }

  Widget _buildWifiTile(MqttService mqtt) {
    final reason = mqtt.wifiSwitchReason;
    final showReason = mqtt.wifiSwitchState == 'REVERTED' ||
        mqtt.wifiSwitchState == 'REJECTED' ||
        mqtt.wifiSwitchState == 'CONNECTING';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: const IconBubble(Icons.router_rounded, Color(0xFF0EA5E9)),
      title: Text('Wi-Fi: ${mqtt.wifiSsid ?? 'unknown'}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        showReason && reason.isNotEmpty
            ? '${mqtt.wifiSwitchState}: $reason'
            : (mqtt.wifiIp == null ? 'Tap to choose another network' : 'IP ${mqtt.wifiIp} · tap to change'),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => WifiSheet.show(context),
    );
  }
}
