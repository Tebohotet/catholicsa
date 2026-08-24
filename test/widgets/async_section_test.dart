import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catholicsa/widgets/async_section.dart';

void main() {
  group('AsyncSection', () {
    testWidgets('shows loading indicator while future is pending', (tester) async {
      final completer = Future<List<String>>.delayed(const Duration(seconds: 10));
      await tester.pumpWidget(MaterialApp(
        home: AsyncSection<List<String>>(
          future: completer,
          builder: (context, data) => Text('Loaded: ${data.length}'),
        ),
      ));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error text when the future throws - this is the exact case that used to hang forever', (tester) async {
      final failing = Future<List<String>>.error(Exception('permission-denied'));
      await tester.pumpWidget(MaterialApp(
        home: AsyncSection<List<String>>(
          future: failing,
          builder: (context, data) => Text('Loaded: ${data.length}'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('shows empty message when isEmpty returns true', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AsyncSection<List<String>>(
          future: Future.value(<String>[]),
          isEmpty: (list) => list.isEmpty,
          emptyMessage: 'Nothing here yet.',
          builder: (context, data) => Text('Loaded: ${data.length}'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet.'), findsOneWidget);
    });

    testWidgets('shows builder content when the future resolves with data', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AsyncSection<List<String>>(
          future: Future.value(['a', 'b', 'c']),
          isEmpty: (list) => list.isEmpty,
          builder: (context, data) => Text('Loaded: ${data.length}'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Loaded: 3'), findsOneWidget);
    });
  });
}
