import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/church.dart';
import '../models/user_preferences.dart';
import 'firestore_service.dart';

/// See content_courses_service.dart for why this file exists - same
/// reasoning, different domain slice. This one already ends with the
/// original file's own closing brace, reused directly as this
/// extension's closing brace.
extension CommunitySearchService on FirestoreService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  // ---------- Donations (same manual bank-deposit flow as orders, no product tie-in) ----------

  Future<String> createDonation({
    required String parishId,
    required String churchId,
    required String associationName,
    required double amount,
    required String donorName,
    required String donorContact,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to donate');
    final ref = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('donations').add({
      'parishId': parishId, 'churchId': churchId,
      'associationName': associationName,
      'donorId': uid, 'donorName': donorName, 'donorContact': donorContact,
      'amount': amount,
      'proofOfPaymentUrl': null,
      'status': 'awaiting_payment',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> uploadDonationProof({
    required String parishId,
    required String churchId,
    required String donationId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
    final isPdf = ext == 'pdf';
    final storagePath = 'churches/$parishId/$churchId/donationProof/$donationId.$ext';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(bytes, SettableMetadata(contentType: isPdf ? 'application/pdf' : 'image/jpeg'));
    final url = await ref.getDownloadURL();

    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('donations').doc(donationId)
        .update({
      'proofOfPaymentUrl': url,
      'proofOfPaymentType': isPdf ? 'pdf' : 'image',
      'status': 'proof_submitted',
    });
  }

  Future<List<Map<String, dynamic>>> getDonationsForChurch(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('donations')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// status: 'approved' (received, thank you) | 'wrong_bank' (tell the
  /// donor to reverse it) | 'rejected'. adminNote is shown to the donor
  /// for wrong_bank/rejected, so it's worth actually writing something
  /// useful rather than leaving it blank.
  Future<void> updateDonationStatus({
    required String parishId,
    required String churchId,
    required String donationId,
    required String status,
    String? adminNote,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('donations').doc(donationId)
        .update({'status': status, 'adminNote': adminNote});
  }

  // ---------- Personal notes (used by the notesList server-driven block) ----------

  Future<List<Map<String, dynamic>>> getMyNotes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final snap = await _db.collection('users').doc(uid).collection('notes')
        .orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> addNote(String text) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to take notes');
    await _db.collection('users').doc(uid).collection('notes').add({
      'text': text, 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNote(String noteId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).collection('notes').doc(noteId).delete();
  }

  // ---------- Server-driven UI: custom pages ----------
  // A page is title + an ordered list of {type, config} blocks. The app
  // never needs new code to add a page built from block types that
  // already exist - it's registering data, not shipping an update. A
  // genuinely new kind of block (never built before) still needs one
  // Dart implementation, once, added to BlockRegistry - after that it's
  // reusable by any future page for free, same as GenericAdminCrudSection
  // already is for admin CRUD screens.

  Future<List<Map<String, dynamic>>> getCustomPages() async {
    final snap = await _db.collection('customPages').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<Map<String, dynamic>?> getCustomPage(String pageId) async {
    final doc = await _db.collection('customPages').doc(pageId).get();
    return doc.exists ? {'id': doc.id, ...doc.data()!} : null;
  }

  Future<String> createCustomPage({required String title, required String icon}) async {
    final ref = await _db.collection('customPages').add({
      'title': title, 'icon': icon, 'blocks': [], 'visible': true,
    });
    return ref.id;
  }

  Future<void> updateCustomPageBlocks(String pageId, List<Map<String, dynamic>> blocks) async {
    await _db.collection('customPages').doc(pageId).update({'blocks': blocks});
  }

  Future<void> setCustomPageVisible(String pageId, bool visible) async {
    await _db.collection('customPages').doc(pageId).update({'visible': visible});
  }

  Future<void> deleteCustomPage(String pageId) async {
    await _db.collection('customPages').doc(pageId).delete();
  }

  // ---------- Design tokens (bounded designer customization, not a free canvas) ----------
  // Deliberately a small fixed set of choices, not arbitrary CSS-like
  // freedom - see the design conversation this came out of for why that
  // boundary is intentional. Applied to the MaterialApp theme and the
  // bottom nav position; does NOT retroactively re-theme every existing
  // hardcoded AppColors reference across the app - that's a separate,
  // much larger mechanical migration, not something to fake completing here.

  // ---------- Catechist applications (the concrete "apply, admin approves, ----------
  // escalates to Super Admin if higher" example) ----------
  // level 'parish': applying to teach at one specific parish - that
  // parish's priest approves. level 'national': applying to be a
  // platform-recognised catechist usable across any parish - only a
  // Super Admin (or Developer, who passes the same check) can approve
  // that, since it's a bigger claim than one priest vouching for someone
  // they actually know.

  Future<void> submitCatechistApplication({
    required String level, // 'parish' | 'national'
    String? parishId,
    required String applicantName,
    required String applicantContact,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to apply');
    await _db.collection('catechistApplications').add({
      'applicantId': uid, 'applicantName': applicantName, 'applicantContact': applicantContact,
      'type': 'catechist', 'level': level, 'parishId': parishId,
      'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getCatechistApplicationsForParish(String parishId) async {
    final snap = await _db.collection('catechistApplications')
        .where('level', isEqualTo: 'parish').where('parishId', isEqualTo: parishId).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getNationalCatechistApplications() async {
    final snap = await _db.collection('catechistApplications').where('level', isEqualTo: 'national').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Sets the application's own status - a parish priest already has
  /// legitimate write access to their own parish's applications, so this
  /// alone is enough. Deliberately does NOT also try to write onto the
  /// applicant's users/{uid} doc - a priest has no general write access
  /// there, and mirroring the flag would either fail for them or require
  /// loosening user-doc permissions for a case this narrow. Verification
  /// status is checked by querying for an approved application instead.
  Future<void> updateCatechistApplicationStatus(String appId, String status) async {
    await _db.collection('catechistApplications').doc(appId).update({'status': status});
  }

  Future<bool> isCatechistVerified(String uid) async {
    final snap = await _db.collection('catechistApplications')
        .where('applicantId', isEqualTo: uid).where('type', isEqualTo: 'catechist').where('status', isEqualTo: 'approved')
        .limit(1).get();
    return snap.docs.isNotEmpty;
  }



  // ---------- Course reviews ("good reviews" sorting, only enrolled students can review) ----------

  Future<void> submitCourseReview({
    required String parishId,
    required String churchId,
    required String courseId,
    required int rating, // 1-5
    required String comment,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to leave a review');
    final enrollment = await getEnrollment(parishId, churchId, courseId);
    if (enrollment == null) throw Exception('Only enrolled students can review a course');
    final user = await getUserDoc(uid);
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('reviews').doc(uid) // one review per student, doc id = uid so re-submitting overwrites rather than duplicates
        .set({
      'reviewerId': uid, 'reviewerName': user?['displayName'] ?? 'A student',
      'rating': rating.clamp(1, 5), 'comment': comment, 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getCourseReviews(String parishId, String churchId, String courseId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('courses').doc(courseId)
        .collection('reviews').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// No stored/denormalized average - computed from the actual reviews
  /// each time. Fine at this scale; would need a maintained counter/sum
  /// if a course ever realistically had thousands of reviews.
  Future<double?> getCourseAverageRating(String parishId, String churchId, String courseId) async {
    final reviews = await getCourseReviews(parishId, churchId, courseId);
    if (reviews.isEmpty) return null;
    final sum = reviews.fold<num>(0, (acc, r) => acc + ((r['rating'] as num?) ?? 0));
    return sum / reviews.length;
  }

  // ---------- Search (churches, courses, marketplace) ----------
  // Firestore doesn't support real substring search natively - only
  // prefix matching via range queries, which would miss "Jude" typed
  // against "St Jude" since it doesn't start with "Jude". Client-side
  // substring filtering after a scoped fetch gives a genuinely better
  // search experience at this app's actual data scale; would need a real
  // search index (e.g. Algolia) if the number of churches/courses/
  // products ever grew far beyond what a single collectionGroup fetch
  // comfortably returns.

  // ---------- Search: scope + filters, designed to scale past "fetch everything" ----------
  //
  // Parish scoping is a genuine `.where('parishId', ...)` query - real,
  // cheap, not a placeholder. Diocese/Province scoping resolves to the
  // concrete list of parish IDs underneath them (reusing the same
  // hierarchy methods the rollup pages already use) and queries with
  // `whereIn`, chunked at Firestore's 30-item cap and merged.
  //
  // Honest ceiling, stated plainly rather than glossed over: once a
  // diocese or province has more parishes than a handful of `whereIn`
  // chunks comfortably cover, this stops being "scoped" in any meaningful
  // sense and starts being "many parallel queries" - at that point the
  // correct fix is a real search index (e.g. an Algolia sync via Cloud
  // Function), not more chunking. National scope was never going to scale
  // this way and still doesn't; scoping the search is what buys real
  // headroom, not a substitute for eventually indexing properly.

  Future<List<String>?> _resolveScopeToParishIds(SearchScope scope, String? scopeId) async {
    switch (scope) {
      case SearchScope.national:
        return null; // no restriction - still a full fetch, same as before
      case SearchScope.parish:
        return scopeId != null ? [scopeId] : null;
      case SearchScope.diocese:
        if (scopeId == null) return null;
        final parishes = await getParishes(scopeId);
        return parishes.map((p) => p['id'] as String).toList();
      case SearchScope.province:
        if (scopeId == null) return null;
        final dioceses = await getDioceses(scopeId);
        final parishIds = <String>[];
        for (final d in dioceses) {
          final parishes = await getParishes(d['id']);
          parishIds.addAll(parishes.map((p) => p['id'] as String));
        }
        return parishIds;
    }
  }

  Future<List<Map<String, dynamic>>> _queryWithParishScope(Query<Map<String, dynamic>> baseQuery, List<String>? parishIds) async {
    if (parishIds == null) {
      final snap = await baseQuery.get();
      return snap.docs.map((d) => {'id': d.id, ...d.data(), '_ref': d.reference}).toList();
    }
    if (parishIds.isEmpty) return [];
    final results = <Map<String, dynamic>>[];
    for (var i = 0; i < parishIds.length; i += 30) {
      final chunk = parishIds.sublist(i, i + 30 > parishIds.length ? parishIds.length : i + 30);
      // whereIn works correctly even for a single-element chunk (the
      // common parish-scope case) - no need for a separate isEqualTo path.
      final snap = await baseQuery.where('parishId', whereIn: chunk).get();
      results.addAll(snap.docs.map((d) => {'id': d.id, ...d.data(), '_ref': d.reference}));
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> searchChurches(
    String query, {
    SearchScope scope = SearchScope.national,
    String? scopeId,
  }) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final parishIds = await _resolveScopeToParishIds(scope, scopeId);
    final docs = await _queryWithParishScope(_db.collectionGroup('churches'), parishIds);
    return docs
        .map((c) => {...c, 'parishId': c['parishId'] ?? (c['_ref'] as DocumentReference).parent.parent!.id})
        .where((c) => (c['name'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchCourses(
    String query, {
    SearchScope scope = SearchScope.national,
    String? scopeId,
    double? minRating,
  }) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final parishIds = await _resolveScopeToParishIds(scope, scopeId);
    final baseQuery = _db.collectionGroup('courses').where('status', isEqualTo: 'published');
    final docs = await _queryWithParishScope(baseQuery, parishIds);
    var results = docs.map((c) {
      final ref = c['_ref'] as DocumentReference;
      return {
        ...c,
        'churchId': ref.parent.parent!.id,
        'parishId': c['parishId'] ?? ref.parent.parent!.parent.parent!.id,
      };
    }).where((c) => (c['title'] as String? ?? '').toLowerCase().contains(q)).toList();

    if (minRating != null) {
      final withRatings = <Map<String, dynamic>>[];
      for (final c in results) {
        final rating = await getCourseAverageRating(c['parishId'], c['churchId'], c['id']);
        if (rating != null && rating >= minRating) withRatings.add({...c, 'averageRating': rating});
      }
      results = withRatings;
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> searchProducts(
    String query, {
    SearchScope scope = SearchScope.national,
    String? scopeId,
    double? minPrice,
    double? maxPrice,
    String? fulfillmentMethod,
  }) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final parishIds = await _resolveScopeToParishIds(scope, scopeId);
    final baseQuery = _db.collectionGroup('products').where('status', isEqualTo: 'approved');
    final docs = await _queryWithParishScope(baseQuery, parishIds);
    var results = docs.map((p) {
      final ref = p['_ref'] as DocumentReference;
      return {
        ...p,
        'churchId': ref.parent.parent!.id,
        'parishId': p['parishId'] ?? ref.parent.parent!.parent.parent!.id,
      };
    }).where((p) => (p['title'] as String? ?? '').toLowerCase().contains(q)).toList();

    if (minPrice != null) results = results.where((p) => ((p['price'] as num?) ?? 0) >= minPrice).toList();
    if (maxPrice != null) results = results.where((p) => ((p['price'] as num?) ?? 0) <= maxPrice).toList();
    if (fulfillmentMethod != null) results = results.where((p) => p['fulfillmentMethod'] == fulfillmentMethod).toList();
    return results;
  }


  // Always Super Admin-reviewed (no parish-level equivalent makes sense
  // here - trust as a seller isn't naturally scoped to one parish the way
  // "teaches at this parish" is), distinguished by 'type' so the review
  // screen can tell the two kinds apart.

  Future<void> submitTrustedSellerApplication({
    required String applicantName,
    required String applicantContact,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to apply');
    await _db.collection('catechistApplications').add({
      'applicantId': uid, 'applicantName': applicantName, 'applicantContact': applicantContact,
      'type': 'trustedSeller', 'level': 'national', 'parishId': null,
      'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> isTrustedSeller(String uid) async {
    final snap = await _db.collection('catechistApplications')
        .where('applicantId', isEqualTo: uid).where('type', isEqualTo: 'trustedSeller')
        .where('status', isEqualTo: 'approved').limit(1).get();
    return snap.docs.isNotEmpty;
  }

  /// Enriches each course with its computed average rating, for the
  /// Latest / Top Rated sort toggle. Same N+1-queries-per-list tradeoff
  /// already accepted elsewhere in this app for small collections (the
  /// hierarchy rollups work the same way) - fine here, would need
  /// revisiting if a church ever had a very large number of courses.
  Future<List<Map<String, dynamic>>> getCoursesWithRatings(String parishId, String churchId) async {
    final courses = await getCourses(parishId, churchId);
    final enriched = <Map<String, dynamic>>[];
    for (final c in courses) {
      final rating = await getCourseAverageRating(parishId, churchId, c['id']);
      enriched.add({...c, 'averageRating': rating});
    }
    return enriched;
  }



  Future<void> setUserSuperAdminStatus(String uid, bool isSuperAdmin) async {
    await _db.collection('users').doc(uid).update({'isSuperAdmin': isSuperAdmin});
  }

  Future<void> setUserDeveloperStatus(String uid, bool isDeveloper) async {
    await _db.collection('users').doc(uid).update({'isDeveloper': isDeveloper});
  }

  /// Lower-stakes than isDeveloper deliberately - these only affect
  /// visibility into draft/test content (devOnly items, in-progress
  /// features), never platform control, which is why the rule lets a
  /// plain Super Admin grant these freely rather than requiring a
  /// Developer specifically.
  Future<void> setUserDesignerStatus(String uid, bool isDesigner) async {
    await _db.collection('users').doc(uid).update({'isDesigner': isDesigner});
  }

  Future<void> setUserAuditorStatus(String uid, bool isAuditor) async {
    await _db.collection('users').doc(uid).update({'isAuditor': isAuditor});
  }

  // ---------- App branding (used throughout the app, edited in one place) ----------

  Future<Map<String, dynamic>> getBranding() async {
    final doc = await _db.collection('platformConfig').doc('branding').get();
    return doc.data() ?? {'appName': 'CatholicSA', 'logoUrl': null, 'description': ''};
  }

  Future<void> setBranding(Map<String, dynamic> data) async {
    await _db.collection('platformConfig').doc('branding').set(data, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> getDesignTokens() async {
    final doc = await _db.collection('platformConfig').doc('designTokens').get();
    return doc.data() ?? {'navPosition': 'bottom', 'cornerRadius': 8.0, 'accentColor': '#A9822F'};
  }

  Future<void> setDesignTokens(Map<String, dynamic> tokens) async {
    await _db.collection('platformConfig').doc('designTokens').set(tokens, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> getPendingPopups() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final snap = await _db.collection('users').doc(uid).collection('pendingPopups')
        .where('dismissed', isEqualTo: false).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> dismissPopup(String popupId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).collection('pendingPopups').doc(popupId)
        .update({'dismissed': true});
  }

  Future<Map<String, dynamic>?> getUserDoc(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<UserPreferences> getUserPreferences(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data()?['preferences'] as Map<String, dynamic>?;
    return UserPreferences.fromFirestore(data ?? {});
  }

  Future<void> saveUserPreferences(String uid, UserPreferences prefs) async {
    await _db.collection('users').doc(uid).update({'preferences': prefs.toFirestore()});
  }

  Future<List<Map<String, dynamic>>> getFundraisers(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('fundraisers').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getComments(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Mirrors the rule's isParishAdmin(parishId) || isSuperAdmin() exactly -
  /// has to predict the rule correctly, or a trusted admin's own comment
  /// with a link would fail to post (the rule requires an exact status
  /// match, not just "close enough").
  Future<bool> _isTrustedCommenter(String parishId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    if (parishId == 'demo-parish') return true;
    final adminDoc = await _db.collection('parishes').doc(parishId).collection('admins').doc(uid).get();
    if (adminDoc.exists) return true;
    final userDoc = await getUserDoc(uid);
    return userDoc?['isSuperAdmin'] == true || userDoc?['isDeveloper'] == true;
  }

  Future<void> addComment({
    required String parishId,
    required String churchId,
    required int rating,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    // Same link-pattern the rule itself checks independently - computed
    // here so the initial write matches what the rule requires, but the
    // rule is what actually enforces it, not this.
    final containsLink = RegExp(r'https?://|www\.').hasMatch(text);
    final isTrusted = await _isTrustedCommenter(parishId);
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('comments')
        .add({
      'userId': user?.uid,
      'userDisplayName': user?.displayName ?? 'Anonymous',
      'rating': rating,
      'text': text,
      'hidden': false,
      'hiddenReason': null,
      'likeCount': 0,
      'containsLink': containsLink,
      'status': (containsLink && !isTrusted) ? 'pendingModeration' : 'visible',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Throws if the comment no longer exists (its own author may have
  /// deleted it since a report was filed) - callers that need to treat a
  /// vanished comment as a normal, expected case catch this explicitly
  /// rather than getting back a silent null.
  Future<Map<String, dynamic>> getCommentById(String parishId, String churchId, String commentId) async {
    final doc = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('comments').doc(commentId).get();
    if (!doc.exists) throw Exception('Comment no longer exists');
    return {'id': doc.id, ...doc.data()!};
  }

  Future<void> deleteComment(String parishId, String churchId, String commentId) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('comments').doc(commentId)
        .delete();
  }

  /// A hidden comment's own author and any admin can still see it (the
  /// rule allows this) - hiding it from general display is a client-side
  /// choice about who's viewing, not the mechanism that actually protects
  /// anyone, which is the rule itself.
  Future<void> approveComment(String parishId, String churchId, String commentId) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('comments').doc(commentId)
        .update({'status': 'visible'});
  }

  Future<void> setCommentHidden({
    required String parishId,
    required String churchId,
    required String commentId,
    required bool hidden,
    String? reason,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('comments').doc(commentId)
        .update({'hidden': hidden, 'hiddenReason': reason});
  }

  Future<bool> isCommentLikedByMe(String parishId, String churchId, String commentId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('comments').doc(commentId)
        .collection('likes').doc(uid).get();
    return doc.exists;
  }

  /// Only ever touches the tiny likes/{uid} doc - likeCount on the
  /// comment itself is never written from the client, the matching
  /// Cloud Function trigger (onCommentLikeChange) keeps it authoritative.
  Future<void> toggleCommentLike(String parishId, String churchId, String commentId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to like a comment');
    final likeRef = _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('comments').doc(commentId)
        .collection('likes').doc(uid);
    final doc = await likeRef.get();
    if (doc.exists) {
      await likeRef.delete();
    } else {
      await likeRef.set({'likedAt': FieldValue.serverTimestamp()});
    }
  }

  /// Reuses the existing reports collection and admin review screen
  /// rather than building a second, parallel moderation queue - a
  /// comment report is just a report with a pointer back to the comment.
  Future<void> reportComment({
    required String parishId,
    required String churchId,
    required String commentId,
    required String reason,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('reports')
        .add({
      'text': 'Comment reported: $reason',
      'reportType': 'comment',
      'targetCommentId': commentId,
      'userId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'open',
    });
  }

  /// Always includes the parish-wide default associations (CWL, SVP, etc.)
  /// PLUS anything this specific church has added on top (like a Choir
  /// with its own practice time) - not an either/or fallback, since a
  /// church having one of its own groups shouldn't hide the parish-wide ones.
  Future<List<Map<String, dynamic>>> getAssociations(String parishId, String churchId) async {
    final parishSnap = await _db.collection('parishes').doc(parishId).collection('associations').get();
    final churchSnap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('associations').get();
    return [
      ...parishSnap.docs.map((d) => {'id': d.id, ...d.data()}),
      ...churchSnap.docs.map((d) => {'id': d.id, ...d.data()}),
    ];
  }

  Future<List<Map<String, dynamic>>> getDevotions(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('devotions').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getNotices(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('notices').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getEvents(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('events').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Every upcoming event across every church - for the app-wide Events tab.
  /// Walks parishes -> churches -> events directly (same pattern as
  /// getAllChurches) rather than a collectionGroup query, since that query
  /// type had inconsistent rule-evaluation behaviour on this project before.
  Future<List<Map<String, dynamic>>> getAllUpcomingEvents() async {
    final parishesSnap = await _db.collection('parishes').get();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final results = <Map<String, dynamic>>[];
    for (final parishDoc in parishesSnap.docs) {
      final churchesSnap = await parishDoc.reference.collection('churches').get();
      for (final churchDoc in churchesSnap.docs) {
        final eventsSnap = await churchDoc.reference.collection('events').get();
        for (final e in eventsSnap.docs) {
          final data = e.data();
          final date = (data['date'] as Timestamp?)?.toDate();
          if (date == null || date.isBefore(today)) continue; // skip past events
          results.add({
            'id': e.id,
            'parishId': parishDoc.id,
            'churchId': churchDoc.id,
            'churchName': churchDoc.data()['name'],
            ...data,
          });
        }
      }
    }
    results.sort((a, b) => (a['date'] as Timestamp).compareTo(b['date'] as Timestamp));
    return results;
  }

  Future<void> submitReport({required String parishId, required String churchId, required String text}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('reports')
        .add({'text': text, 'userId': uid, 'createdAt': FieldValue.serverTimestamp(), 'status': 'open'});
  }

  Future<String?> getSafeguardingPolicy(String parishId) async {
    final doc = await _db.collection('parishes').doc(parishId).collection('policies').doc('safeguarding').get();
    return doc.data()?['body'] as String?;
  }

  Future<bool> isFavourite(String churchId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db.collection('users').doc(uid).collection('favouriteChurches').doc(churchId).get();
    return doc.exists;
  }

  Future<void> toggleFavourite(String churchId, {required String parishId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to save favourites');
    final ref = _db.collection('users').doc(uid).collection('favouriteChurches').doc(churchId);
    final doc = await ref.get();
    if (doc.exists) {
      await ref.delete();
    } else {
      // parishId AND churchId both stored here (not just as the doc ID) -
      // the churchId field specifically is what lets the "new notice"
      // Cloud Function run a collectionGroup query to find everyone who
      // favourited this exact church, across every user's subcollection.
      await ref.set({'parishId': parishId, 'churchId': churchId, 'addedAt': FieldValue.serverTimestamp()});
    }
  }

  /// Resolves each favourite into the real Church object, using the stored
  /// parishId - no guessing or cross-parish lookup needed.
  Future<List<Church>> getFavouriteChurches() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final snap = await _db.collection('users').doc(uid).collection('favouriteChurches').get();
    final churches = <Church>[];
    for (final doc in snap.docs) {
      final parishId = doc.data()['parishId'] as String?;
      if (parishId == null) continue; // skip any legacy favourite saved before this fix
      try {
        churches.add(await getChurch(parishId, doc.id));
      } catch (_) {
        // church may have been deleted since being favourited - skip quietly
      }
    }
    return churches;
  }

  /// Real, road-following route between two points via OSRM's free public
  /// routing server - no API key, no cost. Not meant for heavy production
  /// traffic (it's a shared demo instance with no uptime guarantee); worth
  /// swapping to a paid provider (Google/Mapbox Directions) once this app
  /// has real usage at scale.
  /// Just duration + distance, not the full route geometry - lighter
  /// request than getRoute() since "can I make it in time" only needs the
  /// numbers, not a line to draw.
  Future<Map<String, double>?> getRouteWithDuration(LatLng from, LatLng to) async {
    final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=false');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final route = data['routes']?[0];
      if (route == null) return null;
      return {
        'durationMinutes': (route['duration'] as num) / 60,
        'distanceKm': (route['distance'] as num) / 1000,
      };
    } catch (_) {
      return null;
    }
  }

  Future<List<LatLng>?> getRoute(LatLng from, LatLng to) async {
    final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final coords = data['routes']?[0]?['geometry']?['coordinates'] as List<dynamic>?;
      if (coords == null) return null;
      return coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
    } catch (_) {
      return null; // network hiccup or demo server unavailable - caller falls back to straight line
    }
  }
  /// time and leaves contact details, which only this parish's admins can
  /// ever see (enforced in firestore.rules, not just here).
  Future<void> submitConfessionBooking({
    required String parishId,
    required String churchId,
    required String name,
    required String contactPhone,
    String? contactEmail,
    required String availability,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('confessionBookingRequests')
        .add({
      'userId': uid,
      'name': name,
      'contactPhone': contactPhone,
      'contactEmail': contactEmail,
      'availability': availability,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------- Map: nearby churches across the whole country ----------
  // MVP scale (a handful of parishes) - walk parishes directly and collect
  // their churches, rather than using a collectionGroup() query. This is
  // the same query pattern the Browse screen already uses successfully;
  // collectionGroup queries can have inconsistent rule-evaluation behaviour
  // on some projects even when the underlying rules are correct, so this
  // sidesteps that entirely. Once there are many parishes, this can be
  // revisited (either retry collectionGroup, or add geohash-range queries).

  Future<List<Church>> getAllChurches() async {
    final parishesSnap = await _db.collection('parishes').get();
    final List<Church> allChurches = [];
    for (final parishDoc in parishesSnap.docs) {
      final churchesSnap = await parishDoc.reference.collection('churches').get();
      allChurches.addAll(churchesSnap.docs.map((d) => Church.fromFirestore(d.id, d.data())));
    }
    return allChurches;
  }
}