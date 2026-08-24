import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firestore_service.dart';

/// Fetched once at app start via ConsumerWidget - not live-reactive to
/// admin changes mid-session (that would need a StreamProvider watching
/// the doc instead of a one-shot FutureProvider), which is a deliberate,
/// reasonable simplification: a design change taking effect on next
/// restart rather than instantly is completely normal for something this
/// structural, matching what the admin screen itself already tells you.
final designTokensProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return FirestoreService().getDesignTokens();
});
