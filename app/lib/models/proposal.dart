/// A pending proposal from the ESP32, decoded from the JSON payload on
/// home/agent/proposal. See AGENT_BUILD_SPEC.md section 3.
class Proposal {
  final String id;
  final String action; // "LIGHT_ON" | "LIGHT_OFF"
  final String confidence; // "HIGH" | "LOW"
  final String reason;
  final int ts;

  const Proposal({
    required this.id,
    required this.action,
    required this.confidence,
    required this.reason,
    required this.ts,
  });

  factory Proposal.fromJson(Map<String, dynamic> json) {
    return Proposal(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      confidence: json['confidence']?.toString() ?? 'LOW',
      reason: json['reason']?.toString() ?? '',
      ts: (json['ts'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isHighConfidence => confidence == 'HIGH';
}
