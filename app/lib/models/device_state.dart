/// Everything the ESP32 publishes about itself: light/motion/mode state,
/// the connection status, and the graduation/autonomy status. One object,
/// held by MqttService and rebuilt (via ChangeNotifier) whenever a new
/// MQTT message updates it.
library;

enum OperatingMode { manual, assisted, autonomous }

OperatingMode operatingModeFromString(String value) {
  switch (value) {
    case 'MANUAL':
      return OperatingMode.manual;
    case 'ASSISTED':
      return OperatingMode.assisted;
    case 'AUTONOMOUS':
      return OperatingMode.autonomous;
    default:
      return OperatingMode.manual;
  }
}

String operatingModeToString(OperatingMode mode) {
  switch (mode) {
    case OperatingMode.manual:
      return 'MANUAL';
    case OperatingMode.assisted:
      return 'ASSISTED';
    case OperatingMode.autonomous:
      return 'AUTONOMOUS';
  }
}

/// The ESP32's autonomy/graduation status, decoded from the JSON payload
/// on home/agent/status. See AGENT_BUILD_SPEC.md section 3.
class AgentStatus {
  final String state; // "S1".."S5"
  final String stateName;
  final int proposals;
  final int approvals;
  final double approvalRate;
  final String lastChange;
  final int ts;

  const AgentStatus({
    required this.state,
    required this.stateName,
    required this.proposals,
    required this.approvals,
    required this.approvalRate,
    required this.lastChange,
    required this.ts,
  });

  factory AgentStatus.unknown() => const AgentStatus(
        state: 'S1',
        stateName: 'THRIFTOGENTIC',
        proposals: 0,
        approvals: 0,
        approvalRate: 0,
        lastChange: 'No status received yet',
        ts: 0,
      );

  factory AgentStatus.fromJson(Map<String, dynamic> json) {
    return AgentStatus(
      state: json['state']?.toString() ?? 'S1',
      stateName: json['stateName']?.toString() ?? 'THRIFTOGENTIC',
      proposals: (json['proposals'] as num?)?.toInt() ?? 0,
      approvals: (json['approvals'] as num?)?.toInt() ?? 0,
      approvalRate: (json['approvalRate'] as num?)?.toDouble() ?? 0,
      lastChange: json['lastChange']?.toString() ?? '',
      ts: (json['ts'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isAutonomousReady => state == 'S5';
}

/// Live device state: light, motion, light level, mode, connection.
class DeviceState {
  final bool connected;
  final bool lightOn;
  final bool motionDetected;
  final bool isDark;
  final int ldrRaw;
  final OperatingMode mode;
  final AgentStatus agentStatus;

  const DeviceState({
    this.connected = false,
    this.lightOn = false,
    this.motionDetected = false,
    this.isDark = false,
    this.ldrRaw = 0,
    this.mode = OperatingMode.manual,
    this.agentStatus = const AgentStatus(
      state: 'S1',
      stateName: 'THRIFTOGENTIC',
      proposals: 0,
      approvals: 0,
      approvalRate: 0,
      lastChange: 'No status received yet',
      ts: 0,
    ),
  });

  DeviceState copyWith({
    bool? connected,
    bool? lightOn,
    bool? motionDetected,
    bool? isDark,
    int? ldrRaw,
    OperatingMode? mode,
    AgentStatus? agentStatus,
  }) {
    return DeviceState(
      connected: connected ?? this.connected,
      lightOn: lightOn ?? this.lightOn,
      motionDetected: motionDetected ?? this.motionDetected,
      isDark: isDark ?? this.isDark,
      ldrRaw: ldrRaw ?? this.ldrRaw,
      mode: mode ?? this.mode,
      agentStatus: agentStatus ?? this.agentStatus,
    );
  }
}
