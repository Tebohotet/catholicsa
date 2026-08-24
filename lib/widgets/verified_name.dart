import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

/// Wrap a name with this to show a verified tick if that person has gone
/// through some apply/approve flow. `kind` picks which one to check -
/// 'catechist' (default, backward compatible with the Course page usage)
/// or 'trustedSeller' for marketplace listings.
class VerifiedName extends StatelessWidget {
  final String uid;
  final String name;
  final TextStyle? style;
  final String kind;
  const VerifiedName({super.key, required this.uid, required this.name, this.style, this.kind = 'catechist'});

  @override
  Widget build(BuildContext context) {
    final check = kind == 'trustedSeller'
        ? FirestoreService().isTrustedSeller(uid)
        : FirestoreService().isCatechistVerified(uid);
    return FutureBuilder<bool>(
      future: check,
      builder: (context, snap) {
        final verified = snap.data == true;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(name, style: style, overflow: TextOverflow.ellipsis)),
            if (verified) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified, size: 14, color: AppColors.sage),
            ],
          ],
        );
      },
    );
  }
}
