// Basic smoke test: the app builds and shows its title bar without
// crashing. MqttService.init() will attempt a real connection during this
// test; that's expected to fail silently in a test environment (no
// broker reachable) and must not throw.

import 'package:flutter_test/flutter_test.dart';

import 'package:safehome_edge_ai/main.dart';

void main() {
  testWidgets('SafeHome home screen renders its title bar', (WidgetTester tester) async {
    await tester.pumpWidget(const SafeHomeApp());
    await tester.pump();

    expect(find.text('SAFE HOME EDGE AI'), findsOneWidget);
  });
}
