import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../providers/page_diagnostics_provider.dart';

/// Reads whichever page's diagnostics were last registered via
/// registerPageDiagnostics - genuinely tests the screen you were on when
/// you opened this, not a fixed global list regardless of context. Falls
/// back to a small generic set only if no screen has registered anything
/// yet, which is an honest "not wired up for this page yet" state rather
/// than a silent wrong answer.
class OurItemPage extends StatelessWidget {
  const OurItemPage({super.key});

  static final _today = DateTime.now();
  static final _monthDay = '${_today.month.toString().padLeft(2, '0')}-${_today.day.toString().padLeft(2, '0')}';
  static final _dateStr = '${_today.year}-${_today.month.toString().padLeft(2, '0')}-${_today.day.toString().padLeft(2, '0')}';

  static final List<TestCase> _genericFallback = [
    TestCase('getLiturgicalDay (today)', () => FirestoreService().getLiturgicalDay(_today)),
    TestCase('getSaintByMonthDay (today)', () => FirestoreService().getSaintByMonthDay(_monthDay)),
    TestCase('getBibleTranslations', () => FirestoreService().getBibleTranslations()),
    TestCase('AuthService().currentUser (sync check)', () async => AuthService().currentUser?.uid ?? 'not signed in'),
    TestCase('getReadingNote (today)', () => FirestoreService().getReadingNote(_dateStr)),
  ];

  @override
  Widget build(BuildContext context) {
    final registered = currentPageDiagnostics.value;
    final pageName = registered?.pageName ?? 'Not page-specific yet';
    final items = registered?.testCases ?? _genericFallback;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.stone,
        foregroundColor: Colors.white,
        title: Text('Diagnostics — $pageName'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (registered == null)
            Container(
              width: double.infinity,
              color: Colors.amber.shade50,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'This screen hasn\'t registered its own diagnostics yet - showing a generic app-wide set instead. See registerPageDiagnostics in page_diagnostics_provider.dart to wire this screen up specifically.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) => _TestItemTile(testCase: items[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestItemTile extends StatefulWidget {
  final TestCase testCase;
  const _TestItemTile({required this.testCase});

  @override
  State<_TestItemTile> createState() => _TestItemTileState();
}

class _TestItemTileState extends State<_TestItemTile> {
  late Future<dynamic> _future;
  final _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    // A 15s timeout here is deliberately part of the diagnostic itself -
    // it turns "genuinely stuck forever" into a visible, timed-out result
    // rather than a permanent spinner with no information in it.
    _future = widget.testCase.run().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('No response after 15s - this is very likely the actual problem.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppColors.paperDark,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: FutureBuilder<dynamic>(
          future: _future,
          builder: (context, snap) {
            _stopwatch.stop();
            final elapsed = _stopwatch.elapsedMilliseconds;
            Widget statusIcon;
            String statusText;
            Color statusColor;

            if (snap.connectionState != ConnectionState.done) {
              statusIcon = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
              statusText = 'Pending...';
              statusColor = Colors.black54;
              _stopwatch.start(); // still running, keep timing
            } else if (snap.hasError) {
              statusIcon = const Icon(Icons.error, color: Colors.redAccent, size: 18);
              statusText = 'FAILED after ${elapsed}ms: ${snap.error}';
              statusColor = Colors.redAccent;
            } else {
              statusIcon = const Icon(Icons.check_circle, color: AppColors.sage, size: 18);
              statusText = 'OK after ${elapsed}ms: ${snap.data}';
              statusColor = AppColors.sage;
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                statusIcon,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.testCase.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(statusText, style: TextStyle(fontSize: 12, color: statusColor)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}