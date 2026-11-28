import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// The project owner's own ask: "I normally use Console.WriteLine in C#...
/// I want to catch where every process is failing... Lets have that in
/// our coding so that we just go to the logs and see if all went well."
///
/// A plain print()/debugPrint() disappears the moment the tab closes - no
/// use to anyone after the fact on a deployed web app, and no use at all
/// for catching what a GUEST visitor's browser hit, since nobody's
/// watching their console. This writes to a real Firestore collection
/// instead, so a Super Admin can open the new Logs page (see
/// logs_section.dart) at any time afterward and see exactly what broke,
/// where, and for whom - the actual point of the ask.
///
/// Two ways this gets filled: automatically, via the global handlers
/// wired up in main.dart (FlutterError.onError, PlatformDispatcher's own
/// onError, and runZonedGuarded) - these catch crashes nobody thought to
/// add a manual log line for, including ones hit by signed-out visitors
/// just browsing Mass times, which is most of this app's real traffic.
/// And by hand, anywhere worth tracking deliberately - call
/// LogService.log(...) the same way you'd reach for Console.WriteLine.
///
/// Deliberately left open to writes from anyone, signed in or not (see
/// firestore.rules' appLogs rule) - most errors happen to guests, and a
/// rule requiring sign-in would miss exactly the traffic this exists to
/// watch. Known tradeoff, not an oversight: nothing stops someone from
/// writing junk into this collection. Worth adding real rate-limiting or
/// a size cap later if it's ever actually abused - not done here since
/// there's no sign it's needed yet.
class LogService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> log(
    String message, {
    String level = 'info', // 'info' | 'warning' | 'error'
    String? source, // which screen/service this came from
    String? stack,
  }) async {
    debugPrint('[$level]${source != null ? ' [$source]' : ''} $message');
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _db.collection('appLogs').add({
        'level': level,
        'source': source,
        'message': message.length > 3000 ? message.substring(0, 3000) : message,
        'stack': (stack != null && stack.length > 2000) ? stack.substring(0, 2000) : stack,
        'userId': user?.uid,
        'userEmail': user?.email,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Logging itself must never crash the app it's trying to watch -
      // silently no-ops rather than surfacing a second error on top of
      // whatever this call was trying to report in the first place.
    }
  }

  static Future<void> error(String message, {String? source, Object? error, StackTrace? stack}) {
    return log(
      error != null ? '$message: $error' : message,
      level: 'error',
      source: source,
      stack: stack?.toString(),
    );
  }

  static Future<List<Map<String, dynamic>>> getRecentLogs({int limit = 200}) async {
    final snap = await _db.collection('appLogs').orderBy('timestamp', descending: true).limit(limit).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Deletes up to 500 of the most recent entries in one batch - plenty
  /// for a manual "clear the board" between test passes. Not a true
  /// delete-everything (Firestore has no bulk-delete-by-query from the
  /// client); tap it again if there's ever more than 500 at once.
  static Future<void> clearAll() async {
    final snap = await _db.collection('appLogs').limit(500).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}
