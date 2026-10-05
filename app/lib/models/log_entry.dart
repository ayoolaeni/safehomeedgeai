/// One entry from the ESP32's tamper-evident log, decoded from the JSON
/// payload on home/agent/log. See AGENT_BUILD_SPEC.md section 3.
class LogEntry {
  final int seq;
  final int ts;
  final String type;
  final String detail;

  const LogEntry({
    required this.seq,
    required this.ts,
    required this.type,
    required this.detail,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      ts: (json['ts'] as num?)?.toInt() ?? 0,
      type: json['type']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
    );
  }
}
