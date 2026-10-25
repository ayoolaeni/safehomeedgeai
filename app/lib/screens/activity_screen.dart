import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mqtt_service.dart';
import '../widgets/home_widgets.dart';

/// The tamper-evident audit trail: every decision, escalation, override and
/// distillation trigger, newest first.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final home = mqtt.home;
    if (home == null || !mqtt.serverOnline) {
      return const Center(child: Text('Start the home server on the laptop to see the activity log.'));
    }
    final audit = home.audit;
    final ok = audit['verified'] == true;
    final codes = ['AHDT', ...home.twins.map((t) => t['code'].toString()), 'ESP32', 'SIM'];
    final events = home.events.where((e) => _filter == null || e['twin'] == _filter).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: IconBubble(ok ? Icons.verified_rounded : Icons.gpp_bad_rounded,
                ok ? const Color(0xFF059669) : const Color(0xFFDC2626), size: 44),
            title: Text(ok ? 'Audit chain intact' : 'Audit chain BROKEN at #${audit['broken_at']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${audit['count']} entries, each linked to the one before by a SHA-256 hash. '
                'Editing any past entry breaks the chain.'),
            trailing: TextButton(onPressed: mqtt.verifyAudit, child: const Text('Verify')),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(label: const Text('All'), selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null)),
              ),
              ...codes.map((c) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(label: Text(c), selected: _filter == c,
                        onSelected: (_) => setState(() => _filter = c)),
                  )),
            ],
          ),
        ),
        const SectionTitle('Latest 40 entries'),
        if (events.isEmpty) const Text('Nothing for this filter yet.'),
        if (events.isNotEmpty) Card(child: Column(children: events.map(EventTile.new).toList())),
      ],
    );
  }
}
