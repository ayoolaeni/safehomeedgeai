// Basic smoke tests: the app builds and shows its shell without crashing,
// and the whole-home snapshot model reads the server's JSON. MqttService.init()
// will attempt a real connection during this test; that's expected to fail
// silently in a test environment (no broker reachable) and must not throw.

import 'package:flutter_test/flutter_test.dart';

import 'package:safehome_edge_ai/main.dart';
import 'package:safehome_edge_ai/models/home_state.dart';

void main() {
  testWidgets('SafeHome shell renders its title bar and tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const SafeHomeApp());
    await tester.pump();

    expect(find.text('SAFE HOME EDGE AI'), findsOneWidget);
    expect(find.text('Twins'), findsOneWidget);
    expect(find.text('Assistant'), findsOneWidget);
  });

  test('HomeState reads a server snapshot', () {
    const home = HomeState({
      'sim_time': '18:30',
      'energy': {'source': 'BATTERY', 'battery_soc': 54.2, 'circuits': {'kitchen': false, 'bedroom': true}},
      'rooms': [
        {'id': 'kitchen', 'name': 'Kitchen'},
      ],
      'devices': [
        {'id': 'siren', 'kind': 'siren', 'room': 'entrance', 'on': true},
        {'id': 'light_kitchen', 'kind': 'light', 'room': 'kitchen', 'on': false},
      ],
      'twins': [
        {'code': 'AEDT', 'mode': 'ASSISTED'},
        {'code': 'AWDT', 'mode': 'ASSISTED'},
      ],
    });
    expect(home.simTime, '18:30');
    expect(asDouble(home.energy['battery_soc']), 54.2);
    expect(home.hasFireAlarm, isTrue);
    expect(home.cutCircuits, ['kitchen']);
    expect(home.devicesIn('kitchen').single['id'], 'light_kitchen');
    expect(home.commonMode, 'ASSISTED');
    expect(home.roomName('kitchen'), 'Kitchen');
  });
}
