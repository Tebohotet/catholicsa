import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

/// Single source of truth for "who's signed in", watchable from anywhere
/// below ProviderScope. Riverpod caches the stream subscription itself, so
/// multiple widgets watching this at once share one listener rather than
/// each opening their own StreamBuilder<User?> on AuthService's stream -
/// which is exactly what AccountScreen and several dialogs were each doing
/// independently before this existed.
///
/// This is a deliberately small first step, not a full rewrite: the many
/// places elsewhere in the app that still call AuthService().currentUser
/// synchronously (favourite button, comment dialog, course enrollment,
/// etc.) are intentionally left alone for now. They work correctly as-is;
/// migrating them to watch this provider is real future work, worth doing
/// incrementally rather than in one large, riskier pass.
final authStateProvider = StreamProvider<User?>((ref) {
  return AuthService().authStateChanges;
});
