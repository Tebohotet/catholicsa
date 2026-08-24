import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local, on-device storage for offline course reading - deliberately
/// separate from FirestoreService, since this is about what's cached on
/// this specific device, not remote data. Uses shared_preferences
/// (already a project dependency) rather than adding a new package -
/// JSON-encoded strings under course-specific keys, which is plenty for
/// text content at this app's actual scale.
///
/// Honest scope: this covers lesson text and structure. Images are
/// handled separately via CachedNetworkImage (also already a
/// dependency) - viewing an image once while online caches it to disk,
/// which is a real but different mechanism than what's here. There's no
/// explicit "pre-download every image" step in this first version.
class OfflineService {
  static String _courseKey(String parishId, String churchId, String courseId) =>
      'offline_course_${parishId}_${churchId}_$courseId';
  static const _pendingSyncKey = 'offline_pending_sync';

  Future<void> saveCourseForOffline({
    required String parishId,
    required String churchId,
    required String courseId,
    required String courseTitle,
    required List<Map<String, dynamic>> lessons,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'courseTitle': courseTitle,
      'lessons': lessons,
      'downloadedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_courseKey(parishId, churchId, courseId), json.encode(payload));
  }

  Future<Map<String, dynamic>?> getOfflineCourse(String parishId, String churchId, String courseId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_courseKey(parishId, churchId, courseId));
    if (raw == null) return null;
    return json.decode(raw) as Map<String, dynamic>;
  }

  Future<bool> isCourseDownloaded(String parishId, String churchId, String courseId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_courseKey(parishId, churchId, courseId));
  }

  Future<void> removeOfflineCourse(String parishId, String churchId, String courseId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_courseKey(parishId, churchId, courseId));
  }

  /// Queued when marking a lesson complete fails (offline, or a genuine
  /// network error) - replayed the next time syncPendingCompletions runs,
  /// which the course screen calls on load. Deliberately a simple
  /// retry-on-load approach rather than a reactive connectivity listener,
  /// which would need a new package this project doesn't already have.
  Future<void> queuePendingCompletion({
    required String parishId,
    required String churchId,
    required String courseId,
    required String lessonId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingSyncKey) ?? [];
    final entry = json.encode({'parishId': parishId, 'churchId': churchId, 'courseId': courseId, 'lessonId': lessonId});
    if (!raw.contains(entry)) {
      raw.add(entry);
      await prefs.setStringList(_pendingSyncKey, raw);
    }
  }

  Future<List<Map<String, dynamic>>> getPendingCompletions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingSyncKey) ?? [];
    return raw.map((e) => json.decode(e) as Map<String, dynamic>).toList();
  }

  Future<void> clearPendingCompletion({
    required String parishId,
    required String churchId,
    required String courseId,
    required String lessonId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingSyncKey) ?? [];
    final entry = json.encode({'parishId': parishId, 'churchId': churchId, 'courseId': courseId, 'lessonId': lessonId});
    raw.remove(entry);
    await prefs.setStringList(_pendingSyncKey, raw);
  }
}