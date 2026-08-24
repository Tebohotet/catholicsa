import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

/// Wrap anything still in development in this instead of hardcoding an
/// `if (kDebugMode)` or similar. Reads the same platformConfig/devFlags
/// document the Super Admin Panel edits - 'off' hides it from everyone,
/// 'preview' shows it only to super admins so a half-built feature can be
/// checked in the real app before anyone else ever sees it, 'live' shows
/// it to everyone. An unregistered flag key defaults to visible (matches
/// the service-layer default), so forgetting to register one doesn't
/// silently hide something that was meant to ship.
class FeatureGate extends StatelessWidget {
  final String flagKey;
  final Widget child;
  final Widget? fallback;
  const FeatureGate({super.key, required this.flagKey, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: FirestoreService().isFeatureVisible(flagKey),
      builder: (context, snap) {
        if (snap.data == true) return child;
        return fallback ?? const SizedBox.shrink();
      },
    );
  }
}
