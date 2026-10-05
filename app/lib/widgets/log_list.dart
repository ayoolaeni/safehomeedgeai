import 'package:flutter/material.dart';

import '../models/log_entry.dart';

/// The last 20 log entries, newest first, with time/type/detail. `entries`
/// is expected newest-first already (see MqttService._addLog).
class LogList extends StatelessWidget {
  final List<LogEntry> entries;

  const LogList({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No activity yet.'),
      );
    }

    return Column(
      children: entries.map((e) => _LogRow(entry: e)).toList(),
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;

  const _LogRow({required this.entry});

  Color _typeColor() {
    switch (entry.type) {
      case 'DEMOTION':
      case 'FAULT':
      case 'REJECTION':
        return Colors.red;
      case 'PROMOTION':
        return Colors.green;
      case 'ESCALATION':
      case 'OVERRIDE':
        return Colors.orange;
      case 'ACTION':
        return Colors.blue;
      default:
        return Colors.grey.shade700;
    }
  }

  String _formatTime() {
    // The ESP32 has no RTC/NTP, so `ts` is seconds-since-boot, not a wall
    // clock timestamp. Showing it as elapsed time avoids implying a real
    // clock time that would be misleading.
    final duration = Duration(seconds: entry.ts);
    final h = duration.inHours.toString().padLeft(2, '0');
    final m = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              _formatTime(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(
            width: 84,
            child: Text(
              entry.type,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: _typeColor(), fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(entry.detail, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
