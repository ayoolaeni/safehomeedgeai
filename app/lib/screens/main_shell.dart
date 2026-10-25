import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mqtt_service.dart';
import '../widgets/broker_dialog.dart';
import 'activity_screen.dart';
import 'assistant_screen.dart';
import 'overview_screen.dart';
import 'rooms_screen.dart';
import 'simulation_sheet.dart';
import 'twins_screen.dart';

/// Whole-home app: five tabs over the home server's digital twin.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  StreamSubscription<String>? _ackSub;

  @override
  void initState() {
    super.initState();
    _ackSub = context.read<MqttService>().acks.listen((text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
    });
  }

  @override
  void dispose() {
    _ackSub?.cancel();
    super.dispose();
  }

  Future<void> _editBroker(MqttService mqtt) async {
    final result = await showDialog<BrokerSettings>(
      context: context,
      builder: (context) => BrokerDialog(host: mqtt.brokerIp, user: mqtt.brokerUser, pass: mqtt.brokerPass),
    );
    if (result != null && result.host.trim().isNotEmpty) {
      await mqtt.setBrokerSettings(host: result.host, user: result.user, pass: result.pass);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final home = mqtt.home;
    final pages = [
      OverviewScreen(onOpenTab: (i) => setState(() => _tab = i), onEditBroker: () => _editBroker(mqtt)),
      const RoomsScreen(),
      const TwinsScreen(),
      const AssistantScreen(),
      const ActivityScreen(),
    ];
    final pendingCount = home?.pending.length ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final online = mqtt.serverOnline;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF14B8A6), Color(0xFF0F766E)]),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.home_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SAFE HOME EDGE AI',
                      overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Row(children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: online
                            ? const Color(0xFF10B981)
                            : (mqtt.deviceState.connected ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      !mqtt.deviceState.connected
                          ? 'Not connected'
                          : online
                              ? 'Whole home live'
                              : 'Home server offline',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: 'Simulation & demo events',
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              icon: const Icon(Icons.science_rounded, size: 18),
              label: const Text('Demo'),
              onPressed: online ? () => SimulationSheet.show(context) : null,
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Laptop (broker) settings',
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Connect'),
              onPressed: () => _editBroker(mqtt),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Center(
          // On a wide laptop window the content stays a comfortable width.
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: pages[_tab]),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.home_outlined),
            ),
            selectedIcon: const Icon(Icons.home_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
              icon: Icon(Icons.meeting_room_outlined), selectedIcon: Icon(Icons.meeting_room_rounded), label: 'Rooms'),
          const NavigationDestination(
              icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub_rounded), label: 'Twins'),
          const NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Assistant'),
          const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Activity'),
        ],
      ),
    );
  }
}
