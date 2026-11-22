import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'browse_screen.dart';
import 'readings_screen.dart';
import 'hymns_screen.dart';
import 'account_screen.dart';
import 'church_detail_screen.dart';
import 'messaging/messages_inbox_screen.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
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
      onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => _tabRoots[index]),
    );
  }

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
            // Floating in a fixed top-right spot, on top of every tab,
            // instead of living inside any one of them - so it's always
            // in the same place no matter which tab is open, and none of
            // the six tab screens had to be touched to make room for it.
            // Checked all six: nothing else anchors itself to this corner
            // (Map's own overlay controls sit top-left instead).
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: const _ProfileMenuButton(),
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

/// The replacement for the old Account tab: a small always-visible button,
/// top-right, that opens a 3-item menu - "My Profile" (the Account screen,
/// unchanged), "Messages" (the inbox), "Log out" - exactly the 3 items the
/// project owner asked for. Pushed onto the *root* navigator (above the
/// bottom nav entirely, via navigatorKey[0]'s ancestor) rather than onto
/// any one tab's own stack, so it opens the same way and pops back to
/// whichever tab was showing, regardless of which tab that is.
class _ProfileMenuButton extends StatelessWidget {
  const _ProfileMenuButton();

  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthService().signOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paper,
      shape: const CircleBorder(),
      elevation: 3,
      child: PopupMenuButton<String>(
        tooltip: 'Account menu',
        icon: const Icon(Icons.person, color: AppColors.stone),
        onSelected: (value) {
          // rootNavigator: true climbs past the tab's own Navigator to
          // the one HomeScreen itself lives in, so this opens as a full
          // page over the whole bottom-nav shell - not nested a second
          // level deep inside whichever tab happened to be open.
          final root = Navigator.of(context, rootNavigator: true);
          switch (value) {
            case 'profile':
              root.push(MaterialPageRoute(builder: (_) => const AccountScreen()));
              break;
            case 'messages':
              root.push(MaterialPageRoute(builder: (_) => const MessagesInboxScreen()));
              break;
            case 'logout':
              _signOut(context);
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('My Profile'), contentPadding: EdgeInsets.zero)),
          PopupMenuItem(value: 'messages', child: ListTile(leading: Icon(Icons.chat_bubble_outline), title: Text('Messages'), contentPadding: EdgeInsets.zero)),
          PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout, color: Colors.redAccent), title: Text('Log out', style: TextStyle(color: Colors.redAccent)), contentPadding: EdgeInsets.zero)),
        ],
      ),
    );
  }
}