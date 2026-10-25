import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/home_state.dart';
import '../services/mqtt_service.dart';
import '../widgets/home_widgets.dart';

/// The AHDT and its six Agentic Subsystem Digital Twins.
class TwinsScreen extends StatelessWidget {
  const TwinsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final home = mqtt.home;
    if (home == null || !mqtt.serverOnline) {
      return const Center(child: Text('Start the home server on the laptop to see the twins.'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ahdtCard(context, mqtt, home),
        const SectionTitle('Agentic subsystem twins'),
        ...home.twins.map((t) => _twinCard(context, t)),
      ],
    );
  }

  Widget _ahdtCard(BuildContext context, MqttService mqtt, HomeState home) {
    final a = home.ahdt;
    final eq = asMap(a['equipment']);
    final conn = home.connectivity;
    final slm = home.slm;
    final emergencies = (a['emergencies'] as List?) ?? const [];
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconBubble(Icons.hub_rounded, Theme.of(context).colorScheme.primary, size: 44),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Agentic Home Digital Twin (AHDT)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ]),
            const SizedBox(height: 8),
            const Text('Orchestrates every twin. Full five-principle Thriftogentic AI fusion at whole-home scope.'),
            const SizedBox(height: 6),
            PrinciplesRow(asMap(a['principles'])),
            const SizedBox(height: 6),
            Text('Equipment: ${eq['total']} registered · ${eq['functional']} healthy · ${eq['faulty']} faulty · '
                '${eq['on']} on · ${eq['real']} real'),
            if (emergencies.isNotEmpty)
              Text('Emergency: ${emergencies.join(', ')}',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(children: [
              const Tag('LAN', Colors.green),
              Tag('BROADBAND/SATELLITE ${conn['broadband'] == true ? 'UP' : 'DOWN'}',
                  conn['broadband'] == true ? Colors.green : Colors.red),
              Tag('4G/5G BACKUP ${conn['cellular'] == true ? 'UP' : 'DOWN'}',
                  conn['cellular'] == true ? Colors.green : Colors.red),
              Tag(slm['available'] == true ? 'LOCAL SLM ${slm['model']}' : 'LOCAL SLM OFF (rules only)',
                  slm['available'] == true ? Colors.teal : Colors.orange),
              const Tag('CLOUD LLM: STUB', Colors.blueGrey),
            ]),
            const SizedBox(height: 6),
            Text('Cloud escalations waiting: ${a['cloud_cases']} · distillation cycles: ${a['distill_cycles']}'
                '${a['last_distill'] != null ? ' (last ${a['last_distill']})' : ''}'),
            const Divider(),
            ...((a['agents'] as List?) ?? const [])
                .map((n) => Text('• $n', style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: mqtt.startDistillation,
              icon: const Icon(Icons.model_training),
              label: const Text('Run a distillation cycle'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _twinCard(BuildContext context, Map<String, dynamic> t) {
    final code = t['code'].toString();
    final grad = asMap(t['graduation']);
    final color = statusColor(t['status']?.toString());
    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TwinDetailScreen(code: code))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconBubble(twinIconData(code), twinColor(code), size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t['name']} ($code)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text('${grad['state']} ${grad['name']}', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
                Tag(t['status'].toString(), color),
              ]),
              const SizedBox(height: 10),
              Text(t['summary']?.toString() ?? ''),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: PrinciplesRow(asMap(t['principles']))),
                Tag(t['mode'].toString(), Theme.of(context).colorScheme.primary),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything about one twin: its principle selection, agents, bounded
/// action space, mode, graduation progress, devices and recent decisions.
class TwinDetailScreen extends StatelessWidget {
  final String code;
  const TwinDetailScreen({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final home = mqtt.home;
    final t = home?.twin(code);
    if (home == null || t == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Waiting for the home server...')));
    }
    final grad = asMap(t['graduation']);
    final devices = ((t['devices'] as List?) ?? const [])
        .map((id) => home.device(id.toString()))
        .whereType<Map<String, dynamic>>()
        .toList();
    final events = home.events.where((e) => e['twin'] == code).toList();
    final nonGrad = grad['non_graduating'] == true;
    final answered = grad['answered_since_reset'] ?? 0;
    final minP = grad['min_proposals'] ?? 10;
    return Scaffold(
      appBar: AppBar(title: Text('${t['name']} twin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [twinColor(code), Color.lerp(twinColor(code), Colors.black, 0.35)!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(children: [
              Icon(twinIconData(code), color: Colors.white, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$code · ${t['status']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(t['summary']?.toString() ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
          const SectionTitle('Thriftogentic AI principles'),
          PrinciplesRow(asMap(t['principles'])),
          if ((t['excluded_why']?.toString() ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t['excluded_why'].toString(), style: Theme.of(context).textTheme.bodySmall),
            ),
          const SectionTitle('Mode'),
          ModeChips(current: t['mode']?.toString(), onSelected: (m) => mqtt.setTwinMode(code, m)),
          const SectionTitle('Graduation'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${grad['state']} ${grad['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (!nonGrad) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: switch (grad['state']) {
                        'S1' => 0.2 * (answered / minP).clamp(0, 1),
                        'S2' => 0.4,
                        'S3' => 0.6,
                        'S4' => 0.8,
                        _ => 1.0,
                      },
                      minHeight: 8,
                    ),
                    const SizedBox(height: 6),
                    Text('$answered/$minP answers since last reset · ${grad['approval_rate']}% approved overall '
                        '(${grad['proposals']} answered in total)'),
                    Text('Hazard test suite: ${grad['hazard_suite'] == true ? 'passed' : 'not yet run'}'),
                    if (grad['canary_left_s'] != null) Text('Canary period: ${grad['canary_left_s']} s left'),
                    if (grad['signoff_pending'] == true)
                      const Text('Waiting for household sign-off on the Home tab.',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 4),
                  Text(grad['last_change']?.toString() ?? '', style: Theme.of(context).textTheme.bodySmall),
                  if (!nonGrad && grad['hazard_suite'] != true)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => mqtt.markHazardSuite(code),
                        icon: const Icon(Icons.fact_check),
                        label: const Text('I have completed the hazard tests'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SectionTitle('Agents'),
          ...((t['agents'] as List?) ?? const []).map((a) => ListTile(
                dense: true,
                leading: const Icon(Icons.smart_toy_outlined),
                title: Text(a.toString()),
              )),
          const SectionTitle('Bounded action space'),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: ((t['actions'] as List?) ?? const [])
                .map((a) => Chip(label: Text(prettyAction(a.toString()), style: const TextStyle(fontSize: 11))))
                .toList(),
          ),
          const SectionTitle('Sensors & actuators'),
          ...devices.map((d) => DeviceTile(device: d, onToggle: (on) => mqtt.setHomeDevice(d['id'].toString(), on))),
          if (code == 'AEDT')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(spacing: 8, children: [
                for (final s in const ['GRID', 'BATTERY', 'GENERATOR'])
                  OutlinedButton(onPressed: () => mqtt.setPowerSource(s), child: Text('Use $s')),
              ]),
            ),
          SectionTitle('Recent decisions (${events.length})'),
          if (events.isEmpty) const Text('Nothing yet.'),
          ...events.map(EventTile.new),
        ],
      ),
    );
  }
}
