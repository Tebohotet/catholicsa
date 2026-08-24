import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'browse_screen.dart';
import 'readings_screen.dart';
import 'events_screen.dart';
import 'shop_screen.dart';
import 'account_screen.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../app.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(6, (_) => GlobalKey<NavigatorState>());

  static const _tabRoots = [
    MapScreen(),
    BrowseScreen(),
    ReadingsScreen(),
    EventsScreen(),
    ShopScreen(),
    AccountScreen(),
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
        body: IndexedStack(
          index: _index,
          children: List.generate(6, _buildTabNavigator),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onTap,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
            NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Browse'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Readings'),
            NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'Events'),
            NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Shop'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
          ],
        ),
      ),
    );
  }
}