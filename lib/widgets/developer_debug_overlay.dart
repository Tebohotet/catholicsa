import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/view_as_role_provider.dart';
import '../theme/app_theme.dart';
import '../app.dart';
import '../screens/our_item_page.dart';

/// Wraps the whole app's navigator content - this is what makes the icon
/// appear on every page automatically, rather than needing to be added
/// to each screen individually. Only ever renders anything for a real
/// Developer; everyone else sees exactly what they'd see without this
/// widget existing at all.
///
/// Stateful specifically to track whether the role-switcher sheet is
/// currently open, so pressing the icon repeatedly toggles it rather
/// than stacking multiple sheets on top of each other.
class DeveloperDebugOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const DeveloperDebugOverlay({super.key, required this.child});

  @override
  ConsumerState<DeveloperDebugOverlay> createState() => _DeveloperDebugOverlayState();
}

class _DeveloperDebugOverlayState extends ConsumerState<DeveloperDebugOverlay> {
  bool _sheetOpen = false;
  bool _diagnosticsOpen = false;

  @override
  Widget build(BuildContext context) {
    final isDevAsync = ref.watch(isRealDeveloperProvider);
    final isDev = isDevAsync.maybeWhen(data: (v) => v, orElse: () => false);
    final viewAs = ref.watch(viewAsRoleProvider);

    return Stack(
      children: [
        widget.child,
        if (isDev)
          Positioned(
            right: 12,
            bottom: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (viewAs != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                    child: Text('Viewing as: ${viewAsRoleLabel(viewAs)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                FloatingActionButton.small(
                  heroTag: 'devDiagnosticsIcon',
                  backgroundColor: AppColors.sage,
                  // No tooltip here deliberately - this widget sits as a
                  // sibling of the app's own Navigator/Overlay in the
                  // Stack below, not inside it, so a Tooltip (which
                  // needs a real Overlay ancestor) crashes on build.
                  // Confirmed directly from a real crash report, not
                  // guessed.
                  onPressed: () {
                    if (_diagnosticsOpen) {
                      final navState = rootNavigatorKey.currentState;
                      if (navState != null) navState.pop();
                      return;
                    }
                    final navContext = rootNavigatorKey.currentContext;
                    if (navContext == null) return;
                    setState(() => _diagnosticsOpen = true);
                    Navigator.push(navContext, MaterialPageRoute(builder: (_) => const OurItemPage()))
                        .whenComplete(() {
                      if (mounted) setState(() => _diagnosticsOpen = false);
                    });
                  },
                  child: const Icon(Icons.bug_report_outlined, color: Colors.white, size: 18),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'devDebugIcon',
                  backgroundColor: viewAs != null ? Colors.redAccent : AppColors.stone,
                  onPressed: _toggleRoleSwitcher,
                  child: const Icon(Icons.developer_mode, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Pops back to the root (Map tab) whenever the simulated role
  /// changes - a screen that assumed real auth state (Account, an admin
  /// panel) would otherwise keep showing stale content, or content it
  /// shouldn't, after switching to "Logged Out" or a lower-privilege
  /// role. Deliberately a safe blanket default rather than a per-screen
  /// "does this need login" registry, which would need every screen to
  /// individually declare its own requirement to stay accurate.
  void _navigateToSafety() {
    final navState = rootNavigatorKey.currentState;
    if (navState == null) return;
    navState.popUntil((route) => route.isFirst);
  }

  /// Toggles rather than always opening - pressing the icon again while
  /// the sheet is already showing closes it instead of stacking a
  /// second one on top.
  void _toggleRoleSwitcher() {
    if (_sheetOpen) {
      final navState = rootNavigatorKey.currentState;
      if (navState != null) navState.pop();
      return;
    }
    _showRoleSwitcher();
  }

  void _showRoleSwitcher() {
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    setState(() => _sheetOpen = true);
    showModalBottomSheet(
      context: navContext,
      backgroundColor: AppColors.paper,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(viewAsRoleProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('View As', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
                  const SizedBox(height: 4),
                  const Text(
                    'UI-level preview only - Firestore rules still see your real Developer account underneath. Not a substitute for the rules tests when checking real permission enforcement.',
                    style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<String?>(
                    title: Text(viewAsRoleLabel(null)),
                    value: null,
                    groupValue: current,
                    onChanged: (v) { ref.read(viewAsRoleProvider.notifier).state = v; Navigator.pop(sheetContext); _navigateToSafety(); },
                  ),
                  ...availableViewAsRoles.map((role) => RadioListTile<String?>(
                    title: Text(viewAsRoleLabel(role)),
                    value: role,
                    groupValue: current,
                    onChanged: (v) { ref.read(viewAsRoleProvider.notifier).state = v; Navigator.pop(sheetContext); _navigateToSafety(); },
                  )),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      // Runs whether the sheet was dismissed by a role selection, a tap
      // outside, or the toggle button closing it - the flag always ends
      // up correct regardless of how it closed.
      if (mounted) setState(() => _sheetOpen = false);
    });
  }
}