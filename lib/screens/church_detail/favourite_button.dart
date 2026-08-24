import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';


class FavouriteButton extends StatefulWidget {
  final String churchId;
  final String parishId;
  const FavouriteButton({super.key, required this.churchId, required this.parishId});

  @override
  State<FavouriteButton> createState() => _FavouriteButtonState();
}

class _FavouriteButtonState extends State<FavouriteButton> {
  bool _loading = true;
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    FirestoreService().isFavourite(widget.churchId).then((v) {
      if (mounted) setState(() { _fav = v; _loading = false; });
    });
  }

  Future<void> _toggle() async {
    if (AuthService().currentUser == null) {
      final user = await AuthService().signInWithGoogle();
      if (user == null) return;
    }
    try {
      await FirestoreService().toggleFavourite(widget.churchId, parishId: widget.parishId);
      if (mounted) setState(() => _fav = !_fav);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _fav ? 'Remove favourite' : 'Add to favourites',
      icon: Icon(_fav ? Icons.favorite : Icons.favorite_border, size: 20, color: _fav ? Colors.redAccent : AppColors.ink),
      onPressed: _loading ? null : _toggle,
    );
  }
}

/// Standing notices (Baptisms, Marriages, etc.) plus any events flagged
/// showInNotices: true that haven't happened yet - one shared merge used by
/// both the inline Notices section and the bell popup, so the logic only
/// exists in one place.
