import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firestore_service.dart';
import 'auth_provider.dart';

/// null means "no simulation - genuine Developer view." Any other value
/// means the UI should present itself as that role would see it, while
/// every actual Firestore read/write still happens as the real,
/// authenticated Developer underneath. This is a UI-level simulation
/// only - it can never make the rules themselves treat this account as
/// anything other than what it genuinely is, and isn't a substitute for
/// the real rules tests when checking whether permissions are actually
/// enforced correctly.
final viewAsRoleProvider = StateProvider<String?>((ref) => null);

/// 'loggedOut' | 'regularUser' | 'secretary' | 'priest' | 'superAdmin' |
/// 'designer' | 'auditor' - deliberately not including 'blocked', since
/// there's no real blocked-user feature in this app yet to simulate
/// honestly.
const availableViewAsRoles = ['loggedOut', 'regularUser', 'secretary', 'priest', 'superAdmin', 'designer', 'auditor'];

String viewAsRoleLabel(String? role) {
  switch (role) {
    case 'loggedOut': return 'Logged Out';
    case 'regularUser': return 'Regular User';
    case 'secretary': return 'Secretary';
    case 'priest': return 'Priest';
    case 'superAdmin': return 'Super Admin';
    case 'designer': return 'Designer';
    case 'auditor': return 'Auditor';
    default: return 'Developer (real)';
  }
}

/// Checked once - whether the actual signed-in account genuinely has
/// isDeveloper true. The debug icon and role switcher only ever show for
/// a real Developer; this is what decides that, not the simulated role
/// itself (which would be circular - you can't need Developer status to
/// simulate not having it).
final isRealDeveloperProvider = FutureProvider<bool>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  final uid = authState?.uid;
  if (uid == null) return false;
  final userDoc = await FirestoreService().getUserDoc(uid);
  return userDoc?['isDeveloper'] == true;
});

/// Same shape as isRealDeveloperProvider, but for Super Admin - gates
/// edit-mode affordances on content screens like Readings and Hymns,
/// matching who actually has write access to those collections per the
/// Firestore rules (isSuperAdmin(), which is also true for Developers).
final isRealSuperAdminProvider = FutureProvider<bool>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  final uid = authState?.uid;
  if (uid == null) return false;
  final userDoc = await FirestoreService().getUserDoc(uid);
  return userDoc?['isSuperAdmin'] == true || userDoc?['isDeveloper'] == true;
});