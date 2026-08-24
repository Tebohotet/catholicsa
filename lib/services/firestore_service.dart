import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../models/church.dart';
import '../models/parish.dart';
import 'firestore_service.dart';


/// This file was split into 4 pieces to reduce its size - it had grown
/// large enough to be the direct, repeated cause of real edit mistakes
/// this session (a str_replace clobbering a neighboring method's
/// declaration, caught only by checking method counts after every edit).
/// The other 3 pieces are extension methods on FirestoreService, not
/// separate classes - exporting them here is what makes every existing
/// `import '../services/firestore_service.dart'` across the whole app
/// keep working completely unchanged, with zero call-site edits needed
/// anywhere.
export 'content_courses_service.dart';
export 'marketplace_admin_service.dart';
export 'community_search_service.dart';

/// "Where to look" for search - national is the original full scan,
/// everything else resolves to a real scoped query rather than filtering
/// a full fetch client-side. See the search methods below for the honest
/// scaling ceiling of the diocese/province cases.
enum SearchScope { national, province, diocese, parish }

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // ---------- Browse hierarchy: Province > Diocese > Parish > Church ----------

  Future<List<Map<String, dynamic>>> getProvinces() async {
    final snap = await _db.collection('provinces').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ---------- Country - the top of the whole hierarchy, added above
  // provinces without restructuring the existing province-first browse
  // flow. countryId on a province is optional so this is purely
  // additive. ----------

  Future<List<Map<String, dynamic>>> getCountries() async {
    final snap = await _db.collection('countries').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<String> addCountry(String name) async {
    final ref = await _db.collection('countries').add({'name': name});
    return ref.id;
  }

  Future<void> updateCountry(String countryId, String name) async {
    await _db.collection('countries').doc(countryId).update({'name': name});
  }

  /// Same cascade caveat as every level below it, at the very top of the
  /// tree now - every province (and everything under every province)
  /// that pointed to this country keeps its countryId pointing at
  /// nothing, not automatically cleaned up.
  Future<void> deleteCountry(String countryId) async {
    await _db.collection('countries').doc(countryId).delete();
  }

  Future<String> addProvince(String name, {String? countryId}) async {
    final ref = await _db.collection('provinces').add({'name': name, 'countryId': countryId});
    return ref.id;
  }

  Future<void> updateProvince(String provinceId, String name, {String? countryId}) async {
    await _db.collection('provinces').doc(provinceId).update({'name': name, 'countryId': countryId});
  }

  /// The root of the whole hierarchy - every diocese, parish, church, and
  /// everything nested under all of them sits below a province. Deleting
  /// one orphans more than deleting a parish or a church does, not less -
  /// same honest cascade caveat as those, just at the top of the tree
  /// instead of partway down it.
  Future<void> deleteProvince(String provinceId) async {
    await _db.collection('provinces').doc(provinceId).delete();
  }

  Future<List<Map<String, dynamic>>> getDioceses(String provinceId) async {
    final snap = await _db.collection('dioceses').where('provinceId', isEqualTo: provinceId).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Public-facing only - an empty parish (no churches yet) is a
  /// work-in-progress entry, not something a visitor should be able to
  /// browse into and find nothing. Admin-facing listings (like
  /// getAllParishesFlat, used for role assignment) deliberately don't
  /// use this - an admin needs to see an empty parish specifically in
  /// order to add its first church.
  Future<List<Map<String, dynamic>>> getParishes(String dioceseId) async {
    final snap = await _db.collection('parishes').where('dioceseId', isEqualTo: dioceseId).get();
    final parishes = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    final withChurchCheck = await Future.wait(parishes.map((p) async {
      final churchesSnap = await _db.collection('parishes').doc(p['id']).collection('churches').limit(1).get();
      return {'parish': p, 'hasChurch': churchesSnap.docs.isNotEmpty};
    }));
    return withChurchCheck.where((e) => e['hasChurch'] == true).map((e) => e['parish'] as Map<String, dynamic>).toList();
  }

  Future<List<Church>> getChurches(String parishId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').get();
    return snap.docs.map((d) => Church.fromFirestore(d.id, d.data())).toList();
  }

  // ---------- Church verification ----------
  // A church starts unverified. Verification is a deliberate step a
  // priest confirms, not an automatic status - but most of the
  // underlying conditions ARE checked automatically here, so a priest
  // is confirming real, checked facts, not just trusting a form.

  Future<Map<String, dynamic>?> getAdminTrainingConfig() async {
    final doc = await _db.collection('platformConfig').doc('adminTraining').get();
    return doc.data();
  }

  Future<void> setAdminTrainingCourse({required String parishId, required String churchId, required String courseId}) async {
    await _db.collection('platformConfig').doc('adminTraining').set({
      'parishId': parishId, 'churchId': churchId, 'courseId': courseId,
    });
  }

  /// Checks enrollment completion against the designated training course
  /// specifically - reuses the exact same enrollment/completedLessonIds
  /// mechanism every other course already uses, not a parallel
  /// certification system built just for this.
  Future<bool> hasCompletedAdminTraining(String uid) async {
    final config = await getAdminTrainingConfig();
    if (config == null) return false;
    final courseId = config['courseId'] as String?;
    if (courseId == null) return false;
    final parishId = config['parishId'] as String;
    final churchId = config['churchId'] as String;

    final lessons = await getLessons(parishId, churchId, courseId);
    if (lessons.isEmpty) return false;

    final enrollmentDoc = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('enrollments').doc(uid).get();
    if (!enrollmentDoc.exists) return false;

    final completed = List<String>.from(enrollmentDoc.data()?['completedLessonIds'] ?? []);
    return lessons.every((l) => completed.contains(l['id']));
  }

  /// Every condition from the verification schema, checked for real
  /// rather than trusted. hasAtLeastOneAdmin and adminCompletedTraining
  /// are checked together - specifically, at least one of the church's
  /// admins has to have completed training, not just that an admin
  /// exists at all.
  Future<Map<String, bool>> checkVerificationEligibility(String parishId, String churchId) async {
    final church = await getChurch(parishId, churchId);
    final servicesSnap = await _db
        .collection('parishes').doc(parishId).collection('churches').doc(churchId)
        .collection('services').limit(1).get();
    final admins = await getParishAdmins(parishId);

    bool anyAdminTrained = false;
    for (final admin in admins) {
      if (await hasCompletedAdminTraining(admin['uid'])) { anyAdminTrained = true; break; }
    }

    final gpsSet = !(church.geopoint.latitude == 0 && church.geopoint.longitude == 0);
    final churchDoc = await _db.collection('parishes').doc(parishId).collection('churches').doc(churchId).get();
    final gpsDeferred = churchDoc.data()?['gpsExplicitlyDeferred'] == true;

    return {
      'hasConfirmedMassTime': servicesSnap.docs.isNotEmpty,
      'hasAtLeastOneAdmin': admins.isNotEmpty,
      'adminCompletedTraining': anyAdminTrained,
      'gpsLocationSet': gpsSet || gpsDeferred,
      'associationsReviewed': churchDoc.data()?['associationsReviewed'] == true,
    };
  }

  Future<void> setGpsExplicitlyDeferred(String parishId, String churchId, bool deferred) async {
    await _db.collection('parishes').doc(parishId).collection('churches').doc(churchId)
        .update({'gpsExplicitlyDeferred': deferred});
  }

  Future<void> setAssociationsReviewed(String parishId, String churchId, bool reviewed) async {
    await _db.collection('parishes').doc(parishId).collection('churches').doc(churchId)
        .update({'associationsReviewed': reviewed});
  }

  /// The actual verification action - deliberately not checked again
  /// here client-side; the rule itself requires isPriestForParish, and
  /// the UI only shows this button once checkVerificationEligibility
  /// says every condition passed, so a priest is confirming something
  /// real, not overriding a check.
  Future<void> verifyChurch(String parishId, String churchId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _db.collection('parishes').doc(parishId).collection('churches').doc(churchId).update({
      'verificationStatus': 'verified',
      'verifiedAt': FieldValue.serverTimestamp(),
      'verifiedBy': uid,
    });
  }

  Future<Church> getChurch(String parishId, String churchId) async {
    final doc = await _db.collection('parishes').doc(parishId).collection('churches').doc(churchId).get();
    return Church.fromFirestore(doc.id, doc.data()!);
  }

  /// GPS is genuinely optional at creation - (0,0) is used as an
  /// explicit "not set yet" sentinel rather than making the field
  /// nullable throughout the whole model, which would have meant
  /// touching ~14 call sites across the map, directions links, and
  /// detail screen. A church starts unverified regardless of what's
  /// filled in here - verification is a separate, deliberate step.
  Future<String> addChurch({
    required String parishId,
    required String name,
    required String address,
    GeoPoint? geopoint,
    String contactPhone = '',
    String contactEmail = '',
    List<String> supportedLanguages = const ['en'],
    String buildingType = 'Church',
    int? seatingCapacity,
    String venueType = 'church',
  }) async {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final ref = await _db.collection('parishes').doc(parishId).collection('churches').add({
      'parishId': parishId,
      'name': name,
      'slug': slug,
      'address': address,
      'geopoint': geopoint ?? const GeoPoint(0, 0),
      'contactPhone': contactPhone,
      'contactEmail': contactEmail,
      'socialLinks': <String, String>{},
      'supportedLanguages': supportedLanguages,
      'seatingCapacity': seatingCapacity,
      'venueType': venueType,
      'buildingType': buildingType,
      'verificationStatus': 'unverified',
      'accessibility': {
        'wheelchairAccessible': 'unknown',
        'steps': 'unknown',
        'hasRamp': false,
        'accessibleParking': false,
        'hasAccessibleToilet': false,
        'notes': null,
        'assistanceContactPhone': null,
      },
      'amenities': {
        'hasCryRoom': false,
        'offersWeddingBooking': false,
        'offersFuneralServices': true,
        'offersBaptism': true,
        'offersConfirmationPrep': false,
        'hasParkingOnsite': false,
        'hasSoundLoop': false,
      },
    });
    return ref.id;
  }

  Future<void> updateChurch({
    required String parishId,
    required String churchId,
    required String name,
    required String address,
    GeoPoint? geopoint,
    String contactPhone = '',
    String contactEmail = '',
    List<String> supportedLanguages = const ['en'],
    String buildingType = 'Church',
    int? seatingCapacity,
  }) async {
    await _db.collection('parishes').doc(parishId).collection('churches').doc(churchId).update({
      'name': name,
      'address': address,
      if (geopoint != null) 'geopoint': geopoint,
      'contactPhone': contactPhone,
      'contactEmail': contactEmail,
      'supportedLanguages': supportedLanguages,
      'buildingType': buildingType,
      if (seatingCapacity != null) 'seatingCapacity': seatingCapacity,
    });
  }

  Future<void> updateChurchAccessibility(String parishId, String churchId, Map<String, dynamic> accessibility) async {
    await _db.collection('parishes').doc(parishId).collection('churches').doc(churchId)
        .update({'accessibility': accessibility});
  }

  Future<void> updateChurchAmenities(String parishId, String churchId, Map<String, dynamic> amenities) async {
    await _db.collection('parishes').doc(parishId).collection('churches').doc(churchId)
        .update({'amenities': amenities});
  }

  /// Deletes the church document itself only - Firestore doesn't cascade
  /// delete subcollections (services, notices, associations, and every
  /// other piece a church accumulates), so those would remain as orphaned
  /// data. A real, honest limitation worth knowing before deleting a
  /// church that's had real activity, not something silently handled.
  Future<void> deleteChurch(String parishId, String churchId) async {
    await _db.collection('parishes').doc(parishId).collection('churches').doc(churchId).delete();
  }

  // ---------- Event RSVP + capacity (accessibility seat booking) ----------
  // Deliberately count-based, not a visual seat chart - "reserved" is a
  // tag on a person's own RSVP, not a specific physical seat number. A
  // real seating chart is a much bigger feature; this answers the actual
  // question asked - how many are coming, how many need a guaranteed
  // accessible seat, and is the church full - without over-building.

  Future<void> rsvpToEvent({
    required String parishId, required String churchId, required String eventId,
    required String name, String? contactPhone,
    String? accessibilityNeed, // null | 'hearing' | 'vision' | 'mobility'
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to RSVP');
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('events').doc(eventId)
        .collection('attendees').doc(uid)
        .set({
      'name': name,
      'contactPhone': contactPhone,
      'accessibilityNeed': accessibilityNeed,
      'seatTag': accessibilityNeed != null ? 'reserved' : null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelEventRsvp(String parishId, String churchId, String eventId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('events').doc(eventId)
        .collection('attendees').doc(uid).delete();
  }

  Future<bool> isRsvpedToEvent(String parishId, String churchId, String eventId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('events').doc(eventId)
        .collection('attendees').doc(uid).get();
    return doc.exists;
  }

  /// Attendee count plus how many of those are reserved (accessibility)
  /// seats specifically - an admin planning for the day needs both
  /// numbers, not just a total.
  Future<Map<String, int>> getEventAttendanceSummary(String parishId, String churchId, String eventId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('events').doc(eventId)
        .collection('attendees').get();
    final reserved = snap.docs.where((d) => d.data()['seatTag'] == 'reserved').length;
    return {'total': snap.docs.length, 'reserved': reserved};
  }

  /// Admin-only detail view - who's coming and what they each need,
  /// not just the count.
  Future<List<Map<String, dynamic>>> getEventAttendees(String parishId, String churchId, String eventId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('events').doc(eventId)
        .collection('attendees').get();
    return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
  }

  // ---------- Schedule: services for a church, upcoming only ----------

  /// Returns this church's services in the given window. By default hides
  /// anything already in the past (for "what can I still attend" views like
  /// the map cards) - pass hidePast: false to show the full published week
  /// regardless of today's date (for the Horarium, which is meant to read
  /// like the printed bulletin, not just what's left to attend).
  Future<List<ServiceEntry>> getUpcomingServices(String parishId, String churchId, {int daysAhead = 7, bool hidePast = true}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Full-week view starts from this week's Sunday, not from today, so
    // earlier days already passed this week still show in the Horarium.
    final startDate = hidePast ? today : today.subtract(Duration(days: now.weekday % 7));
    final endDate = startDate.add(Duration(days: daysAhead));
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('services')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .orderBy('date')
        .get();

    final all = snap.docs.map((d) => ServiceEntry.fromFirestore(d.id, churchId, d.data())).toList();
    final filtered = hidePast ? all.where((s) => !s.isPast).toList() : all;
    return filtered..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  Future<List<ConfessionTime>> getConfessionTimes(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('confessionTimes').get();
    return snap.docs.map((d) => ConfessionTime.fromFirestore(d.id, d.data())).toList();
  }

  Future<Parish> getParish(String parishId) async {
    final doc = await _db.collection('parishes').doc(parishId).get();
    return Parish.fromFirestore(doc.id, doc.data()!);
  }

  /// Every parish, id and name only - what the Super Admin Panel's role
  /// assignment dropdown actually needs to stay current as new parishes
  /// get created, rather than a hardcoded list that silently goes stale.
  Future<List<Map<String, String>>> getAllParishesFlat() async {
    final snap = await _db.collection('parishes').get();
    return snap.docs.map((d) => {'id': d.id, 'name': (d.data()['name'] as String?) ?? d.id}).toList();
  }

  /// Super Admin only, matching the rule - creating a brand new parish is
  /// a platform-level structural decision, unlike adding a second church
  /// within an existing parish, which any parish admin can already do.
  Future<String> addParish({
    required String dioceseId,
    required String name,
    String contactPhone = '',
    String contactEmail = '',
  }) async {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final ref = await _db.collection('parishes').add({
      'dioceseId': dioceseId,
      'name': name,
      'slug': slug,
      'featureFlags': {'finances': false, 'shop': false, 'comments': true, 'associations': true},
      'contactPhone': contactPhone,
      'contactEmail': contactEmail,
      'socialLinks': <String, String>{},
    });
    return ref.id;
  }

  /// General fields only - deliberately doesn't touch featureFlags or
  /// bankDetails, which already have their own narrower, priest-gated
  /// methods (updateFinanceFlag, savePaymentGatewayConfig). Keeping this
  /// method to the fields the rule actually opens to any parish admin
  /// avoids it silently failing if a secretary tries to use it.
  Future<void> updateParish({
    required String parishId,
    required String name,
    String contactPhone = '',
    String contactEmail = '',
  }) async {
    await _db.collection('parishes').doc(parishId).update({
      'name': name,
      'contactPhone': contactPhone,
      'contactEmail': contactEmail,
    });
  }

  /// Deletes the parish document itself only - same honest limitation as
  /// deleteChurch, at a larger scale: every church, course, product, and
  /// comment nested under this parish becomes orphaned data, not
  /// automatically cleaned up. The rule restricts this to Super Admin
  /// specifically because of that scale, not as a formality.
  Future<void> deleteParish(String parishId) async {
    await _db.collection('parishes').doc(parishId).delete();
  }

  Future<Map<String, dynamic>?> getDioceseLeadership(String dioceseId) async {
    final doc = await _db.collection('dioceses').doc(dioceseId).collection('leadership').doc('main').get();
    return doc.exists ? doc.data() : null;
  }

  Future<Map<String, dynamic>> getDioceseById(String dioceseId) async {
    final doc = await _db.collection('dioceses').doc(dioceseId).get();
    return {'id': doc.id, ...doc.data()!};
  }

  /// dioceseType drives the default bishopTitle when leadership is first
  /// set up ('archdiocese' -> 'Archbishop', 'diocese' -> 'Bishop'), but
  /// bishopTitle itself stays independently editable - a newly-elevated
  /// archdiocese can have an Apostolic Administrator temporarily, and
  /// that shouldn't be blocked by an assumption baked into the type.
  Future<String> addDiocese({
    required String provinceId,
    required String name,
    String dioceseType = 'diocese', // 'diocese' | 'archdiocese'
    String? metropolitanSeeId, // for a suffragan diocese, points to its archdiocese
  }) async {
    final ref = await _db.collection('dioceses').add({
      'provinceId': provinceId,
      'name': name,
      'dioceseType': dioceseType,
      'metropolitanSeeId': metropolitanSeeId,
    });
    return ref.id;
  }

  Future<void> updateDiocese({
    required String dioceseId,
    required String name,
    String dioceseType = 'diocese',
    String? metropolitanSeeId,
  }) async {
    await _db.collection('dioceses').doc(dioceseId).update({
      'name': name,
      'dioceseType': dioceseType,
      'metropolitanSeeId': metropolitanSeeId,
    });
  }

  /// Every diocese below it (in the same province) loses its
  /// metropolitanSeeId reference if this was itself an archdiocese with
  /// suffragans pointing to it - not automatically cleaned up, same
  /// honest orphaned-reference caveat as deleting a parish or church.
  Future<void> deleteDiocese(String dioceseId) async {
    await _db.collection('dioceses').doc(dioceseId).delete();
  }

  /// The write side of DioceseLeadership - the model and the rule
  /// permitting this have existed the whole time; nothing could ever
  /// actually call it until now.
  Future<void> updateDioceseLeadership(String dioceseId, Map<String, dynamic> data) async {
    await _db.collection('dioceses').doc(dioceseId).collection('leadership').doc('main').set(data, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> getProvinceById(String provinceId) async {
    final doc = await _db.collection('provinces').doc(provinceId).get();
    return {'id': doc.id, ...doc.data()!};
  }

  Future<List<Map<String, dynamic>>> getPriests(String parishId) async {
    final snap = await _db.collection('parishes').doc(parishId).collection('priests').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<Map<String, dynamic>> getPriest(String parishId, String priestId) async {
    final doc = await _db.collection('parishes').doc(parishId).collection('priests').doc(priestId).get();
    return {'id': doc.id, ...doc.data()!};
  }

  Future<void> addService({
    required String parishId,
    required String churchId,
    required DateTime date,
    required String time,
    required String type,
    required String language,
  }) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final docId = '${dateStr}_$time';
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('services').doc(docId)
        .set({
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'time': time,
      'type': type,
      'language': language,
    });
  }

  Future<void> deleteService(String parishId, String churchId, String serviceId) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('services').doc(serviceId)
        .delete();
  }

  /// Dotted field path updates only that one nested key, leaving the other
  /// featureFlags (shop, comments, associations) untouched.
  Future<void> updateFinanceFlag(String parishId, bool enabled) async {
    await _db.collection('parishes').doc(parishId).update({'featureFlags.finances': enabled});
  }

  /// Same walk-every-church pattern as getAllCommentsForParish, filtered
  /// to comment reports specifically - generic issue reports already have
  /// their own section (Reported Issues), this is just the comment-shaped
  /// subset of the same underlying reports collection.
  Future<List<Map<String, dynamic>>> getCommentReportsForParish(String parishId) async {
    final churchesSnap = await _db.collection('parishes').doc(parishId).collection('churches').get();
    final results = <Map<String, dynamic>>[];
    for (final churchDoc in churchesSnap.docs) {
      final reportsSnap = await churchDoc.reference.collection('reports')
          .where('reportType', isEqualTo: 'comment').orderBy('createdAt', descending: true).get();
      for (final r in reportsSnap.docs) {
        results.add({'id': r.id, 'churchId': churchDoc.id, 'churchName': churchDoc.data()['name'], ...r.data()});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getAllCommentsForParish(String parishId) async {
    final churchesSnap = await _db.collection('parishes').doc(parishId).collection('churches').get();
    final results = <Map<String, dynamic>>[];
    for (final churchDoc in churchesSnap.docs) {
      final commentsSnap = await churchDoc.reference.collection('comments').orderBy('createdAt', descending: true).get();
      for (final c in commentsSnap.docs) {
        results.add({'id': c.id, 'churchId': churchDoc.id, 'churchName': churchDoc.data()['name'], ...c.data()});
      }
    }
    return results;
  }

  Future<void> replyToComment({
    required String parishId,
    required String churchId,
    required String commentId,
    required String from,
    required String text,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('comments').doc(commentId)
        .update({
      'reply': {'from': from, 'text': text, 'repliedAt': FieldValue.serverTimestamp()},
    });
  }
  Future<List<Map<String, dynamic>>> getMedia(String parishId, String churchId, {bool onlyApproved = true}) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('media')
        .orderBy('uploadedAt', descending: true)
        .get();
    final all = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    if (!onlyApproved) return all;
    return all.where((m) => m['status'] == 'approved').toList();
  }

  /// Uses XFile.readAsBytes() + putData() rather than putFile(), since
  /// putFile doesn't work on Flutter web - this keeps the same upload code
  /// working across every platform without a separate web path.
  Future<void> uploadMedia({
    required String parishId,
    required String churchId,
    required XFile file,
    required String caption,
    required bool isVideo,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final uploaderName = FirebaseAuth.instance.currentUser?.displayName ?? 'Parish Admin';
    final bytes = await file.readAsBytes();
    final ext = file.name.contains('.') ? file.name.split('.').last : (isVideo ? 'mp4' : 'jpg');
    final storagePath = 'churches/$parishId/$churchId/media/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(bytes, SettableMetadata(contentType: isVideo ? 'video/mp4' : 'image/jpeg'));
    final url = await ref.getDownloadURL();

    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('media')
        .add({
      'kind': isVideo ? 'video' : 'image',
      'url': url,
      'caption': caption,
      'uploadedBy': uid,
      'uploadedByName': uploaderName,
      'uploadedAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  /// Only the parish priest (or superAdmin) can change status - enforced
  /// server-side in firestore.rules, this is just the client call.
  Future<void> updateMediaStatus({
    required String parishId,
    required String churchId,
    required String mediaId,
    required String status,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('media').doc(mediaId)
        .update({'status': status});
  }

  Future<List<Map<String, dynamic>>> getPrayers(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('prayers').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> addPrayer({
    required String parishId,
    required String churchId,
    required String title,
    required String text,
    String language = 'EN',
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('prayers')
        .doc(title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'))
        .set({'title': title, 'text': text, 'language': language});
  }

  Future<void> deletePrayer(String parishId, String churchId, String prayerId) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('prayers').doc(prayerId)
        .delete();
  }

  Future<Map<String, dynamic>?> getSongByNumber(String parishId, String churchId, int number) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('songs')
        .where('number', isEqualTo: number)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return {'id': snap.docs.first.id, ...snap.docs.first.data()};
  }

  Future<List<Map<String, dynamic>>> getSongs(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('songs')
        .orderBy('number')
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> addSong({
    required String parishId,
    required String churchId,
    required int number,
    required String title,
    String? hymnal,
    String language = 'EN',
    String? lyrics,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('songs')
        .doc('song-$number')
        .set({
      'number': number,
      'title': title,
      'hymnal': hymnal,
      'language': language,
      'lyrics': lyrics,
    });
  }

  Future<void> deleteSong(String parishId, String churchId, String songId) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('songs').doc(songId)
        .delete();
  }

  Future<String?> getReadingNote(String date) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).collection('readingNotes').doc(date).get();
    return doc.data()?['text'] as String?;
  }

  Future<void> saveReadingNote(String date, String text) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to add a note');
    await _db.collection('users').doc(uid).collection('readingNotes').doc(date).set({
      'text': text,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Free, no-key Church Calendar API - tells us which saint/feast is
  /// celebrated on a date. Picks the highest-ranked celebration with an
  /// actual title (an ordinary weekday often has an empty-title "ferial"
  /// entry alongside an optional memorial - we want the memorial).
  Future<String?> getSaintOfDay(DateTime date) async {
    final url = Uri.parse(
        'http://calapi.inadiutorium.cz/api/v0/en/calendars/general-en/${date.year}/${date.month}/${date.day}');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final celebrations = (data['celebrations'] as List<dynamic>? ?? [])
          .where((c) => (c['title'] as String? ?? '').isNotEmpty)
          .toList();
      if (celebrations.isEmpty) return null;
      celebrations.sort((a, b) => (a['rank_num'] as num).compareTo(b['rank_num'] as num));
      return celebrations.first['title'] as String;
    } catch (_) {
      return null; // API hiccup - the day's readings still work fine without this
    }
  }

  /// Only a handful of saints have real curated profiles - matches the
  /// day's celebration title against each curated saint's key phrase.
  /// Looks up a saint by fixed calendar date (MM-DD), entirely from our own
  /// data - no network call. Replaces the earlier live-API approach, which
  /// also solves the mixed-content risk that API carried once deployed to
  /// HTTPS, since there's simply no HTTP call being made anymore.
  Future<Map<String, dynamic>?> getSaintByMonthDay(String monthDay) async {
    final snap = await _db.collection('saints').where('feastMonthDay', isEqualTo: monthDay).limit(1).get().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception('Timed out looking up the saint for $monthDay - check your connection or Firebase config.'),
    );
    if (snap.docs.isEmpty) return null;
    return {'id': snap.docs.first.id, ...snap.docs.first.data()};
  }

  Future<Map<String, dynamic>?> getCuratedSaintInfo(String celebrationTitle) async {
    final snap = await _db.collection('saints').get();
    for (final doc in snap.docs) {
      final matchPhrase = doc.data()['matchPhrase'] as String? ?? '';
      if (matchPhrase.isNotEmpty && celebrationTitle.toLowerCase().contains(matchPhrase.toLowerCase())) {
        return {'id': doc.id, ...doc.data()};
      }
    }
    return null;
  }
}
