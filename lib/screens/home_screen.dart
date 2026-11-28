import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_menu_button.dart';
import '../services/hymn_player_service.dart';
// accountRouteName / messagesRouteName live in profile_menu_button.dart -
// see _closeProfileOverlays below for why.
import '../app.dart';

/// One real Navigator per bottom-nav tab - now built and owned by
/// go_router's `StatefulShellRoute` (see app.dart's router config)
/// instead of hand-built here with a plain `IndexedStack`. Kept as
/// package-level keys, not private to `HomeShell`, because app.dart's
/// `StatefulShellBranch` definitions need the exact same keys this file
/// reads from, so both sides are pointing at the one real Navigator per
/// tab - this is what lets `ProfileMenuButton` push Account/Messages
/// onto whichever tab is actually showing, and lets `_onWillPop`/
/// `_atTabRoot` below ask that tab's own Navigator "can you pop?".
final List<GlobalKey<NavigatorState>> homeBranchNavigatorKeys =
    List.generate(4, (_) => GlobalKey<NavigatorState>());

/// Ticks on any push/pop/remove/replace in ANY Navigator in the app -
/// go_router applies the same `observers` list (see app.dart's
/// `GoRouter(observers: ...)`) to every Navigator it builds, root and
/// every shell branch alike, so one shared observer here covers all
/// four tabs with no per-tab wiring needed. HomeShell listens to this
/// (see `_atTabRoot` below) to know the instant the active tab stops
/// being at its own root, so the floating profile button can hide
/// itself - the exact reactivity a per-tab NavigatorObserver gave the
/// old hand-built version, just routed through go_router's own
/// shared-observer hook instead of a manually-constructed Navigator.
final ValueNotifier<int> homeNavChangeTick = ValueNotifier(0);

class HomeNavObserver extends NavigatorObserver {
  void _tick() {
    // Deferred to after the current frame - a NavigatorObserver callback
    // can fire *during* an ancestor's build. Confirmed the hard way on a
    // real Windows `flutter run`, back when this was a hand-built
    // Navigator: a tab's own Navigator fires didPush on itself during
    // its own first build, which happens *while* the shell above it is
    // still building every branch at once - updating a listener
    // synchronously then throws "setState() or markNeedsBuild() called
    // during build". Same fix as before, just generalised to work
    // through go_router's shared observer list rather than a Navigator
    // this file built by hand.
    WidgetsBinding.instance.addPostFrameCallback((_) => homeNavChangeTick.value++);
  }

  @override
  void didPush(Route route, Route? previousRoute) => _tick();
  @override
  void didPop(Route route, Route? previousRoute) => _tick();
  @override
  void didRemove(Route route, Route? previousRoute) => _tick();
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => _tick();
}

/// The shell every bottom-nav tab lives inside - handed a
/// `StatefulNavigationShell` by go_router's `StatefulShellRoute` (see
/// app.dart), which is itself the real, URL-aware replacement for the
/// `IndexedStack` of manually-built per-tab Navigators this used to be.
/// Added 2026-11-28 as part of adopting real routing - the project
/// owner's own two complaints the same night: "I need refresh to keep
/// in hymns" and "no start over from about us". Everything else about
/// this screen (popups, the profile button's hide-on-push behaviour,
/// the mini hymn-player bar, back-button handling) is unchanged from
/// before - only *how* each tab's own Navigator gets built changed.
class HomeShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const HomeShell({super.key, required this.navigationShell});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Covers the case where someone already signed in during a previous
    // session and just reopened the app - requestPermission() is safe to
    // call repeatedly, it won't re-prompt if the person already answered.
    NotificationService().requestPermissionAndSaveToken();
    NotificationService().listenForForegroundMessages((message) {
      final title = message.notification?.title;
      final body = message.notification?.body;
      if (title == null && body == null) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
        content: Text([title, body].where((s) => s != null).join(' — ')),
        duration: const Duration(seconds: 4),
      ));
    });
    _showPendingPopups();
  }

  // A popup is a genuinely different thing from the SnackBar above - an
  // interrupting dialog the person has to actively dismiss, for
  // broadcasts configured with channels.popup (e.g. the welcome
  // message), rather than a passive toast for a live push arriving while
  // the app's already open.
  Future<void> _showPendingPopups() async {
    final popups = await FirestoreService().getPendingPopups();
    for (final popup in popups) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: Text(popup['title'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
          content: Text(popup['body'] ?? ''),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await FirestoreService().dismissPopup(popup['id']);
    }
  }

  // Is the currently-selected tab sitting at its own root (nothing
  // pushed on top)? Used to decide whether the profile button should
  // show at all. Reads homeNavChangeTick via the ValueListenableBuilder
  // in build() below, not just checked once - see HomeNavObserver above
  // for why this needs to be reactive.
  bool get _atTabRoot =>
      !(homeBranchNavigatorKeys[widget.navigationShell.currentIndex].currentState?.canPop() ?? false);

  Future<bool> _onWillPop() async {
    final index = widget.navigationShell.currentIndex;
    final navigator = homeBranchNavigatorKeys[index].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return false;
    }
    if (index != 0) {
      widget.navigationShell.goBranch(0);
      return false;
    }
    return true;
  }

  // The project owner's own bug report: "when you click account while on
  // a page, it stays there even when you went to another page you still
  // see account or messages." Confirmed: each bottom-nav tab keeps its
  // own Navigator stack when you switch away and back (by design -
  // that's what lets Browse remember how deep you'd drilled into the
  // Province->Diocese->Parish hierarchy) - but Account/Messages are a
  // global utility reachable from every tab's own profile menu, not real
  // content belonging to whichever tab happened to be open when you
  // tapped it, so leaving them sitting there reads as stuck/broken rather
  // than as the same kind of helpful memory Browse's own depth is. Pop
  // them off specifically (by the names profile_menu_button.dart tags
  // them with) the moment the bottom nav leaves that tab, leaving any
  // other genuine in-tab navigation depth untouched.
  void _closeProfileOverlays(int index) {
    homeBranchNavigatorKeys[index].currentState?.popUntil(
      (route) => route.settings.name != accountRouteName && route.settings.name != messagesRouteName,
    );
  }

  void _onTap(int i) {
    final leavingIndex = widget.navigationShell.currentIndex;
    if (i != leavingIndex) _closeProfileOverlays(leavingIndex);
    // initialLocation: true on the already-selected tab is go_router's
    // own documented way to reset that tab back to its own root - the
    // StatefulShellRoute equivalent of the old popUntil((r) => r.isFirst).
    widget.navigationShell.goBranch(i, initialLocation: i == leavingIndex);
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.navigationShell.currentIndex;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: ValueListenableBuilder<int>(
        valueListenable: homeNavChangeTick,
        builder: (context, _, __) => Scaffold(
          body: Stack(
            children: [
              // go_router's own replacement for the old hand-built
              // IndexedStack of per-tab Navigators - this widget already
              // *is* an IndexedStack of the 4 branches underneath.
              widget.navigationShell,
              // Floating in a fixed top-right spot, on top of whichever
              // tab is open - but ONLY while that tab is at its own
              // root. The moment anything is pushed on top (a church
              // page, a parish page, a profile, anything) this hides
              // itself instead of sitting on top of that screen's own
              // controls - see _atTabRoot above.
              //
              // Also excluded on index 1 (Browse), index 2 (Readings) and
              // index 3 (Hymns) specifically - all three tab roots have
              // their own icons in their own header now (uniform Hymns/
              // Bible/profile icon row, see quick_nav_icons.dart); each
              // embeds the same ProfileMenuButton inline in its own
              // header Row instead - see browse_screen.dart /
              // readings_screen.dart / hymns_screen.dart.
              if (_atTabRoot && index != 1 && index != 2 && index != 3)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      // Pushing Account/Messages onto the CURRENT tab's
                      // own Navigator keeps this screen's
                      // bottomNavigationBar on-screen while either is
                      // open - see profile_menu_button.dart's own
                      // comment for the full bug this fixes.
                      child: ProfileMenuButton(navigatorKey: homeBranchNavigatorKeys[index]),
                    ),
                  ),
                ),
            ],
          ),
          // A Column, not just the NavigationBar directly - the mini
          // hymn-player bar (see _MiniHymnPlayerBar below) sits directly
          // above the nav bar whenever a hymn is loaded, and disappears
          // entirely the instant nothing's playing (AnimatedBuilder
          // listens to HymnPlayerService.instance, a ChangeNotifier, so
          // this rebuilds on its own the moment play/pause/stop happens
          // anywhere in the app). This sits in HomeShell's own Scaffold,
          // which stays on screen under every pushed screen in every
          // tab (PdfViewerScreen included), unlike the floating
          // ProfileMenuButton above which deliberately hides on a push.
          bottomNavigationBar: AnimatedBuilder(
            animation: HymnPlayerService.instance,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (HymnPlayerService.instance.hasTrack) const _MiniHymnPlayerBar(),
                NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: _onTap,
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
                    NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Browse'),
                    NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Readings'),
                    NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Hymns'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The persistent "something's playing" bar - title, play/pause, and a
/// stop (X) button. Reads HymnPlayerService.instance directly rather than
/// taking it as a constructor parameter, since it's a true app-wide
/// singleton (same reason the player dialog in hymns_screen.dart reads it
/// the same way) - there's only ever one of these on screen at a time, so
/// there's no real case where it'd need to point at a different instance.
class _MiniHymnPlayerBar extends StatelessWidget {
  const _MiniHymnPlayerBar();

  @override
  Widget build(BuildContext context) {
    final player = HymnPlayerService.instance;
    return Container(
      color: AppColors.stone,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: Icon(player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
              onPressed: player.togglePlayPause,
            ),
            Expanded(
              child: Text(
                player.title ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Stop',
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: player.stop,
            ),
          ],
        ),
      ),
    );
  }
}

// ProfileMenuButton itself lives in ../widgets/profile_menu_button.dart
// (pulled out of this file so ReadingsScreen can embed it too - see that
// file's doc comment for why a shared file, not a cross-import between
// these two screens, was the right fix).
