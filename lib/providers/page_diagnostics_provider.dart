import 'package:flutter/foundation.dart';

/// One test case - a label and an async call to run, timed and shown
/// pass/fail independently of the others.
class TestCase {
  final String label;
  final Future<dynamic> Function() run;
  TestCase(this.label, this.run);
}

class PageDiagnostics {
  final String pageName;
  final List<TestCase> testCases;
  PageDiagnostics({required this.pageName, required this.testCases});
}

/// A plain global ValueNotifier, deliberately not a Riverpod provider -
/// most screens in this app are plain StatefulWidget, not
/// ConsumerStatefulWidget, and this needs to work from any of them
/// without forcing a widget-type conversion just to register
/// diagnostics. Whichever screen is currently visible sets this in its
/// own initState via registerPageDiagnostics below; the diagnostics
/// page reads whatever's here when opened, so it tests the actual page
/// you're on, not a fixed list regardless of where you are in the app.
final currentPageDiagnostics = ValueNotifier<PageDiagnostics?>(null);

/// Call from a screen's initState with that screen's own relevant
/// service calls.
void registerPageDiagnostics(String pageName, List<TestCase> testCases) {
  currentPageDiagnostics.value = PageDiagnostics(pageName: pageName, testCases: testCases);
}