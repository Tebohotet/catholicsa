import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firestore_service.dart';

/// Same one-shot-at-startup pattern as designTokensProvider - a branding
/// change (app name, description) takes effect on next restart, which is
/// the right tradeoff for something this structural.
final brandingProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return FirestoreService().getBranding();
});
