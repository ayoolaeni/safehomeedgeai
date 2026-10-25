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
    final color = _typeColor();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5, right: 10),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(entry.type,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: color, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text(_formatTime(), style: Theme.of(context).textTheme.labelSmall),
                ]),
                const SizedBox(height: 2),
                Text(entry.detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
