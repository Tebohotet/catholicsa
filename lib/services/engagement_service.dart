import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// One central place every feature reports activity to, rather than
/// gamification logic scattered and duplicated across Bible, Courses,
/// Comments, and everywhere else it applies. Deliberately simple, honest
/// scope: client-side point awards with fixed values per activity type,
/// not a fraud-proof server-validated economy - reasonable for
/// gamification specifically (low-stakes, not financial), but a
/// determined person could inflate their own XP by repeatedly triggering
/// an action. Not pretending otherwise.
class EngagementService {
  final _db = FirebaseFirestore.instance;

  static const Map<String, int> _points = {
    'login': 10,
    'bibleChapterRead': 5,
    'comment': 3,
    'like': 1,
    'share': 2,
    'lessonComplete': 10,
    'courseComplete': 50,
  };

  static const Map<String, String> _badgeNames = {
    'week_streak': '7-Day Streak',
    'month_streak': '30-Day Streak',
    'century_xp': '100 XP',
    'bible_reader': 'Read 10 Bible Chapters',
    'first_course': 'First Course Completed',
  };

  static String get _todayKey {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// The one method everything else calls. Awards points for the given
  /// activity, updates the daily streak (once per day, not once per
  /// action - reading three chapters in one day doesn't triple-count the
  /// streak), and checks for newly-earned badges.
  Future<void> recordActivity(String activityType) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final points = _points[activityType];
    if (points == null) return; // an unrecognized activity type - fail quietly rather than throw over a gamification side-effect

    final ref = _db.collection('users').doc(uid);
    final doc = await ref.get();
    final data = doc.data() ?? {};

    final today = _todayKey;
    final lastActiveDate = data['lastActiveDate'] as String?;
    int streak = (data['streak'] as num?)?.toInt() ?? 0;

    if (lastActiveDate != today) {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayKey = '${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      streak = (lastActiveDate == yesterdayKey) ? streak + 1 : 1;
    }

    final updates = <String, dynamic>{
      'xp': FieldValue.increment(points),
      'streak': streak,
      'lastActiveDate': today,
    };

    if (activityType == 'bibleChapterRead') updates['chaptersRead'] = FieldValue.increment(1);
    if (activityType == 'courseComplete') updates['coursesCompleted'] = FieldValue.increment(1);

    await ref.set(updates, SetOptions(merge: true));
    await _checkBadges(uid);
  }

  Future<void> _checkBadges(String uid) async {
    final ref = _db.collection('users').doc(uid);
    final doc = await ref.get();
    final data = doc.data() ?? {};
    final existingBadges = List<String>.from(data['badges'] ?? []);
    final newBadges = <String>[];

    final streak = (data['streak'] as num?)?.toInt() ?? 0;
    final xp = (data['xp'] as num?)?.toInt() ?? 0;
    final chaptersRead = (data['chaptersRead'] as num?)?.toInt() ?? 0;
    final coursesCompleted = (data['coursesCompleted'] as num?)?.toInt() ?? 0;

    if (streak >= 7 && !existingBadges.contains('week_streak')) newBadges.add('week_streak');
    if (streak >= 30 && !existingBadges.contains('month_streak')) newBadges.add('month_streak');
    if (xp >= 100 && !existingBadges.contains('century_xp')) newBadges.add('century_xp');
    if (chaptersRead >= 10 && !existingBadges.contains('bible_reader')) newBadges.add('bible_reader');
    if (coursesCompleted >= 1 && !existingBadges.contains('first_course')) newBadges.add('first_course');

    if (newBadges.isNotEmpty) {
      await ref.update({'badges': FieldValue.arrayUnion(newBadges)});
    }
  }

  static String badgeName(String badgeId) => _badgeNames[badgeId] ?? badgeId;

  Future<Map<String, dynamic>> getMyStats() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    return {
      'xp': (data['xp'] as num?)?.toInt() ?? 0,
      'streak': (data['streak'] as num?)?.toInt() ?? 0,
      'chaptersRead': (data['chaptersRead'] as num?)?.toInt() ?? 0,
      'coursesCompleted': (data['coursesCompleted'] as num?)?.toInt() ?? 0,
      'badges': List<String>.from(data['badges'] ?? []),
    };
  }
}