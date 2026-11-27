import 'package:flutter/material.dart';
import '../screens/account_screen.dart';
import '../screens/messaging/messages_inbox_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// The small "My Profile / Messages / Log out" menu that replaced the old
/// Account tab (see home_screen.dart). Pulled out to its own file - not
/// left as a private class inside home_screen.dart - so it can also be
/// embedded directly inside ReadingsScreen's own header (see that
/// screen's build method): home_screen.dart importing readings_screen.dart
/// (one of its _tabRoots) while readings_screen.dart also imported
/// _ProfileMenuButton back from home_screen.dart would be a circular
/// import between the two screens; a shared widget file has no such cycle.
///
/// [embedded]: false (the default) renders the original floating version -
/// a solid paper-coloured circle with elevation, meant to sit on its own
/// on top of a page's content (used by home_screen.dart's floating
/// overlay). true renders a plain white icon with no circle/elevation,
/// to sit naturally among a dark header's own icon buttons instead -
/// used by ReadingsScreen, which has its own pencil/music/book icons in
/// that same header and would otherwise have this floating on top of
/// them (the exact overlap bug this embedded mode fixes).
class ProfileMenuButton extends StatelessWidget {
  final bool embedded;
  // Which tab's Navigator Account/Messages should push onto - passed in
  // by HomeScreen's floating overlay (see home_screen.dart) as whichever
  // tab's own key is current, since the floating button itself sits in
  // a Stack *beside* the tab Navigators, not nested inside any one of
  // them, so plain Navigator.of(context) from there would miss all four
  // and climb straight past the bottom nav bar. Left null for the
  // embedded case (ReadingsScreen) - that usage already sits *inside*
  // its own tab's Navigator, so the plain Navigator.of(context) fallback
  // below already finds the right one with no key needed.
  //
  // Previously this always used rootNavigator: true, which opened Account/
  // Messages as a full page over the whole bottom-nav shell - the project
  // owner's own bug report: "On every page I need the bottom nav... Right
  // now when I am at log in or account there is no way to go back." Both
  // halves of that report are fixed together: pushing onto a tab's own
  // Navigator (instead of root) keeps the bottom bar on screen the same
  // way any other pushed page in that tab already does, and AccountScreen
  // itself now has a real back arrow (see account_screen.dart) rather
  // than relying on one this rootNavigator push never had anyway.
  final GlobalKey<NavigatorState>? navigatorKey;
  const ProfileMenuButton({super.key, this.embedded = false, this.navigatorKey});

  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthService().signOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
      }
    }
  }

  void _onSelected(BuildContext context, String value) {
    final nav = navigatorKey?.currentState ?? Navigator.of(context);
    switch (value) {
      case 'profile':
        nav.push(MaterialPageRoute(builder: (_) => const AccountScreen()));
        break;
      case 'messages':
        nav.push(MaterialPageRoute(builder: (_) => const MessagesInboxScreen()));
        break;
      case 'logout':
        _signOut(context);
        break;
    }
  }

  static const _items = [
    PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('My Profile'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'messages', child: ListTile(leading: Icon(Icons.chat_bubble_outline), title: Text('Messages'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout, color: Colors.redAccent), title: Text('Log out', style: TextStyle(color: Colors.redAccent)), contentPadding: EdgeInsets.zero)),
  ];

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return PopupMenuButton<String>(
        tooltip: 'Account menu',
        icon: const Icon(Icons.person, color: Colors.white),
        onSelected: (v) => _onSelected(context, v),
        itemBuilder: (_) => _items,
      );
    }
    return Material(
      color: AppColors.paper,
      shape: const CircleBorder(),
      elevation: 3,
      child: PopupMenuButton<String>(
        tooltip: 'Account menu',
        icon: const Icon(Icons.person, color: AppColors.stone),
        onSelected: (v) => _onSelected(context, v),
        itemBuilder: (_) => _items,
      ),
    );
  }
}
