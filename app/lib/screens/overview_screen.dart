import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/home_state.dart';
import '../services/mqtt_service.dart';
import '../widgets/home_widgets.dart';
import '../widgets/proposal_card.dart';
import 'home_screen.dart';
import 'twins_screen.dart';

/// The whole house at a glance: a status header, live figures, alarms,
/// anything waiting for a person, the mode, and the six twins.
class OverviewScreen extends StatelessWidget {
  final void Function(int tab) onOpenTab;
  final VoidCallback onEditBroker;
  const OverviewScreen({super.key, required this.onOpenTab, required this.onEditBroker});

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final home = mqtt.home;
    final online = home != null && mqtt.serverOnline;
    final children = <Widget>[_hero(context, mqtt, online ? home : null)];

    if (!online) {
      children.add(_serverOffline(context, mqtt));
    } else {
      children
        ..add(const SizedBox(height: 12))
        ..add(_stats(context, home))
        ..addAll(_alerts(context, mqtt, home))
        ..addAll(_messages(context, home))
        ..addAll(_pending(context, mqtt, home))
        ..add(const SectionTitle('Whole-home mode'))
        ..add(ModeChips(current: home.commonMode, onSelected: (m) => mqtt.setTwinMode('ALL', m)))
        ..add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            home.commonMode == null
                ? 'Twins are in different modes. Set each one on the Twins tab.'
                : 'Manual: you decide. Assisted: twins ask first. Auto: a twin acts alone only once it is '
                    'THRIFTONOMOUS. Safety fail-safes always run.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ))
        ..add(const SectionTitle('Energy & water'))
        ..add(_energyCard(context, home))
        ..add(_waterCard(context, home))
        ..add(SectionTitle('Subsystem twins',
            trailing: TextButton(onPressed: () => onOpenTab(2), child: const Text('See all'))))
        ..add(_twinGrid(context, home));
    }
    if (mqtt.deviceState.connected) {
      children
        ..add(const SectionTitle('Real device'))
        ..add(Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: IconBubble(Icons.lightbulb_rounded,
                mqtt.deviceState.lightOn ? const Color(0xFFF59E0B) : const Color(0xFF0D9488)),
            title: const Text('Sitting room lamp', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('ESP32 · light ${mqtt.deviceState.lightOn ? 'on' : 'off'} · on-device agent'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeScreen())),
          ),
        ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: children);
  }

  // A gradient status header: greeting, overall state, connection.
  Widget _hero(BuildContext context, MqttService mqtt, HomeState? home) {
    final connected = mqtt.deviceState.connected;
    final critical = home?.alerts.where((a) => a['severity'] == 'CRITICAL').length ?? 0;
    final warnings = (home?.alerts.length ?? 0) - critical;
    final List<Color> colors;
    final String headline;
    final IconData icon;
    if (home == null) {
      colors = [const Color(0xFF475569), const Color(0xFF334155)];
      headline = connected ? 'Home server offline' : 'Not connected';
      icon = Icons.cloud_off_rounded;
    } else if (critical > 0) {
      colors = [const Color(0xFFDC2626), const Color(0xFF991B1B)];
      headline = critical == 1 ? '1 critical alert' : '$critical critical alerts';
      icon = Icons.warning_rounded;
    } else if (warnings > 0) {
      colors = [const Color(0xFFD97706), const Color(0xFFB45309)];
      headline = warnings == 1 ? '1 thing needs attention' : '$warnings things need attention';
      icon = Icons.info_rounded;
    } else {
      colors = [const Color(0xFF0F766E), const Color(0xFF115E59)];
      headline = 'All systems normal';
      icon = Icons.verified_rounded;
    }
    final resident = home?.residents.isNotEmpty == true ? home!.residents.first['name'] : null;
    final hour = int.tryParse((home?.simTime ?? '12').split(':').first) ?? 12;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(resident == null ? 'SafeHome' : '$greeting, $resident',
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ),
            if (home != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.schedule_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(home.simTime, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(headline,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 14),
          InkWell(
            onTap: onEditBroker,
            borderRadius: BorderRadius.circular(12),
            child: Row(children: [
              Icon(connected ? Icons.wifi_rounded : Icons.wifi_off_rounded, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  !mqtt.brokerConfigured
                      ? 'Tap to enter your laptop address'
                      : '${connected ? 'Connected to' : 'Trying'} ${mqtt.brokerIp}'
                          '${home != null ? ' · ${home.devices.length} devices · ${home.twins.length} twins' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              const Icon(Icons.edit_rounded, color: Colors.white70, size: 14),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _stats(BuildContext context, HomeState home) {
    final e = home.energy;
    final soc = asDouble(e['battery_soc']);
    final tank = asDouble(home.water['tank_pct']);
    final sitting = home.rooms.where((r) => r['id'] == 'sitting_room');
    final temp = sitting.isEmpty ? null : sitting.first['temp'];
    final source = e['source']?.toString() ?? '';
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 700 ? 4 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      final tiles = [
        StatTile(icon: Icons.battery_charging_full_rounded, label: 'Battery · $source', value: '${soc.round()}%',
            color: soc < 20 ? const Color(0xFFDC2626) : const Color(0xFF059669), progress: soc / 100),
        StatTile(icon: Icons.solar_power_rounded, label: 'Solar now', value: '${e['solar_w']} W',
            color: const Color(0xFFF59E0B)),
        StatTile(icon: Icons.water_drop_rounded, label: 'Water tank', value: '${tank.round()}%',
            color: const Color(0xFF0EA5E9), progress: tank / 100),
        StatTile(icon: Icons.thermostat_rounded, label: 'Sitting room', value: temp == null ? '-' : '$temp°C',
            color: const Color(0xFF8B5CF6)),
      ];
      return Wrap(spacing: 10, runSpacing: 10, children: tiles.map((t) => SizedBox(width: w, child: t)).toList());
    });
  }

  Widget _serverOffline(BuildContext context, MqttService mqtt) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBubble(Icons.dns_rounded, scheme.tertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(mqtt.deviceState.connected
                  ? 'The whole-home server is not answering. On the laptop, double-click '
                      'safehome-server.exe and leave its window open. The sitting-room lamp below still works '
                      'on its own.'
                  : 'Connect to the laptop first: tap the address line in the header above.'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _alerts(BuildContext context, MqttService mqtt, HomeState home) {
    final alerts = home.alerts;
    if (alerts.isEmpty) return [];
    final scheme = Theme.of(context).colorScheme;
    final out = <Widget>[const SectionTitle('Alerts')];
    for (final a in alerts) {
      final critical = a['severity'] == 'CRITICAL';
      final color = critical ? const Color(0xFFDC2626) : const Color(0xFFD97706);
      out.add(Card(
        color: critical ? scheme.errorContainer.withValues(alpha: 0.6) : null,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: IconBubble(critical ? Icons.warning_rounded : Icons.info_rounded, color),
          title: Text(a['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${a['detail'] ?? ''}\n${a['twin']} · ${a['sim'] ?? ''}'),
          isThreeLine: true,
        ),
      ));
    }
    if (home.hasFireAlarm || home.cutCircuits.isNotEmpty || home.device('main_valve')?['on'] == false) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (home.hasFireAlarm)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                onPressed: mqtt.resetAlarm,
                icon: const Icon(Icons.notifications_off_rounded),
                label: const Text('Reset alarm'),
              ),
            if (home.cutCircuits.isNotEmpty)
              OutlinedButton.icon(
                onPressed: mqtt.restorePower,
                icon: const Icon(Icons.power_rounded),
                label: Text('Restore power (${home.cutCircuits.map(home.roomName).join(', ')})'),
              ),
            if (home.device('main_valve')?['on'] == false)
              OutlinedButton.icon(
                onPressed: () => mqtt.setHomeDevice('main_valve', true),
                icon: const Icon(Icons.water_drop_rounded),
                label: const Text('Reopen water valve'),
              ),
          ],
        ),
      ));
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Text('Only a person can reset an alarm, and only once the hazard has cleared.',
            style: Theme.of(context).textTheme.bodySmall),
      ));
    }
    return out;
  }

  List<Widget> _messages(BuildContext context, HomeState home) {
    final msgs = home.messages;
    if (msgs.isEmpty) return [];
    final m = msgs.first;
    final scheme = Theme.of(context).colorScheme;
    return [
      const SectionTitle('From your home'),
      Card(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          leading: IconBubble(Icons.record_voice_over_rounded, scheme.primary),
          title: Text(m['text']?.toString() ?? ''),
          subtitle: Text('Resident liaison · ${m['sim'] ?? ''}'),
        ),
      ),
    ];
  }

  List<Widget> _pending(BuildContext context, MqttService mqtt, HomeState home) {
    final items = <Widget>[];
    for (final p in home.pending) {
      items.add(HomeProposalCard(
        proposal: p,
        home: home,
        onApprove: () => mqtt.respondHome(p['id'].toString(), true),
        onDecline: () => mqtt.respondHome(p['id'].toString(), false),
      ));
    }
    final lamp = mqtt.pendingProposal;
    if (lamp != null) {
      items.add(ProposalCard(
        proposal: lamp,
        receivedAt: mqtt.pendingProposalReceivedAt ?? DateTime.now(),
        onApprove: () => mqtt.respondToProposal(true),
        onDecline: () => mqtt.respondToProposal(false),
        onExpire: () => mqtt.clearExpiredProposal(lamp.id),
      ));
    }
    if (items.isEmpty) return [];
    return [SectionTitle('Waiting for you · ${items.length}'), ...items];
  }

  Widget _energyCard(BuildContext context, HomeState home) {
    final e = home.energy;
    final gen = home.generator;
    final source = e['source']?.toString() ?? '';
    final sourceColor = source == 'GRID'
        ? const Color(0xFF2563EB)
        : source == 'GENERATOR'
            ? const Color(0xFF92400E)
            : const Color(0xFF059669);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconBubble(Icons.bolt_rounded, sourceColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Running on ${source.toLowerCase()}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text('House load ${e['load_w']} W · solar ${e['solar_w']} W',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              Tag(e['grid'] == true ? 'GRID ON' : 'GRID OFF',
                  e['grid'] == true ? const Color(0xFF2563EB) : const Color(0xFFDC2626)),
            ]),
            const SizedBox(height: 10),
            Text('Generator ${gen['running'] == true ? 'running' : 'off'} · ${gen['fuel_l']} L fuel · '
                'CO ${gen['co_ppm']} ppm', style: Theme.of(context).textTheme.bodySmall),
            if (e['power_ok'] == false)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Power interrupted!', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _waterCard(BuildContext context, HomeState home) {
    final w = home.water;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const IconBubble(Icons.water_rounded, Color(0xFF0EA5E9)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tank ${asDouble(w['tank_pct']).round()}% · ${w['tank_l']} L',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text('Borehole pump ${home.device('borehole_pump')?['on'] == true ? 'on' : 'off'} · quality '
                  '${w['turbidity']} NTU', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          if (w['leak'] == true) const Tag('LEAK', Color(0xFFDC2626)),
          if (w['raining'] == true) const Tag('RAIN', Color(0xFF0EA5E9)),
        ]),
      ),
    );
  }

  Widget _twinGrid(BuildContext context, HomeState home) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 700 ? 6 : 3;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: home.twins.map((t) {
          final code = t['code'].toString();
          final status = t['status']?.toString();
          final grad = asMap(t['graduation']);
          return SizedBox(
            width: w,
            child: Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TwinDetailScreen(code: code))),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Stack(clipBehavior: Clip.none, children: [
                        IconBubble(twinIconData(code), twinColor(code), size: 42),
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: statusColor(status),
                              shape: BoxShape.circle,
                              border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(t['name'].toString(), textAlign: TextAlign.center, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      Text('${t['mode']}'.toLowerCase(), style: Theme.of(context).textTheme.labelSmall),
                      Text(grad['state']?.toString() ?? '', style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
    });
  }
}
