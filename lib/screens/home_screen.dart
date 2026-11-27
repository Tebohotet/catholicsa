import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'browse_screen.dart';
import 'readings_screen.dart';
import 'hymns_screen.dart';
import 'church_detail_screen.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_menu_button.dart';
import '../app.dart';

class HomeScreen extends StatefulWidget {
  // Set only when the app was opened from a church link/QR code (see
  // app.dart's _churchLinkFromCurrentUrl) - pushes straight to that
  // church, on top of the Map tab, instead of leaving someone who
  // followed a link on the plain home screen with no idea it worked.
  final String? initialChurchParishId;
  final String? initialChurchId;
  const HomeScreen({super.key, this.initialChurchParishId, this.initialChurchId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

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
    _openInitialChurchLinkIfAny();
  }

  // Runs once, after the first frame, so _navigatorKeys[0] is attached
  // to an actual Navigator before anything tries to push onto it.
  void _openInitialChurchLinkIfAny() {
    final parishId = widget.initialChurchParishId;
    final churchId = widget.initialChurchId;
    if (parishId == null || churchId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKeys[0].currentState?.push(MaterialPageRoute(
        builder: (_) => ChurchDetailScreen(parishId: parishId, churchId: churchId),
      ));
    });
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

  // Each tab gets its own Navigator with its own back-stack, so pushing a
  // church detail page (or anything else) stays *inside* that tab instead
  // of covering the whole screen - the bottom nav bar lives outside all of
  // them and never disappears.
  //
  // Only 4 tabs right now, not 6: Events and Shop are deliberately left
  // off the bottom bar - the project owner's own call ("Hiding the un[us]ed
  // Tabs, events, Shop, we do not have any information in it") since
  // neither has any real events/listings in production yet, unlike Map,
  // Browse, Readings and Hymns which all do. Their screens, routes and
  // backing services are untouched and still fully working - EventsScreen
  // and ShopScreen just aren't one of _tabRoots below, so admins can still
  // manage events/listings from the Admin Panel exactly as before. Put
  // them back on the bar (and bump this List.generate and the one in
  // build() below back to 6) once there's real content in either one.
  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(4, (_) => GlobalKey<NavigatorState>());

  // Account used to be its own tab here. It's reached from the profile
  // menu now instead (see _ProfileMenuButton below) - the project owner's
  // own ask: "we will put Hymns there Next to Readings... On the menu,
  // put 1.My Profile which leads to Account As It is." The screen itself
  // (AccountScreen) didn't need to change at all for this.
  static const _tabRoots = [
    MapScreen(),
    BrowseScreen(),
    ReadingsScreen(),
    HymnsScreen(),
  ];

  Widget _buildTabNavigator(int index) {
    return Navigator(
      key: _navigatorKeys[index],
      // Rebuilds HomeScreen on every push/pop in any tab, so the profile
      // button below can hide itself the instant something's pushed and
      // reappear the instant that tab is back at its root. Found the
      // hard way: the button used to float above EVERY pushed screen in
      // every tab, not just the tab roots - overlapping ParishDetailScreen's
      // own search icon, ChurchDetailScreen's own edit-pencil icon, and
      // anything else with its own top-right control. Checking only the
      // 6 (now 4) tab roots for collisions, like the original comment
      // here claimed, was never actually enough - there are dozens of
      // pushed screens underneath them.
      // addPostFrameCallback, not a direct setState() - real crash found
      // tonight on a Windows flutter run (not seen on the deployed web
      // build, which strips this assert() in --release mode, but a real
      // bug either way): each tab's Navigator fires didPush on itself
      // during its OWN first build (NavigatorState.restoreState ->
      // didChangeDependencies, on initial mount), which happens *while*
      // HomeScreen's IndexedStack is still building all 4 tab Navigators
      // at once - calling setState() on the ancestor HomeScreen DURING
      // that build throws "setState() or markNeedsBuild() called during
      // build". Deferring to after the current frame is the standard
      // fix for a NavigatorObserver wanting to update an ancestor.
      observers: [_TabNavObserver(() {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      })],
      onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => _tabRoots[index]),
    );
  }

  // Is the currently-selected tab sitting at its own root (nothing
  // pushed on top)? Used to decide whether the profile button should
  // show at all - see _buildTabNavigator's observer above for why this
  // needs to be reactive, not just checked once.
  bool get _atTabRoot => !(_navigatorKeys[_index].currentState?.canPop() ?? false);

  Future<bool> _onWillPop() async {
    final navigator = _navigatorKeys[_index].currentState!;
    if (navigator.canPop()) {
      navigator.pop();
      return false;
    }
    if (_index != 0) {
      setState(() => _index = 0);
      return false;
    }
    return true;
  }

  void _onTap(int i) {
    if (i == _index) {
      _navigatorKeys[i].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _index = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _index,
              children: List.generate(4, _buildTabNavigator),
            ),
            // Floating in a fixed top-right spot, on top of whichever tab
            // is open - but ONLY while that tab is at its own root. The
            // moment anything is pushed on top (a church page, a parish
            // page, a profile, anything) this hides itself instead of
            // sitting on top of that screen's own controls - see
            // _atTabRoot and the observer in _buildTabNavigator above.
            //
            // Also excluded on index 2 (Readings) specifically - that tab
            // root has its own pencil/music/book icons in its own header,
            // which this floating button used to sit on top of (a second,
            // different overlap bug from the one _atTabRoot fixes, since
            // Readings IS a tab root, not a pushed screen). ReadingsScreen
            // embeds the same ProfileMenuButton inline in that header Row
            // instead - see readings_screen.dart.
            if (_atTabRoot && _index != 2)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    // Pushing Account/Messages onto the CURRENT tab's own
                    // Navigator (instead of the old rootNavigator: true)
                    // keeps this screen's bottomNavigationBar on-screen
                    // while either is open - see profile_menu_button.dart's
                    // own comment for the full bug this fixes.
                    child: ProfileMenuButton(navigatorKey: _navigatorKeys[_index]),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onTap,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
            NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Browse'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Readings'),
            NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Hymns'),
          ],
        ),
      ),
    );
  }
}

/// Fires [onChange] on any push/pop/remove/replace in whichever tab
/// Navigator it's attached to - see _buildTabNavigator above for why.
class _TabNavObserver extends NavigatorObserver {
  final VoidCallback onChange;
  _TabNavObserver(this.onChange);

  @override
  void didPush(Route route, Route? previousRoute) => onChange();
  @override
  void didPop(Route route, Route? previousRoute) => onChange();
  @override
  void didRemove(Route route, Route? previousRoute) => onChange();
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => onChange();
}

// ProfileMenuButton itself now lives in ../widgets/profile_menu_button.dart
// (pulled out of this file so ReadingsScreen can embed it too - see that
// file's doc comment for why a shared file, not a cross-import between
// these two screens, was the right fix).