import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// One central place sensitive admin actions report to - deliberately
/// starting with the highest-stakes actions (role grants/revokes), not
/// every single CRUD operation across the whole app at once. That would
/// be a genuinely large undertaking touching dozens of call sites;
/// wiring the most security-critical ones first, then expanding
/// coverage deliberately, is the honest way to build this rather than
/// claiming comprehensive coverage that isn't actually there yet.
class AuditLogService {
  final _db = FirebaseFirestore.instance;

  Future<void> log({
    required String action, // e.g. 'user.grantSuperAdmin', 'church.delete'
    required String targetId,
    String? targetPath,
    String? detail,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // nothing to attribute this to - skip rather than log an anonymous action
    await _db.collection('auditLogs').add({
      'actorUid': user.uid,
      'actorEmail': user.email,
      'action': action,
      'targetId': targetId,
      'targetPath': targetPath,
      'detail': detail,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getRecentLogs({int limit = 100}) async {
    final snap = await _db.collection('auditLogs').orderBy('timestamp', descending: true).limit(limit).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }
}