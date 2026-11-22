import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';

/// See content_courses_service.dart for why this file exists - same
/// reasoning, different domain slice: a church "I'm here" check-in, the
/// streak it builds, and the per-church tally shown on a user's profile.
///
/// Two different sensitivity levels on purpose. The exact log (which
/// church, exactly when) stays in the existing, already-locked-down
/// `users/{uid}/attendanceHistory` subcollection - owner-only, per
/// firestore.rules, same as bibleBookmarks/notes. What goes on the
/// user's own `users/{uid}` document (already publicly readable, since
/// that's where displayName/photoUrl already live) is just a summary:
/// a streak number, a total, and a per-church count - how often, not a
/// timestamped trail of where someone was and when. That split is what
/// makes a user's "checked in at" list on their profile (see the Users
/// list feature) safe to show without also exposing their movements.
/// The Sunday that starts the week containing [d], as a plain date key -
/// Mass attendance is a weekly rhythm, so the streak counts consecutive
/// weeks with at least one check-in (any church), not consecutive
/// calendar days. Top-level (not a method on the extension below) so
/// there's no ambiguity about calling a static extension member from
/// its own instance methods.
String _weekStartKey(DateTime d) {
  final daysSinceSunday = d.weekday % 7; // DateTime: Mon=1 ... Sun=7, so Sun%7=0
  final sunday = DateTime(d.year, d.month, d.day).subtract(Duration(days: daysSinceSunday));
  return '${sunday.year.toString().padLeft(4, '0')}-${sunday.month.toString().padLeft(2, '0')}-${sunday.day.toString().padLeft(2, '0')}';
}

extension ChurchCheckInService on FirestoreService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<void> checkInAtChurch({
    required String parishId,
    required String parishName,
    required String churchId,
    required String churchName,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to check in');
    final now = DateTime.now();
    final userRef = _db.collection('users').doc(uid);

    // Private detailed log - owner-only, unchanged from how
    // bibleBookmarks/notes already work under this same user doc.
    await userRef.collection('attendanceHistory').add({
      'parishId': parishId,
      'parishName': parishName,
      'churchId': churchId,
      'churchName': churchName,
      'at': FieldValue.serverTimestamp(),
    });

    final snap = await userRef.get();
    final data = snap.data() ?? {};
    final thisWeek = _weekStartKey(now);
    final lastWeek = data['lastCheckInWeek'] as String?;
    int streak = (data['checkInStreak'] as num?)?.toInt() ?? 0;
    if (lastWeek != thisWeek) {
      // Only the first check-in of a new week moves the streak - a
      // second visit the same week (e.g. Mass plus a weekday Devotion)
      // shouldn't double-count it.
      final previousWeek = _weekStartKey(now.subtract(const Duration(days: 7)));
      streak = (lastWeek == previousWeek) ? streak + 1 : 1;
    }

    final churches = Map<String, dynamic>.from(data['checkInChurches'] as Map? ?? {});
    final key = '${parishId}_$churchId';
    final existing = Map<String, dynamic>.from(churches[key] as Map? ?? {});
    churches[key] = {
      'parishId': parishId,
      'parishName': parishName,
      'churchId': churchId,
      'churchName': churchName,
      'count': ((existing['count'] as num?)?.toInt() ?? 0) + 1,
    };

    await userRef.set({
      'checkInStreak': streak,
      'lastCheckInWeek': thisWeek,
      'totalCheckIns': FieldValue.increment(1),
      'checkInChurches': churches,
    }, SetOptions(merge: true));
  }

  /// This week's key, for the UI to show "already checked in this week at
  /// X" rather than letting the button look like nothing happened.
  Future<String?> getLastCheckInWeek(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['lastCheckInWeek'] as String?;
  }

  bool isCurrentWeek(String weekKey) => weekKey == _weekStartKey(DateTime.now());

  /// The public summary for a profile: streak, running total, and every
  /// church this user has ever checked into with how many times -
  /// sorted most-visited first, since that's usually "their" church.
  Future<Map<String, dynamic>> getUserCheckInSummary(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    final raw = Map<String, dynamic>.from(data['checkInChurches'] as Map? ?? {});
    final churches = raw.values.map((v) => Map<String, dynamic>.from(v as Map)).toList()
      ..sort((a, b) => ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0));
    return {
      'streak': (data['checkInStreak'] as num?)?.toInt() ?? 0,
      'totalCheckIns': (data['totalCheckIns'] as num?)?.toInt() ?? 0,
      'churches': churches,
    };
  }
}
