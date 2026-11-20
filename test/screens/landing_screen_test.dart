import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catholicsa/screens/landing_screen.dart';

void main() {
  group('LandingScreen', () {
    testWidgets('shows the About Us content', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LandingScreen(next: (_) => const Text('next screen')),
      ));
      expect(find.text('About Us'), findsOneWidget);
      expect(find.text(LandingScreen.intro), findsOneWidget);
      expect(find.text(LandingScreen.features.first), findsOneWidget);
    });

    testWidgets('Continue replaces the landing page with the next screen', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LandingScreen(next: (_) => const Text('next screen')),
      ));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('next screen'), findsOneWidget);
      expect(find.text('About Us'), findsNothing);
    });
  });
}
