import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mqtt_service.dart';

/// Demo events injected into the simulated parts of the home, so every twin
/// can be shown working without real smoke, generators or water tanks.
class SimulationSheet extends StatelessWidget {
  const SimulationSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const SimulationSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final mqtt = context.read<MqttService>();
    void run(String name, {String? room, String? value}) {
      mqtt.runScenario(name, room: room, value: value);
      Navigator.of(context).pop();
    }

    Widget group(String title, List<(String, IconData, VoidCallback)> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: items
                  .map((i) => ActionChip(avatar: Icon(i.$2, size: 18), label: Text(i.$1), onPressed: i.$3))
                  .toList(),
            ),
          ],
        );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Simulation & demo events', style: Theme.of(context).textTheme.titleLarge),
          const Text('These change the simulated parts of the house. The ESP32 lamp stays real.'),
          group('People', [
            ('Arrive home', Icons.login, () => run('arrive')),
            ('Everyone leaves', Icons.logout, () => run('leave')),
            ('Go to bedroom', Icons.bed, () => run('move', room: 'bedroom')),
            ('Go to kitchen', Icons.kitchen, () => run('move', room: 'kitchen')),
            ('Go to sitting room', Icons.weekend, () => run('move', room: 'sitting_room')),
            ('Visitor at door', Icons.doorbell, () => run('visitor')),
            ('Intruder', Icons.warning_amber, () => run('intruder')),
          ]),
          group('Energy', [
            ('Grid outage', Icons.power_off, () => run('blackout')),
            ('Grid restored', Icons.power, () => run('grid_restore')),
            ('Battery at 18%', Icons.battery_alert, () => run('low_battery')),
            ('Low generator fuel', Icons.local_gas_station, () => run('low_fuel')),
            ('Block generator vent', Icons.co2, () => run('gen_co')),
          ]),
          group('Fire & safety', [
            ('Kitchen fire', Icons.local_fire_department, () => run('fire', room: 'kitchen')),
            ('Bedroom fire', Icons.local_fire_department, () => run('fire', room: 'bedroom')),
            ('Gas leak', Icons.gas_meter, () => run('gas')),
            ('Detector fault', Icons.sensors_off, () => run('sensor_fault', value: 'smoke_bedroom')),
          ]),
          group('Water & weather', [
            ('Pipe leak', Icons.water_damage, () => run('leak')),
            ('Dirty water', Icons.science, () => run('water_bad')),
            ('Tank at 20%', Icons.water_drop, () => run('low_tank')),
            ('Rain', Icons.umbrella, () => run('rain')),
            ('Sunny', Icons.wb_sunny, () => run('sunny')),
          ]),
          group('Connectivity', [
            ('Internet down', Icons.wifi_off, () => run('internet_down')),
            ('Internet back', Icons.wifi, () => run('internet_up')),
            ('4G/5G down', Icons.signal_cellular_off, () => run('cellular_down')),
            ('4G/5G back', Icons.signal_cellular_alt, () => run('cellular_up')),
          ]),
          group('Clock', [
            ('06:00', Icons.wb_twilight, () => run('time', value: '06:00')),
            ('12:00', Icons.light_mode, () => run('time', value: '12:00')),
            ('18:30', Icons.nights_stay, () => run('time', value: '18:30')),
            ('23:00', Icons.bedtime, () => run('time', value: '23:00')),
            ('Real time (1x)', Icons.speed, () => run('speed', value: '1')),
            ('Fast (60x)', Icons.fast_forward, () => run('speed', value: '60')),
            ('Very fast (300x)', Icons.fast_forward, () => run('speed', value: '300')),
          ]),
          group('Reset', [
            ('Clear all hazards', Icons.cleaning_services, () => run('clear')),
          ]),
        ],
      ),
    );
  }
}
