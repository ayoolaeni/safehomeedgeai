import 'package:flutter/material.dart';

import '../models/home_state.dart';

/// Small building blocks shared by the whole-home screens.

const principleLabels = {
  'agentic': 'Agentic',
  'edge': 'Edge',
  'safe': 'Safe',
  'resilient': 'Resilient',
  'green': 'Green',
};

const principleIcons = {
  'agentic': Icons.psychology_rounded,
  'edge': Icons.memory_rounded,
  'safe': Icons.health_and_safety_rounded,
  'resilient': Icons.autorenew_rounded,
  'green': Icons.eco_rounded,
};

Color statusColor(String? status) {
  switch (status) {
    case 'ALERT':
    case 'CRITICAL':
      return const Color(0xFFDC2626);
    case 'WARN':
      return const Color(0xFFD97706);
    default:
      return const Color(0xFF059669);
  }
}

IconData deviceIcon(String? kind) {
  switch (kind) {
    case 'light':
      return Icons.lightbulb_rounded;
    case 'ac':
      return Icons.ac_unit_rounded;
    case 'lock':
      return Icons.lock_rounded;
    case 'pump':
      return Icons.water_rounded;
    case 'valve':
    case 'irrigation':
      return Icons.water_drop_rounded;
    case 'treatment':
      return Icons.science_rounded;
    case 'generator':
      return Icons.local_gas_station_rounded;
    case 'ats':
      return Icons.swap_horiz_rounded;
    case 'load':
      return Icons.power_rounded;
    case 'siren':
      return Icons.campaign_rounded;
    case 'sprinkler':
      return Icons.shower_rounded;
    case 'fan':
      return Icons.wind_power_rounded;
    case 'camera':
      return Icons.videocam_rounded;
    case 'alarm':
      return Icons.shield_rounded;
    case 'presence':
      return Icons.person_rounded;
    default:
      return Icons.sensors_rounded;
  }
}

IconData twinIconData(String code) {
  switch (code) {
    case 'AEDT':
      return Icons.bolt_rounded;
    case 'AF&SDT':
      return Icons.local_fire_department_rounded;
    case 'AWDT':
      return Icons.water_drop_rounded;
    case 'ACDT':
      return Icons.thermostat_rounded;
    case 'AA&SDT':
      return Icons.security_rounded;
    case 'ARDT':
      return Icons.person_rounded;
    default:
      return Icons.hub_rounded;
  }
}

/// Each twin keeps its own colour everywhere in the app.
Color twinColor(String code) {
  switch (code) {
    case 'AEDT':
      return const Color(0xFFF59E0B);
    case 'AF&SDT':
      return const Color(0xFFEF4444);
    case 'AWDT':
      return const Color(0xFF0EA5E9);
    case 'ACDT':
      return const Color(0xFF8B5CF6);
    case 'AA&SDT':
      return const Color(0xFF10B981);
    case 'ARDT':
      return const Color(0xFFEC4899);
    default:
      return const Color(0xFF0F766E);
  }
}

String prettyAction(String? action) {
  final s = (action ?? '').replaceAll('_', ' ').toLowerCase();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: t.textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.1, fontWeight: FontWeight.w700, color: t.colorScheme.onSurfaceVariant)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A round tinted icon, used as the leading element of rows and cards.
class IconBubble extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBubble(this.icon, this.color, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(size / 3)),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

/// A small pill label, e.g. SIMULATED / REAL / CRITICAL LOAD.
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4, top: 2, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
    );
  }
}

/// A compact figure with an icon, e.g. "Battery 72%".
class StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double? progress;
  const StatTile({super.key, required this.icon, required this.label, required this.value, required this.color,
      this.progress});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBubble(icon, color, size: 32),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0, 1),
                  minHeight: 5,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One device row: reading or state, real/simulated tag, and a switch when
/// a person may control it. Locks show "Locked" when on.
class DeviceTile extends StatelessWidget {
  final Map<String, dynamic> device;
  final void Function(bool on)? onToggle;
  const DeviceTile({super.key, required this.device, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final kind = device['kind']?.toString();
    final on = device['on'] == true;
    final functional = device['functional'] != false;
    final value = device['value'];
    final unit = device['unit']?.toString() ?? '';
    String state;
    if (!functional) {
      state = 'Fault · not reporting';
    } else if (kind == 'lock') {
      state = on ? 'Locked' : 'Unlocked';
    } else if (kind == 'sensor' || kind == 'camera' || kind == 'ats' || kind == 'alarm') {
      state = value == null ? '-' : '$value $unit'.trim();
    } else if (kind == 'ac' && on) {
      state = 'On · set ${value ?? ''} °C';
    } else if (kind == 'generator') {
      state = '${on ? 'Running' : 'Off'} · ${value ?? '-'} $unit';
    } else {
      state = on ? 'On' : 'Off';
    }
    final controllable = device['controllable'] == true && onToggle != null && kind != 'ats';
    final scheme = Theme.of(context).colorScheme;
    final color = !functional
        ? const Color(0xFFDC2626)
        : on
            ? (kind == 'siren' ? const Color(0xFFDC2626) : const Color(0xFFF59E0B))
            : scheme.outline;
    return ListTile(
      leading: IconBubble(functional ? deviceIcon(kind) : Icons.error_rounded, color, size: 38),
      title: Text(device['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(padding: const EdgeInsets.only(right: 6), child: Text(state)),
          if (device['real'] == true)
            const Tag('REAL', Color(0xFF0D9488))
          else
            Tag('SIMULATED', scheme.outline),
          if (device['critical'] == true) const Tag('CRITICAL', Color(0xFFDC2626)),
          if (device['shed'] == true) const Tag('SHED', Color(0xFFD97706)),
        ],
      ),
      trailing: controllable ? Switch(value: on, onChanged: (v) => onToggle!(v)) : null,
    );
  }
}

/// The five Thriftogentic AI principles; the ones a twin leaves out are
/// shown struck out.
class PrinciplesRow extends StatelessWidget {
  final Map<String, dynamic> principles;
  const PrinciplesRow(this.principles, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: principleLabels.entries.map((e) {
        final on = principles[e.key] == true;
        final color = on ? scheme.primary : scheme.outline;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: on ? scheme.primaryContainer.withValues(alpha: 0.6) : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(principleIcons[e.key], size: 14, color: color),
            const SizedBox(width: 4),
            Text(e.value,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: on ? scheme.onPrimaryContainer : scheme.outline,
                  decoration: on ? null : TextDecoration.lineThrough,
                )),
          ]),
        );
      }).toList(),
    );
  }
}

/// Manual / Assisted / Autonomous as one segmented control.
class ModeChips extends StatelessWidget {
  final String? current;
  final void Function(String mode) onSelected;
  const ModeChips({super.key, required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'MANUAL', label: Text('Manual'), icon: Icon(Icons.pan_tool_alt_rounded)),
          ButtonSegment(value: 'ASSISTED', label: Text('Assisted'), icon: Icon(Icons.handshake_rounded)),
          ButtonSegment(value: 'AUTONOMOUS', label: Text('Auto'), icon: Icon(Icons.smart_toy_rounded)),
        ],
        selected: {if (current != null) current!},
        onSelectionChanged: (s) {
          if (s.isNotEmpty) onSelected(s.first);
        },
      ),
    );
  }
}

/// A request from a twin waiting for the household, with the Thriftogentic
/// AI checks it went through so the person can see why it is being asked.
class HomeProposalCard extends StatelessWidget {
  final Map<String, dynamic> proposal;
  final HomeState home;
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  const HomeProposalCard({
    super.key,
    required this.proposal,
    required this.home,
    required this.onApprove,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final twinCode = proposal['twin']?.toString() ?? '';
    final twinName = twinCode == 'AHDT' ? 'Home (AHDT)' : home.twin(twinCode)?['name'] ?? twinCode;
    final category = proposal['category']?.toString();
    final humanOnly = category == 'human_only' || category == 'governance';
    final checks = asList(proposal['checks']);
    final low = proposal['confidence'] != 'HIGH';
    final accent = twinColor(twinCode);
    return Card(
      color: scheme.tertiaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBubble(twinIconData(twinCode), accent, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(prettyAction(proposal['action']?.toString()),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(twinName.toString(), style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(children: [
              if (humanOnly) const Tag('A PERSON MUST DECIDE', Color(0xFF7C3AED)),
              if (low && !humanOnly) const Tag('LOW CONFIDENCE', Color(0xFFDC2626)),
            ]),
            const SizedBox(height: 6),
            Text(proposal['reason']?.toString() ?? ''),
            if ((proposal['source']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Raised by ${proposal['source']}', style: Theme.of(context).textTheme.bodySmall),
              ),
            if (checks.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.verified_user_rounded, size: 18, color: scheme.primary),
                title: const Text('Thriftogentic AI checks', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                children: checks
                    .map((c) => ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                            c['ok'] == true ? Icons.check_circle_rounded : Icons.front_hand_rounded,
                            color: c['ok'] == true ? const Color(0xFF059669) : const Color(0xFFD97706),
                            size: 18,
                          ),
                          title: Text(principleLabels[c['principle']] ?? '${c['principle']}'),
                          subtitle: Text(c['note']?.toString() ?? ''),
                        ))
                    .toList(),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDecline,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One audit-log line.
class EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  const EventTile(this.event, {super.key});

  @override
  Widget build(BuildContext context) {
    final type = event['type']?.toString() ?? '';
    final twin = event['twin']?.toString() ?? '';
    final color = switch (type) {
      'EMERGENCY' || 'ALERT' || 'DENIED' || 'CELLULAR' => const Color(0xFFDC2626),
      'FAILSAFE' || 'OVERRIDE' || 'ARBITRATION' => const Color(0xFFD97706),
      'AUTONOMOUS' || 'EXECUTED' || 'MANUAL' => const Color(0xFF059669),
      'PROPOSAL' || 'GRADUATION' || 'SIGNOFF' => const Color(0xFF4F46E5),
      _ => Theme.of(context).colorScheme.outline,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${event['sim'] ?? ''}\n#${event['seq']}',
                  style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
            ),
          ),
          Container(width: 3, margin: const EdgeInsets.symmetric(vertical: 6), color: color.withValues(alpha: 0.6)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(children: [Tag(twin, twinColor(twin)), Tag(type, color)]),
                  const SizedBox(height: 2),
                  Text(event['detail']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
