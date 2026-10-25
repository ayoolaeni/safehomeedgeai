// Renders every whole-home screen from a real snapshot recorded from the
// home server (test/fixtures/snapshot.json: grid outage, kitchen fire and a
// failed detector), so layout or parsing errors show up here, not on the
// client's phone. Regenerate the fixture after changing the snapshot format.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safehome_edge_ai/screens/activity_screen.dart';
import 'package:safehome_edge_ai/screens/overview_screen.dart';
import 'package:safehome_edge_ai/screens/rooms_screen.dart';
import 'package:safehome_edge_ai/screens/twins_screen.dart';
import 'package:safehome_edge_ai/services/mqtt_service.dart';

void main() {
  late Map<String, dynamic> snapshot;

  setUpAll(() {
    snapshot = jsonDecode(File('test/fixtures/snapshot.json').readAsStringSync()) as Map<String, dynamic>;
    // Add one request waiting for a person, so the approval card is drawn too.
    snapshot['pending'] = [
      {
        'id': 'P1',
        'twin': 'AA&SDT',
        'action': 'UNLOCK',
        'device': 'lock_front',
        'confidence': 'LOW',
        'category': 'human_only',
        'reason': 'Unknown visitor at the front door.',
        'source': 'Entry Recognition Agent',
        'checks': [
          {'principle': 'agentic', 'ok': true, 'note': 'inside the bounded action space'},
          {'principle': 'safe', 'ok': false, 'note': 'letting a stranger in always needs a resident'},
        ],
      },
    ];
  });

  Future<MqttService> pumpScreen(WidgetTester tester, Widget screen) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final mqtt = MqttService()..debugSetHome(snapshot);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: mqtt,
      child: MaterialApp(home: Scaffold(body: screen)),
    ));
    await tester.pump();
    return mqtt;
  }

  testWidgets('Home tab shows the fire, the pending request and the twins', (tester) async {
    await pumpScreen(tester, OverviewScreen(onOpenTab: (_) {}, onEditBroker: () {}));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('FIRE'), findsWidgets);
    expect(find.text('Reset alarm'), findsOneWidget);
    expect(find.text('A PERSON MUST DECIDE'), findsOneWidget);
    expect(find.text('Fire & Safety'), findsOneWidget);
  });

  testWidgets('Rooms tab draws the floor plan and rooms', (tester) async {
    await pumpScreen(tester, const RoomsScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Kitchen'), findsWidgets);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('Twins tab lists the AHDT and six twins', (tester) async {
    await pumpScreen(tester, const TwinsScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Agentic Home Digital Twin (AHDT)'), findsOneWidget);
    expect(find.textContaining('(AEDT)'), findsOneWidget);
  });

  testWidgets('Every twin detail page renders', (tester) async {
    for (final code in ['AEDT', 'AF&SDT', 'AWDT', 'ACDT', 'AA&SDT', 'ARDT']) {
      await pumpScreen(tester, TwinDetailScreen(code: code));
      expect(tester.takeException(), isNull, reason: code);
      expect(find.text('THRIFTOGENTIC AI PRINCIPLES'), findsOneWidget, reason: code);
    }
  });

  testWidgets('Activity tab shows the verified audit chain', (tester) async {
    await pumpScreen(tester, const ActivityScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Audit chain intact'), findsOneWidget);
  });
}
