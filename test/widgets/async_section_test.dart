import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catholicsa/widgets/async_section.dart';

void main() {
  group('AsyncSection', () {
    testWidgets('shows loading indicator while future is pending', (tester) async {
      // Future<T>.delayed needs an explicit computation when T isn't
      // nullable - omitting it defaults to a closure that returns null,
      // which throws ArgumentError for a non-nullable type parameter like
      // List<String> here. Supplying a (never-reached, since the test only
      // checks the loading state) computation fixes that.
      final completer = Future<List<String>>.delayed(
        const Duration(seconds: 10),
        () => <String>[],
      );
      await tester.pumpWidget(MaterialApp(
        home: AsyncSection<List<String>>(
          future: completer,
          builder: (context, data) => Text('Loaded: ${data.length}'),
        ),
      ));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error text when the future throws - this is the exact case that used to hang forever', (tester) async {
      // Future<T>.error(...) completes immediately, before AsyncSection's
      // FutureBuilder has a chance to attach its listener - Dart's zone
      // machinery then reports it as an unhandled error straight to the
      // test framework instead of letting FutureBuilder's snap.hasError
      // branch (the thing this test is actually meant to exercise) see it.
      // Future.delayed with a throwing computation defers the error past
      // that widget-build/subscribe step, same as a real async failure
      // would arrive.
      final failing = Future<List<String>>.delayed(
        const Duration(milliseconds: 1),
        () => throw Exception('permission-denied'),
      );
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
