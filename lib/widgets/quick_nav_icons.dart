import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/bible_screen.dart';

/// The same "jump to Hymns" / "jump to the Bible" pair of icons Readings'
/// own header already had, now offered everywhere else too - the project
/// owner's own ask: "I need the app to be uniform, the same Header icons
/// you have on hymns and readings use them even on browse, make it
/// uniform." Dropped into Browse/Province/Diocese/Parish headers
/// alongside each page's own existing icons (search, profile, etc.) and
/// Hymns' own header (which gets the Readings-pointing half of this
/// same pair - see hymns_screen.dart).
///
/// Hymns is a real go_router tab switch (`context.go('/hymns')`), not a
/// Navigator.push - HymnsScreen is a bottom-nav tab root with no back
/// arrow of its own, so pushing a second copy on top of wherever this is
/// tapped from would be a dead end with no way back except the OS/
/// browser back gesture (the exact bug just fixed on Readings' own copy
/// of this same icon). Bible stays a plain push - BibleScreen already has
/// its own real back arrow and isn't a bottom-nav tab, so a push behaves
/// correctly there.
class QuickNavIcons extends StatelessWidget {
  final Color iconColor;
  const QuickNavIcons({super.key, this.iconColor = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'View Hymns',
          icon: Icon(Icons.library_music_outlined, color: iconColor),
          onPressed: () => context.go('/hymns'),
        ),
        IconButton(
          tooltip: 'Browse the Bible',
          icon: Icon(Icons.menu_book_outlined, color: iconColor),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BibleScreen())),
        ),
      ],
    );
  }
}
