import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catholicsa/screens/landing_screen.dart';

void main() {
  group('LandingScreen', () {
    testWidgets('shows the About Us content', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LandingScreen(onContinue: () {}),
      ));
      expect(find.text('About Us'), findsOneWidget);
      expect(find.text(LandingScreen.intro), findsOneWidget);
      expect(find.text(LandingScreen.features.first), findsOneWidget);
    });

    // LandingScreen itself stopped deciding what comes next once real
    // routing (go_router) landed - that's app.dart's job now (checking
    // onboarding state, then going to '/onboarding' or '/map'). This
    // screen's only remaining job is to call onContinue - tested here as
    // exactly that, not by checking what widget shows up afterward.
    testWidgets('Continue calls onContinue', (tester) async {
      var called = false;
      await tester.pumpWidget(MaterialApp(
        home: LandingScreen(onContinue: () => called = true),
      ));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
    });
  });
}
