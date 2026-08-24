import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../models/liturgical_day.dart';
import 'firestore_service.dart';

/// Split out of firestore_service.dart specifically to reduce the size
/// of that file - it had grown large enough that it was the direct
/// cause of several real edit mistakes this session (a str_replace
/// clobbering a neighboring method's declaration, caught each time only
/// by checking method counts immediately after). Extension on
/// FirestoreService rather than a separate class, so every call site
/// across the whole app - FirestoreService().getCourses(...) etc. -
/// works completely unchanged.
extension ContentCoursesService on FirestoreService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  // ---------- Liturgical readings admin (Super Admin only, per firestore.rules) ----------
  // Doc ID is the date string itself (YYYY-MM-DD). onEdit always writes
  // to the original date, regardless of what's in the form's date field
  // during an edit - avoids an accidental doc rename if someone edits the
  // date field on an existing entry rather than creating a new one.

  Future<List<Map<String, dynamic>>> getAllLiturgicalReadings() async {
    final snap = await _db.collection('liturgicalReadings').get();
    return snap.docs.map((d) {
      final data = d.data();
      final en = (data['readings'] as Map<String, dynamic>?)?['en'] as Map<String, dynamic>? ?? {};
      return {
        'id': d.id,
        'date': d.id,
        'liturgicalTitle': data['liturgicalTitle'] ?? '',
        'sundayCycle': data['sundayCycle'],
        'weekdayCycle': data['weekdayCycle'],
        'firstReading': en['firstReading'] ?? '',
        'psalm': en['psalm'] ?? '',
        'psalmResponse': en['psalmResponse'] ?? '',
        'secondReading': en['secondReading'] ?? '',
        'gospelAcclamation': en['gospelAcclamation'] ?? '',
        'gospel': en['gospel'] ?? '',
        'entranceAntiphon': en['entranceAntiphon'] ?? '',
        'communionAntiphon': en['communionAntiphon'] ?? '',
        'reflectionTitle': en['reflectionTitle'] ?? '',
        'reflectionBody': en['reflectionBody'] ?? '',
        'themedBoxTitle': en['themedBoxTitle'] ?? '',
        'themedBoxBody': en['themedBoxBody'] ?? '',
        'prayersIntro': en['prayersIntro'] ?? '',
        'prayersResponse': en['prayersResponse'] ?? '',
        'petitions': List<String>.from(en['petitions'] ?? []),
        'prayersClosing': en['prayersClosing'] ?? '',
        'verseForTheDay': en['verseForTheDay'] ?? '',
        'verseForTheDayCitation': en['verseForTheDayCitation'] ?? '',
        'source': en['source'] ?? '',
      };
    }).toList();
  }

  Future<void> addLiturgicalReading(Map<String, dynamic> data) async {
    final date = data['date'] as String;
    await _saveLiturgicalReading(date, data);
  }

  /// Syncs reading citations (never full text) from cpbjr's Catholic
  /// Readings API for a whole year - fills in missing firstReading/
  /// psalm/secondReading/gospel citations without ever touching an
  /// existing manual entry, independent of whether a saint exists for
  /// that date.
  Future<Map<String, dynamic>> syncDailyReadingsCitations({required int year}) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'syncDailyReadingsCitations',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 540)),
    );
    final result = await callable.call({'year': year});
    return Map<String, dynamic>.from(result.data);
  }

  /// Citations only, from USCCB's own calendar and readings pages -
  /// scoped by month, since it scrapes that month's real calendar page
  /// first to resolve each date's actual URL (some dates use a slug
  /// instead of the predictable pattern), then follows each real link.
  /// Correctly captures multi-reading Vigil days into vigilReadings.
  Future<Map<String, dynamic>> syncUsccbCitations({required int year, required int month}) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'syncUsccbCitations',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 540)),
    );
    final result = await callable.call({'year': year, 'month': month});
    return Map<String, dynamic>.from(result.data);
  }

  Future<void> updateLiturgicalReading(String date, Map<String, dynamic> data) async {
    await _saveLiturgicalReading(date, data);
  }

  /// Updates exactly one reading field in place, via dot-notation, so an
  /// editor tapping "Entrance Antiphon" in the reader view and saving a
  /// change doesn't touch anything else on the document - unlike
  /// _saveLiturgicalReading, which expects the full form's worth of data.
  Future<void> updateReadingFieldValue(String date, String fieldKey, String value) async {
    await _db.collection('liturgicalReadings').doc(date).update({
      'readings.en.$fieldKey': value,
    });
  }

  /// Rewrites the whole vigilReadings array - Firestore has no way to
  /// update one array element by index directly, so any add/edit/
  /// remove on a single vigil reading means resubmitting the entire
  /// list, same as the admin form already does.
  Future<void> updateVigilReadings(String date, List<Map<String, dynamic>> vigilReadings) async {
    // set(merge: true) rather than update() - update() throws if the
    // document doesn't already exist yet, a real risk for any date
    // that hasn't been synced or manually created before this was the
    // first edit made to it.
    await _db.collection('liturgicalReadings').doc(date).set({
      'vigilReadings': vigilReadings,
    }, SetOptions(merge: true));
  }

  /// Toggles a single field's hidden status - the underlying text stays
  /// in Firestore either way, so un-hiding is instant and never loses
  /// what was there.
  Future<void> setReadingFieldHidden(String date, String fieldKey, bool hidden) async {
    await _db.collection('liturgicalReadings').doc(date).update({
      'readings.en.hiddenFields': hidden ? FieldValue.arrayUnion([fieldKey]) : FieldValue.arrayRemove([fieldKey]),
    });
  }

  Future<void> _saveLiturgicalReading(String date, Map<String, dynamic> data) async {
    String? emptyToNull(String? key) => (data[key] as String?)?.isEmpty ?? true ? null : data[key];
    await _db.collection('liturgicalReadings').doc(date).set({
      'liturgicalTitle': data['liturgicalTitle'],
      'sundayCycle': emptyToNull('sundayCycle'),
      'weekdayCycle': emptyToNull('weekdayCycle'),
      'readings': {
        'en': {
          'firstReading': data['firstReading'],
          'psalm': emptyToNull('psalm'),
          'psalmResponse': emptyToNull('psalmResponse'),
          'secondReading': emptyToNull('secondReading'),
          'gospelAcclamation': emptyToNull('gospelAcclamation'),
          'gospel': data['gospel'],
          'entranceAntiphon': emptyToNull('entranceAntiphon'),
          'communionAntiphon': emptyToNull('communionAntiphon'),
          'reflectionTitle': emptyToNull('reflectionTitle'),
          'reflectionBody': emptyToNull('reflectionBody'),
          'themedBoxTitle': emptyToNull('themedBoxTitle'),
          'themedBoxBody': emptyToNull('themedBoxBody'),
          'prayersIntro': emptyToNull('prayersIntro'),
          'prayersResponse': emptyToNull('prayersResponse'),
          'petitions': data['petitions'] ?? [],
          'prayersClosing': emptyToNull('prayersClosing'),
          'verseForTheDay': emptyToNull('verseForTheDay'),
          'verseForTheDayCitation': emptyToNull('verseForTheDayCitation'),
          'source': data['source'],
        },
      },
    });
  }

  Future<void> deleteLiturgicalReading(String date) async {
    await _db.collection('liturgicalReadings').doc(date).delete();
  }

  /// Reads from feastCalendar, populated by the syncFeastCalendar Cloud
  /// Function - a real, synced feast (name, rank, liturgical details),
  /// separate from getLiturgicalDay which reads the actual reading
  /// citations. A date can have one without the other.
  Future<Map<String, dynamic>?> getFeastForDate(DateTime date) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final doc = await _db.collection('feastCalendar').doc(dateStr).get();
    if (!doc.exists) return null;
    return {'id': doc.id, ...doc.data()!};
  }

  Future<LiturgicalDay?> getLiturgicalDay(DateTime date) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    // Timeout kept deliberately - a genuine stuck-forever request with no
    // error is nearly undiagnosable from the outside. This turns it into
    // a concrete, visible error message instead of an infinite spinner.
    // Widened from 10s to 20s - the inline scripture feature added several
    // concurrent Firestore reads per date view (independent requests, not
    // blocking this one directly, but genuinely competing for the same
    // connection on a slower network), which could push an otherwise-fine
    // connection past a tighter timeout.
    final doc = await _db.collection('liturgicalReadings').doc(dateStr).get().timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw Exception('Timed out waiting for readings ($dateStr) - check your connection or Firebase config.'),
    );
    if (!doc.exists) return null;
    return LiturgicalDay.fromFirestore(dateStr, doc.data()!);
  }

  // ---------- Scoped reading overrides (wedding, funeral, feast - not
  // the ordinary reading for that date) ----------

  String _scopedReadingKey({String? eventId, String? parishId}) {
    if (eventId != null) return 'event_$eventId';
    if (parishId != null) return 'parish_$parishId';
    throw ArgumentError('Provide either eventId or parishId');
  }

  /// The actual mechanism behind "a wedding can't use the same readings
  /// as the day" - checks for a scoped override first (this specific
  /// event, or this specific parish), and only falls back to the
  /// ordinary date reading if neither exists. Event takes priority over
  /// parish, since a specific wedding's chosen readings are more
  /// specific than "this parish always uses X for feast days."
  Future<LiturgicalDay?> getLiturgicalDayForContext(DateTime date, {String? eventId, String? parishId}) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (eventId != null) {
      final scoped = await _getScopedReadingDoc(dateStr, _scopedReadingKey(eventId: eventId));
      if (scoped != null) return scoped;
    }
    if (parishId != null) {
      final scoped = await _getScopedReadingDoc(dateStr, _scopedReadingKey(parishId: parishId));
      if (scoped != null) return scoped;
    }
    return getLiturgicalDay(date);
  }

  Future<LiturgicalDay?> _getScopedReadingDoc(String dateStr, String scopeKey) async {
    final doc = await _db.collection('liturgicalReadings').doc(dateStr).collection('scoped').doc(scopeKey).get();
    if (!doc.exists) return null;
    return LiturgicalDay.fromFirestore(dateStr, doc.data()!);
  }

  Future<void> setScopedReading({
    required DateTime date,
    String? eventId,
    String? parishId,
    required String liturgicalTitle,
    required String firstReading,
    String? psalm,
    String? secondReading,
    required String gospel,
    String? source,
  }) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final scopeKey = _scopedReadingKey(eventId: eventId, parishId: parishId);
    await _db.collection('liturgicalReadings').doc(dateStr).collection('scoped').doc(scopeKey).set({
      'liturgicalTitle': liturgicalTitle,
      'readings': {
        'en': {
          'firstReading': firstReading,
          'psalm': (psalm?.isEmpty ?? true) ? null : psalm,
          'secondReading': (secondReading?.isEmpty ?? true) ? null : secondReading,
          'gospel': gospel,
          'source': source,
        },
      },
    });
  }

  Future<void> deleteScopedReading(DateTime date, {String? eventId, String? parishId}) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final scopeKey = _scopedReadingKey(eventId: eventId, parishId: parishId);
    await _db.collection('liturgicalReadings').doc(dateStr).collection('scoped').doc(scopeKey).delete();
  }

  // ---------- Courses / Lessons / Enrollments ----------

  /// devOnly mirrors the FeatureGate/dev flag philosophy but per-item -
  /// a specific course still being written, not a whole platform
  /// feature. A Developer or Super Admin sees it regardless (same
  /// "preview" trust tier as isFeatureVisible); anyone else never does,
  /// even if it's otherwise published.
  Future<bool> _canViewDevOnlyContent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final user = await getUserDoc(uid);
    return user?['isSuperAdmin'] == true || user?['isDeveloper'] == true ||
        user?['isDesigner'] == true || user?['isAuditor'] == true;
  }

  Future<List<Map<String, dynamic>>> getCourses(String parishId, String churchId, {bool onlyPublished = true}) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').get();
    final all = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    if (!onlyPublished) return all;
    final published = all.where((c) => c['status'] == 'published').toList();
    final canSeeDevOnly = await _canViewDevOnlyContent();
    return canSeeDevOnly ? published : published.where((c) => c['devOnly'] != true).toList();
  }

  Future<Map<String, dynamic>> getCourse(String parishId, String churchId, String courseId) async {
    final doc = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId).get();
    return {'id': doc.id, ...doc.data()!};
  }

  Future<void> addCourse({
    required String parishId,
    required String churchId,
    required String title,
    required String description,
    required String catechistName,
    String? meetingLink,
    bool devOnly = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').add({
      'title': title,
      'description': description,
      'catechistName': catechistName,
      'meetingLink': meetingLink,
      'status': 'draft',
      'devOnly': devOnly,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCourseStatus({
    required String parishId,
    required String churchId,
    required String courseId,
    required String status,
    String? reviewNotes,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .update({'status': status, 'reviewNotes': reviewNotes});
  }

  Future<List<Map<String, dynamic>>> getLessons(String parishId, String churchId, String courseId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').orderBy('order').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// blocks is the real content model now - a list of {type, text?,
  /// imageUrl?, caption?} maps, ordered as written. content stays as a
  /// fallback field only, kept in sync as a plain-text join of the
  /// blocks' text, so anything still reading the old field (search
  /// indexing, notifications, etc.) doesn't silently break.
  Future<void> addLesson({
    required String parishId,
    required String churchId,
    required String courseId,
    required String title,
    required List<Map<String, dynamic>> blocks,
    required int order,
  }) async {
    final content = blocks.where((b) => b['type'] != 'image').map((b) => b['text'] ?? '').join('\n\n');
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').add({'title': title, 'blocks': blocks, 'content': content, 'order': order, 'verified': false});
  }

  /// Resets verified to false deliberately - a verified lesson means a
  /// priest reviewed this exact content; that review stops being true the
  /// moment the content changes, so it shouldn't silently stay "verified"
  /// against text nobody's actually checked.
  Future<void> updateLesson({
    required String parishId,
    required String churchId,
    required String courseId,
    required String lessonId,
    required String title,
    required List<Map<String, dynamic>> blocks,
    required int order,
  }) async {
    final content = blocks.where((b) => b['type'] != 'image').map((b) => b['text'] ?? '').join('\n\n');
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').doc(lessonId)
        .update({'title': title, 'blocks': blocks, 'content': content, 'order': order, 'verified': false});
  }

  /// Reorders every lesson in one batch write - used by the new
  /// drag-to-reorder lesson list, replacing manual order-number typing.
  Future<void> reorderLessons({
    required String parishId,
    required String churchId,
    required String courseId,
    required List<String> orderedLessonIds,
  }) async {
    final batch = _db.batch();
    for (var i = 0; i < orderedLessonIds.length; i++) {
      final ref = _db
          .collection('parishes').doc(parishId)
          .collection('churches').doc(churchId)
          .collection('courses').doc(courseId)
          .collection('lessons').doc(orderedLessonIds[i]);
      batch.update(ref, {'order': i + 1});
    }
    await batch.commit();
  }

  Future<String> uploadLessonImage(XFile file) async {
    final bytes = await file.readAsBytes();
    final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
    final storagePath = 'lessons/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<void> deleteLesson({
    required String parishId,
    required String churchId,
    required String courseId,
    required String lessonId,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').doc(lessonId)
        .delete();
  }

  /// Same "same can work on the course" verification idea, one level
  /// down - a course being published doesn't automatically mean every
  /// lesson in it has been individually checked. A priest can verify
  /// lessons one at a time as they're reviewed.
  Future<void> setLessonVerified({
    required String parishId,
    required String churchId,
    required String courseId,
    required String lessonId,
    required bool verified,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').doc(lessonId)
        .update({'verified': verified});
  }

  // ---------- Quizzes (gate lesson completion, server-graded) ----------
  //
  // Branching is deliberately binary (if correct -> question X, if wrong
  // -> question Y) rather than per-option - covers the real use case
  // (advance vs. remedial path) without needing a full branching-graph
  // author UI. Question selection for a randomized pool happens
  // client-side for the display order/subset, then that exact list is
  // submitted and graded against - a determined student could in theory
  // pick a favourable subset before submitting, which is a real, honest
  // limitation worth naming rather than pretending this is exam-grade
  // tamper-proof. For a parish course quiz, that's a proportionate
  // tradeoff against the real complexity of a server-pinned quiz session.

  Future<Map<String, dynamic>?> getPublicQuiz(String parishId, String churchId, String courseId, String lessonId) async {
    final doc = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').doc(lessonId)
        .collection('quiz').doc('public').get();
    return doc.exists ? doc.data() : null;
  }

  /// Admin authoring writes both documents from one form - the public
  /// question/option text, and separately the answer key. Never call
  /// this from anything a student can reach; the rules also enforce this
  /// server-side regardless.
  Future<void> saveQuizForLesson({
    required String parishId,
    required String churchId,
    required String courseId,
    required String lessonId,
    required List<Map<String, dynamic>> questions, // each: {id, type, text, options?, items?, nextIfCorrect?, nextIfWrong?}
    required Map<String, dynamic> answers, // questionId -> {correctIndex} or {correctOrder}
    bool randomizeOrder = false,
    int? questionPoolSize,
    double passingScorePercent = 70,
  }) async {
    final lessonRef = _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').doc(lessonId);
    await lessonRef.collection('quiz').doc('public').set({
      'questions': questions,
      'randomizeOrder': randomizeOrder,
      'questionPoolSize': questionPoolSize,
      'passingScorePercent': passingScorePercent,
    });
    await lessonRef.collection('quiz').doc('answerKey').set({'answers': answers});
  }

  Future<void> deleteQuizForLesson(String parishId, String churchId, String courseId, String lessonId) async {
    final lessonRef = _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').doc(lessonId);
    await lessonRef.collection('quiz').doc('public').delete();
    await lessonRef.collection('quiz').doc('answerKey').delete();
  }

  /// Writes only raw answers - score/passed are never set here, both by
  /// design (rules block it) and because grading has to happen server-side
  /// against the answer key this client can't read.
  Future<void> submitQuizAttempt({
    required String parishId,
    required String churchId,
    required String courseId,
    required String lessonId,
    required Map<String, dynamic> answers,
    required List<String> questionsShown,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to take this quiz');
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').doc(lessonId)
        .collection('quizAttempts').doc(uid)
        .set({
      'studentId': uid,
      'answers': answers,
      'questionsShown': questionsShown,
      'submittedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getQuizAttempt(String parishId, String churchId, String courseId, String lessonId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').doc(lessonId)
        .collection('quizAttempts').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  /// Listens for the attempt to become graded after submission - the
  /// grading Cloud Function runs asynchronously on the write trigger, so
  /// polling with a guessed delay would be unreliable; this waits for the
  /// actual result instead.
  Stream<Map<String, dynamic>?> streamQuizAttempt(String parishId, String churchId, String courseId, String lessonId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('lessons').doc(lessonId)
        .collection('quizAttempts').doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? doc.data() : null);
  }

  /// Real-time single-question check for branching mid-quiz - see the
  /// Cloud Function itself for why this exists as a narrow callable
  /// rather than sending the answer key to the client.
  /// Returns the full diagnostic result, not just success/failure - the
  /// whole point of the self-diagnosing design is that the admin
  /// actually sees what needed review, not just a generic "done."
  Future<Map<String, dynamic>> syncFeastCalendar({required int year, String? nationalCalendar}) async {
    final result = await FirebaseFunctions.instance.httpsCallable('syncFeastCalendar').call({
      'year': year, 'nationalCalendar': nationalCalendar,
    });
    return Map<String, dynamic>.from(result.data);
  }

  Future<bool> checkQuizAnswer({
    required String parishId,
    required String churchId,
    required String courseId,
    required String lessonId,
    required String questionId,
    required dynamic answer,
  }) async {
    final result = await FirebaseFunctions.instance.httpsCallable('checkQuizAnswer').call({
      'parishId': parishId, 'churchId': churchId, 'courseId': courseId,
      'lessonId': lessonId, 'questionId': questionId, 'answer': answer,
    });
    return result.data['correct'] == true;
  }

  Future<Map<String, dynamic>?> getEnrollment(String parishId, String churchId, String courseId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('enrollments').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> enrollInCourse(String parishId, String churchId, String courseId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to enroll');
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('enrollments').doc(uid)
        .set({'enrolledAt': FieldValue.serverTimestamp(), 'completedLessonIds': <String>[]});
  }

  Future<void> markLessonComplete(String parishId, String churchId, String courseId, String lessonId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('enrollments').doc(uid)
        .update({'completedLessonIds': FieldValue.arrayUnion([lessonId])});
  }

  // ---------- Bible - genuinely multi-translation. Starting with
  // Douay-Rheims (Challoner Revision, confirmed public domain), designed
  // so a licensed translation later is just a new bibleTranslations doc,
  // never a schema change. ----------

  Future<List<Map<String, dynamic>>> getBibleTranslations() async {
    final snap = await _db.collection('bibleTranslations').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> addBibleTranslation({
    required String code,
    required String name,
    required bool isPublicDomain,
    String? licenseNote,
  }) async {
    await _db.collection('bibleTranslations').doc(code).set({
      'name': name,
      'isPublicDomain': isPublicDomain,
      'licenseNote': licenseNote,
    });
  }

  /// One document per chapter - matches how someone actually reads
  /// scripture (a whole chapter at a time), and keeps this to one
  /// Firestore read per chapter view rather than one per verse.
  Future<Map<String, dynamic>?> getBibleChapter({
    required String translationCode,
    required String bookCode,
    required int chapter,
  }) async {
    final doc = await _db
        .collection('bibleTranslations').doc(translationCode)
        .collection('books').doc(bookCode)
        .collection('chapters').doc(chapter.toString())
        .get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> setBibleChapter({
    required String translationCode,
    required String bookCode,
    required int chapter,
    required Map<String, String> verses, // {"1": "In the beginning...", "2": "..."}
  }) async {
    await _db
        .collection('bibleTranslations').doc(translationCode)
        .collection('books').doc(bookCode)
        .collection('chapters').doc(chapter.toString())
        .set({'verses': verses, 'translationCode': translationCode, 'bookCode': bookCode, 'chapter': chapter});
  }

  // ---------- Bible bookmarks - personal, owner-only ----------

  Future<void> addBibleBookmark({
    required String translationCode,
    required String bookCode,
    required String bookName,
    required int chapter,
    int? verse,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final id = '${translationCode}_${bookCode}_$chapter${verse != null ? '_$verse' : ''}';
    await _db.collection('users').doc(uid).collection('bibleBookmarks').doc(id).set({
      'translationCode': translationCode,
      'bookCode': bookCode,
      'bookName': bookName,
      'chapter': chapter,
      'verse': verse,
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeBibleBookmark(String translationCode, String bookCode, int chapter, {int? verse}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final id = '${translationCode}_${bookCode}_$chapter${verse != null ? '_$verse' : ''}';
    await _db.collection('users').doc(uid).collection('bibleBookmarks').doc(id).delete();
  }

  Future<bool> isBibleBookmarked(String translationCode, String bookCode, int chapter, {int? verse}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final id = '${translationCode}_${bookCode}_$chapter${verse != null ? '_$verse' : ''}';
    final doc = await _db.collection('users').doc(uid).collection('bibleBookmarks').doc(id).get();
    return doc.exists;
  }

  Future<List<Map<String, dynamic>>> getMyBibleBookmarks() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final snap = await _db.collection('users').doc(uid).collection('bibleBookmarks').orderBy('savedAt', descending: true).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Server-side brute-force scan, honestly - see the Cloud Function's
  /// own comment for why this is fine now and won't scale indefinitely.
  Future<Map<String, dynamic>> searchBibleVerses({required String translationCode, required String query}) async {
    final result = await FirebaseFunctions.instance.httpsCallable('searchBibleVerses').call({
      'translationCode': translationCode, 'query': query,
    });
    return Map<String, dynamic>.from(result.data);
  }

  Future<List<Map<String, dynamic>>> getBibleSyncSources() async {
    final result = await FirebaseFunctions.instance.httpsCallable('getBibleSyncSources').call();
    return List<Map<String, dynamic>>.from(result.data);
  }

  /// Real, server-side sync of a whole Bible translation - see the
  /// Cloud Function's own comments for the actual fetch/parse/write
  /// logic. This can genuinely take minutes (73 books, ~1,300+
  /// chapters), hence the generous timeout matching the function's own
  /// 540s limit.
  Future<Map<String, dynamic>> syncFullBible({required String sourceId}) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'syncFullBible',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 540)),
    );
    final result = await callable.call({'sourceId': sourceId});
    return Map<String, dynamic>.from(result.data);
  }

  // ---------- Bible cross-references - the mechanism, not the content.
  // No actual reference pairs exist yet; this just makes adding and
  // showing them possible once someone curates real ones. ----------

  Future<void> addBibleCrossReference({
    required String fromBookCode, required int fromChapter, int? fromVerse,
    required String toBookCode, required int toChapter, int? toVerse,
    String? note,
  }) async {
    await _db.collection('bibleCrossReferences').add({
      'fromBookCode': fromBookCode, 'fromChapter': fromChapter, 'fromVerse': fromVerse,
      'toBookCode': toBookCode, 'toChapter': toChapter, 'toVerse': toVerse,
      'note': note,
    });
  }

  Future<void> deleteBibleCrossReference(String id) async {
    await _db.collection('bibleCrossReferences').doc(id).delete();
  }

  Future<List<Map<String, dynamic>>> getAllBibleCrossReferences() async {
    final snap = await _db.collection('bibleCrossReferences').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Queried by book+chapter directly (not a collection-group scan) -
  /// checks both directions, since a reference from A→B should surface
  /// when reading either A or B.
  Future<List<Map<String, dynamic>>> getCrossReferencesForChapter(String bookCode, int chapter) async {
    final fromSnap = await _db.collection('bibleCrossReferences')
        .where('fromBookCode', isEqualTo: bookCode).where('fromChapter', isEqualTo: chapter).get();
    final toSnap = await _db.collection('bibleCrossReferences')
        .where('toBookCode', isEqualTo: bookCode).where('toChapter', isEqualTo: chapter).get();
    return [
      ...fromSnap.docs.map((d) => {'id': d.id, 'direction': 'to', ...d.data()}),
      ...toSnap.docs.map((d) => {'id': d.id, 'direction': 'from', ...d.data()}),
    ];
  }

  Future<List<Map<String, dynamic>>> getConfessionBookingRequests(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('confessionBookingRequests')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> updateBookingStatus(String parishId, String churchId, String requestId, String status) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('confessionBookingRequests').doc(requestId)
        .update({'status': status});
  }

  Future<List<Map<String, dynamic>>> getReports(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> updateReportStatus(String parishId, String churchId, String reportId, String status) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('reports').doc(reportId)
        .update({'status': status});
  }

  Future<void> addDevotion({
    required String parishId, required String churchId,
    required String name, required String dayOfWeek, required String time,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('devotions').add({'name': name, 'dayOfWeek': dayOfWeek, 'time': time});
  }

  Future<void> deleteDevotion(String parishId, String churchId, String devotionId) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('devotions').doc(devotionId).delete();
  }

  /// Church-level association only - the parish-wide list (CWL, SVP, etc.)
  /// isn't editable from here yet, since it's scoped to the whole parish,
  /// not a single church like everything else in this panel.
  /// Church-level associations only, unlike getAssociations() which merges
  /// in the parish-wide list too - needed here specifically because this
  /// admin section can only safely edit/delete church-scoped entries, and
  /// the merged list gives no way to tell which is which.
  Future<List<Map<String, dynamic>>> getChurchAssociationsOnly(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('associations').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> addChurchAssociation({
    required String parishId, required String churchId,
    required String name, String? purpose, String? contactPerson, String? meetingDay, String? meetingTime,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('associations').add({
      'name': name, 'purpose': purpose, 'contactPerson': contactPerson,
      'meetingDay': meetingDay, 'meetingTime': meetingTime,
    });
  }

  // ---------- Parish-wide associations (CWL, SVP, etc.) - visible across
  // every church in the parish, distinct from a church-specific group
  // like one choir. Same shape as church-level associations, different
  // collection depth. ----------

  Future<List<Map<String, dynamic>>> getParishAssociations(String parishId) async {
    final snap = await _db.collection('parishes').doc(parishId).collection('associations').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> addParishAssociation({
    required String parishId,
    required String name, String? purpose, String? contactPerson, String? meetingDay, String? meetingTime,
  }) async {
    await _db.collection('parishes').doc(parishId).collection('associations').add({
      'name': name, 'purpose': purpose, 'contactPerson': contactPerson,
      'meetingDay': meetingDay, 'meetingTime': meetingTime,
    });
  }

  Future<void> updateParishAssociation({
    required String parishId, required String associationId,
    required String name, String? purpose, String? contactPerson, String? meetingDay, String? meetingTime,
  }) async {
    await _db.collection('parishes').doc(parishId).collection('associations').doc(associationId).update({
      'name': name, 'purpose': purpose, 'contactPerson': contactPerson,
      'meetingDay': meetingDay, 'meetingTime': meetingTime,
    });
  }

  Future<void> deleteParishAssociation(String parishId, String associationId) async {
    await _db.collection('parishes').doc(parishId).collection('associations').doc(associationId).delete();
  }

  Future<void> updateChurchAssociation({
    required String parishId, required String churchId, required String associationId,
    required String name, String? purpose, String? contactPerson, String? meetingDay, String? meetingTime,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('associations').doc(associationId).update({
      'name': name, 'purpose': purpose, 'contactPerson': contactPerson,
      'meetingDay': meetingDay, 'meetingTime': meetingTime,
    });
  }

  Future<void> deleteChurchAssociation(String parishId, String churchId, String associationId) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('associations').doc(associationId).delete();
  }

  Future<void> addNotice({
    required String parishId, required String churchId, required String title, required String body,
    String? associationId,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('notices').add({'title': title, 'body': body, 'associationId': associationId});
  }

  /// An association's detail page shows its own events PLUS every
  /// parish-wide one (associationId null) - "seen by every association"
  /// means a global event cascades down to appear here too, not just in
  /// the main Events list. Filtered client-side rather than via a
  /// Firestore query, since whereIn's handling of a literal null value
  /// isn't reliable enough to build this on - fine at the event volumes
  /// a single parish actually has.
  Future<List<Map<String, dynamic>>> getEventsForAssociation(String parishId, String associationId) async {
    final churchesSnap = await _db.collection('parishes').doc(parishId).collection('churches').get();
    final results = <Map<String, dynamic>>[];
    for (final churchDoc in churchesSnap.docs) {
      final eventsSnap = await churchDoc.reference.collection('events').get();
      for (final e in eventsSnap.docs) {
        final data = e.data();
        if (data['associationId'] == associationId || data['associationId'] == null) {
          results.add({'id': e.id, 'churchId': churchDoc.id, 'churchName': churchDoc.data()['name'], ...data});
        }
      }
    }
    results.sort((a, b) => (a['date'] as Timestamp).compareTo(b['date'] as Timestamp));
    return results;
  }

  Future<List<Map<String, dynamic>>> getNoticesForAssociation(String parishId, String associationId) async {
    final churchesSnap = await _db.collection('parishes').doc(parishId).collection('churches').get();
    final results = <Map<String, dynamic>>[];
    for (final churchDoc in churchesSnap.docs) {
      final noticesSnap = await churchDoc.reference.collection('notices').get();
      for (final n in noticesSnap.docs) {
        final data = n.data();
        if (data['associationId'] == associationId || data['associationId'] == null) {
          results.add({'id': n.id, 'churchId': churchDoc.id, 'churchName': churchDoc.data()['name'], ...data});
        }
      }
    }
    return results;
  }

  Future<void> deleteNotice(String parishId, String churchId, String noticeId) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('notices').doc(noticeId).delete();
  }

  Future<void> addEvent({
    required String parishId, required String churchId,
    required String title, required String description,
    required DateTime date, required String time, String? category, bool showInNotices = false,
    String? associationId,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('events').add({
      'title': title, 'description': description,
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'time': time, 'category': category, 'showInNotices': showInNotices,
      'associationId': associationId,
    });
  }

  Future<void> updateEvent({
    required String parishId, required String churchId, required String eventId,
    required String title, required String description,
    required DateTime date, required String time, String? category, bool showInNotices = false,
    String? associationId,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('events').doc(eventId).update({
      'title': title, 'description': description,
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'time': time, 'category': category, 'showInNotices': showInNotices,
      'associationId': associationId,
    });
  }

  Future<void> deleteEvent(String parishId, String churchId, String eventId) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('events').doc(eventId).delete();
  }

  // ---------- Parish-wide summaries (aggregated from its churches) ----------
  // Same aggregation shape works one level up too: a future Diocese summary
  // would loop over its parishes the same way this loops over its churches.
  // Honest limitation to flag before reusing this at Diocese/Province/
  // National scale: this walks every child with its own query, which is
  // fine for a handful of churches per parish, but would need real
  // denormalization or a Cloud Function rollup once a diocese has dozens
  // of parishes - not a problem yet, worth knowing before it is one.

  Future<List<Map<String, dynamic>>> getParishNotices(String parishId) async {
    final churches = await getChurches(parishId);
    final results = <Map<String, dynamic>>[];
    for (final c in churches) {
      final notices = await getNotices(parishId, c.id);
      for (final n in notices) {
        results.add({...n, 'churchId': c.id, 'churchName': c.name});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getParishPrayers(String parishId) async {
    final churches = await getChurches(parishId);
    final results = <Map<String, dynamic>>[];
    for (final c in churches) {
      final prayers = await getPrayers(parishId, c.id);
      for (final p in prayers) {
        results.add({...p, 'churchId': c.id, 'churchName': c.name});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getParishCourses(String parishId) async {
    final churches = await getChurches(parishId);
    final results = <Map<String, dynamic>>[];
    for (final c in churches) {
      final courses = await getCourses(parishId, c.id, onlyPublished: true);
      for (final course in courses) {
        results.add({...course, 'parishId': parishId, 'churchId': c.id, 'churchName': c.name});
      }
    }
    return results;
  }

  /// Formatted directly in the shape PhotoTile/GalleryViewer already expect,
  /// so the parish gallery can reuse those exact widgets with zero changes.
  Future<List<Map<String, String>>> getParishApprovedMedia(String parishId) async {
    final churches = await getChurches(parishId);
    final results = <Map<String, String>>[];
    for (final c in churches) {
      final media = await getMedia(parishId, c.id, onlyApproved: true);
      for (final m in media) {
        final uploadedAt = m['uploadedAt'] as Timestamp?;
        results.add({
          'url': m['url'] ?? '',
          'caption': '${m['caption'] ?? ''} — ${c.name}',
          'date': uploadedAt != null ? '${uploadedAt.toDate().day}/${uploadedAt.toDate().month}/${uploadedAt.toDate().year}' : '',
          'uploadedBy': m['uploadedByName'] ?? '',
          'kind': m['kind'] ?? 'image',
          'isSample': 'false',
        });
      }
    }
    return results;
  }

  // ---------- Diocese-wide summaries (loop parishes, reuse the parish-level rollup) ----------
  Future<List<Map<String, dynamic>>> getDioceseNotices(String dioceseId) async {
    final parishes = await getParishes(dioceseId);
    final results = <Map<String, dynamic>>[];
    for (final p in parishes) {
      final notices = await getParishNotices(p['id']);
      for (final n in notices) {
        results.add({...n, 'parishId': p['id'], 'parishName': p['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getDiocesePrayers(String dioceseId) async {
    final parishes = await getParishes(dioceseId);
    final results = <Map<String, dynamic>>[];
    for (final p in parishes) {
      final prayers = await getParishPrayers(p['id']);
      for (final pr in prayers) {
        results.add({...pr, 'parishId': p['id'], 'parishName': p['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getDioceseCourses(String dioceseId) async {
    final parishes = await getParishes(dioceseId);
    final results = <Map<String, dynamic>>[];
    for (final p in parishes) {
      final courses = await getParishCourses(p['id']);
      for (final c in courses) {
        results.add({...c, 'parishId': p['id'], 'parishName': p['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, String>>> getDioceseApprovedMedia(String dioceseId) async {
    final parishes = await getParishes(dioceseId);
    final results = <Map<String, String>>[];
    for (final p in parishes) {
      results.addAll(await getParishApprovedMedia(p['id']));
    }
    return results;
  }

  // ---------- Province-wide summaries (loop dioceses, reuse the diocese-level rollup) ----------
  Future<List<Map<String, dynamic>>> getProvinceNotices(String provinceId) async {
    final dioceses = await getDioceses(provinceId);
    final results = <Map<String, dynamic>>[];
    for (final d in dioceses) {
      final notices = await getDioceseNotices(d['id']);
      for (final n in notices) {
        results.add({...n, 'dioceseId': d['id'], 'dioceseName': d['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getProvincePrayers(String provinceId) async {
    final dioceses = await getDioceses(provinceId);
    final results = <Map<String, dynamic>>[];
    for (final d in dioceses) {
      final prayers = await getDiocesePrayers(d['id']);
      for (final pr in prayers) {
        results.add({...pr, 'dioceseId': d['id'], 'dioceseName': d['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getProvinceCourses(String provinceId) async {
    final dioceses = await getDioceses(provinceId);
    final results = <Map<String, dynamic>>[];
    for (final d in dioceses) {
      final courses = await getDioceseCourses(d['id']);
      for (final c in courses) {
        results.add({...c, 'dioceseId': d['id'], 'dioceseName': d['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, String>>> getProvinceApprovedMedia(String provinceId) async {
    final dioceses = await getDioceses(provinceId);
    final results = <Map<String, String>>[];
    for (final d in dioceses) {
      results.addAll(await getDioceseApprovedMedia(d['id']));
    }
    return results;
  }

  // ---------- National summaries (loop provinces, reuse the province-level rollup) ----------
  // Honest flag, more urgent here than anywhere below it: this fans out to
  // 9 provinces x every diocese x every parish x every church, all as live
  // reads, every time this page opens. It works correctly right now purely
  // because almost none of that tree has real data yet (one real parish
  // out of ~20 seeded dioceses). This is NOT the shape to ship once the
  // directory is genuinely populated nationally - that needs real
  // denormalization or a Cloud Function maintaining rollup documents,
  // not four levels of nested live queries at read time.
  Future<List<Map<String, dynamic>>> getNationalNotices() async {
    final provinces = await getProvinces();
    final results = <Map<String, dynamic>>[];
    for (final prov in provinces) {
      final notices = await getProvinceNotices(prov['id']);
      for (final n in notices) {
        results.add({...n, 'provinceId': prov['id'], 'provinceName': prov['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getNationalPrayers() async {
    final provinces = await getProvinces();
    final results = <Map<String, dynamic>>[];
    for (final prov in provinces) {
      final prayers = await getProvincePrayers(prov['id']);
      for (final pr in prayers) {
        results.add({...pr, 'provinceId': prov['id'], 'provinceName': prov['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getNationalCourses() async {
    final provinces = await getProvinces();
    final results = <Map<String, dynamic>>[];
    for (final prov in provinces) {
      final courses = await getProvinceCourses(prov['id']);
      for (final c in courses) {
        results.add({...c, 'provinceId': prov['id'], 'provinceName': prov['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, String>>> getNationalApprovedMedia() async {
    final provinces = await getProvinces();
    final results = <Map<String, String>>[];
    for (final prov in provinces) {
      results.addAll(await getProvinceApprovedMedia(prov['id']));
    }
    return results;
  }

  // ---------- Hymns - real, verified data from the CMAA (Church Music
  // Association of America) English Hymns page, confirmed genuinely
  // Catholic and transcribed directly from the actual page content, not
  // scraped by an untested parser against HTML structure never directly
  // seen. Each entry links to CMAA's real PDF sheet music - lyric text
  // isn't extracted from these PDFs, since that extraction is
  // genuinely unreliable for music-typeset lyrics (verses stack
  // vertically under the same melody line and interleave on
  // extraction), confirmed directly against a real sample earlier this
  // session rather than assumed. ----------

  /// One-time import from the bundled, verified asset into Firestore -
  /// lets an admin re-run this if the collection needs rebuilding,
  /// without needing a live scrape of CMAA's page (which was
  /// deliberately avoided given the risk of guessing at HTML structure
  /// never directly verified).
  Future<int> importHymnsFromAsset() async {
    final raw = await rootBundle.loadString('assets/hymns/cmaa_hymns.json');
    final List<dynamic> hymns = json.decode(raw);
    int imported = 0;
    for (var i = 0; i < hymns.length; i += 400) {
      final batch = _db.batch();
      final slice = hymns.sublist(i, i + 400 > hymns.length ? hymns.length : i + 400);
      for (final h in slice) {
        final map = Map<String, dynamic>.from(h);
        final id = map['pdfUrl'].toString().split('/').last.replaceAll('.pdf', '');
        batch.set(_db.collection('hymns').doc(id), map);
        imported++;
      }
      await batch.commit();
    }
    return imported;
  }

  Future<List<Map<String, dynamic>>> getHymns() async {
    final snap = await _db.collection('hymns').orderBy('title').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Editing a hymn's own fields (title, category) in place - the file
  /// itself (PDF or lyrics text) isn't touched here; re-uploading a new
  /// file is a separate action from correcting a typo in the title.
  Future<void> updateHymn(String id, Map<String, dynamic> data) async {
    await _db.collection('hymns').doc(id).update(data);
  }

  /// Same "keep the data, just stop showing it" pattern as reading
  /// fields - a hidden hymn stays in Firestore, just filtered out of
  /// the regular Hymns screen.
  Future<void> setHymnHidden(String id, bool hidden) async {
    await _db.collection('hymns').doc(id).update({'hidden': hidden});
  }

  /// Triggers the real PDF -> Audiveris -> MusicXML -> MIDI -> FluidSynth
  /// -> WAV pipeline for one hymn, via the separate hymn-omr-service
  /// Cloud Run container (Node.js Cloud Functions can't run Audiveris,
  /// a Java application, natively). Can genuinely take a few minutes -
  /// OMR itself is slow, especially for a real, multi-voice hymn
  /// arrangement rather than a simple test file.
  /// Re-hosts every hymn's external CMAA link into this project's own
  /// Firebase Storage - runs server-side via Cloud Function, which has
  /// real network access to the CMAA host (unlike the sandbox this was
  /// first attempted from). Safe to re-run; already-rehosted hymns are
  /// skipped automatically.
  Future<Map<String, dynamic>> rehostHymnPdfs() async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'rehostHymnPdfs',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 540)),
    );
    final result = await callable.call();
    return Map<String, dynamic>.from(result.data);
  }

  /// Manually adding a hymn with an uploaded PDF file, not a pasted
  /// link - the file goes straight into this project's own Storage, the
  /// same way CMAA hymns end up there after rehostHymnPdfs runs.
  Future<void> addHymnWithPdf({
    required String title,
    required Uint8List pdfBytes,
    String? category,
  }) async {
    final id = title.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final storagePath = 'hymns/$id.pdf';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(pdfBytes, SettableMetadata(contentType: 'application/pdf'));
    final url = await ref.getDownloadURL();
    await _db.collection('hymns').doc(id).set({
      'title': title.trim(),
      'pdfUrl': url,
      'fileType': 'pdf',
      'category': category ?? 'manual',
      'categoryLabel': 'Manually Added',
      'source': 'Manually added',
    });
  }

  /// A hymn with no PDF at all - just typed or pasted lyrics, for hymns
  /// that don't have sheet music available, or where only the words
  /// matter for now.
  Future<void> addHymnWithText({
    required String title,
    required String lyricsText,
    String? category,
  }) async {
    final id = title.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    await _db.collection('hymns').doc(id).set({
      'title': title.trim(),
      'lyricsText': lyricsText.trim(),
      'fileType': 'text',
      'category': category ?? 'manual',
      'categoryLabel': 'Manually Added',
      'source': 'Manually added',
    });
  }

}