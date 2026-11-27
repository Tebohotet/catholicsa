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
  const ProfileMenuButton({super.key, this.embedded = false});

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
    // rootNavigator: true climbs past the tab's own Navigator to the one
    // HomeScreen itself lives in, so this opens as a full page over the
    // whole bottom-nav shell - not nested a second level deep inside
    // whichever tab happened to be open.
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
