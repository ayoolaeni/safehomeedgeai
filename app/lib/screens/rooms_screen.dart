import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/home_state.dart';
import '../services/mqtt_service.dart';
import '../widgets/home_widgets.dart';
import 'home_screen.dart';

/// The AHDT's spatial model: a floor plan showing who is where, lights on,
/// hazards and cut circuits, then every room's devices.
class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();
    final home = mqtt.home;
    if (home == null || !mqtt.serverOnline) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Start the home server on the laptop to see the whole house.', textAlign: TextAlign.center),
      ));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const SectionTitle('Floor plan'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: AspectRatio(
              aspectRatio: 15 / 10,
              child: CustomPaint(painter: FloorPlanPainter(home, Theme.of(context).colorScheme)),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Wrap(spacing: 10, children: [
            _Legend(Colors.lightBlue, 'occupied'),
            _Legend(Colors.amber, 'light on'),
            _Legend(Colors.red, 'hazard / alarm'),
            _Legend(Colors.black54, 'power cut'),
          ]),
        ),
        const SectionTitle('Rooms'),
        ...home.rooms.map((r) => _roomCard(context, mqtt, home, r)),
      ],
    );
  }

  Widget _roomCard(BuildContext context, MqttService mqtt, HomeState home, Map<String, dynamic> room) {
    final id = room['id'].toString();
    final devices = home.devicesIn(id);
    final people = home.residents.where((r) => r['location'] == id).map((r) => r['name']).join(', ');
    final temp = room['temp'];
    final bits = [
      if (temp != null) '$temp °C',
      if (room['humidity'] != null) '${room['humidity']}% RH',
      room['occupied'] == true ? (people.isEmpty ? 'motion' : people) : 'empty',
      if (room['powered'] == false) 'POWER CUT',
    ];
    final occupied = room['occupied'] == true;
    return Card(
      child: ExpansionTile(
        leading: IconBubble(
          room['outdoor'] == true ? Icons.park_rounded : Icons.meeting_room_rounded,
          room['powered'] == false
              ? const Color(0xFFDC2626)
              : occupied
                  ? const Color(0xFF0EA5E9)
                  : Theme.of(context).colorScheme.outline,
        ),
        title: Text(room['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(bits.join(' · ')),
        children: [
          if (id == 'sitting_room')
            ListTile(
              leading: const Icon(Icons.developer_board, color: Colors.teal),
              title: const Text('Open the ESP32 lamp controls'),
              subtitle: const Text('Voice, Wi-Fi and the lamp\'s own on-device agent'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeScreen())),
            ),
          ...devices.map((d) => DeviceTile(
                device: d,
                onToggle: (on) => mqtt.setHomeDevice(d['id'].toString(), on),
              )),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend(this.color, this.text);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, color: color.withValues(alpha: 0.6)),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11)),
      ]);
}

class FloorPlanPainter extends CustomPainter {
  final HomeState home;
  final ColorScheme scheme;
  FloorPlanPainter(this.home, this.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    const planW = 15.0, planH = 10.0;
    final sx = size.width / planW, sy = size.height / planH;
    final hazardRooms = home.alerts.map((a) => a['room']).whereType<String>().toSet();
    final cut = home.cutCircuits.toSet();
    for (final r in home.rooms) {
      final rect = Rect.fromLTWH(asDouble(r['x']) * sx, asDouble(r['y']) * sy, asDouble(r['w']) * sx,
          asDouble(r['h']) * sy).deflate(2);
      final id = r['id'].toString();
      Color fill = r['outdoor'] == true
          ? const Color(0xFF10B981).withValues(alpha: 0.12)
          : scheme.surfaceContainerHighest;
      if (r['occupied'] == true) fill = const Color(0xFF0EA5E9).withValues(alpha: 0.25);
      if (hazardRooms.contains(id)) fill = const Color(0xFFEF4444).withValues(alpha: 0.45);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(rr, Paint()..color = fill);
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cut.contains(id) ? 3 : 1
          ..color = cut.contains(id) ? const Color(0xFFDC2626) : scheme.outlineVariant,
      );
      final lightOn = home.devicesIn(id).any((d) => d['kind'] == 'light' && d['on'] == true);
      if (lightOn) {
        final c = rect.topRight + const Offset(-12, 12);
        canvas.drawCircle(c, 10, Paint()..color = const Color(0xFFFBBF24).withValues(alpha: 0.35));
        canvas.drawCircle(c, 5, Paint()..color = const Color(0xFFF59E0B));
      }
      final people = home.residents.where((p) => p['location'] == id).map((p) => p['name'].toString());
      final label = [
        r['name'].toString(),
        if (r['temp'] != null) '${r['temp']}°C',
        if (people.isNotEmpty) '👤 ${people.join(', ')}',
      ].join('\n');
      final tp = TextPainter(
        text: TextSpan(
            text: label, style: TextStyle(fontSize: 10, color: scheme.onSurface, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: rect.width - 24);
      tp.paint(canvas, rect.topLeft + const Offset(8, 6));
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter old) => old.home.raw != home.raw;
}
