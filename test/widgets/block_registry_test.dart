import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catholicsa/widgets/block_registry.dart';

void main() {
  group('BlockRegistry', () {
    testWidgets('renders a known block type (spacer) without error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => BlockRegistry.build(
              context,
              {'type': 'spacer', 'config': {'height': 20}},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('renders a textBlock with the configured text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => BlockRegistry.build(context, {
              'type': 'textBlock',
              'config': {'text': 'Hello from a block'},
            }),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Hello from a block'), findsOneWidget);
    });

    testWidgets('an unknown block type degrades gracefully instead of crashing the page', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => BlockRegistry.build(context, {
              'type': 'somethingThatWasNeverRegistered',
              'config': {},
            }),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // The exact wording matters less than the fact that this doesn't
      // throw and shows *something* visible instead of a blank/crashed page.
      expect(find.textContaining('Unknown block type'), findsOneWidget);
    });

    testWidgets('a block with no type key also degrades gracefully', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => BlockRegistry.build(context, {'config': {}}),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unknown block type'), findsOneWidget);
    });

    test('availableTypes includes every block type the registry actually knows about', () {
      final types = BlockRegistry.availableTypes;
      expect(types, containsAll(['textBlock', 'spacer', 'shareButton', 'notesList']));
    });
  });
}
