import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'firestore_service.dart';

/// See content_courses_service.dart for why this file exists - same
/// reasoning, different domain slice.
extension MarketplaceAdminService on FirestoreService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  // ---------- Training / demo sandbox ----------
  // The demo parish (id: 'demo-parish') is a permanent fixture, not
  // seeded-once-and-forgotten - firestore.rules grants every signed-in
  // user full admin rights there specifically so new trainees never need
  // manual provisioning. This reset writes fresh practice content covering
  // every admin workflow in the app (a pending photo to approve, an
  // unanswered comment to reply to, a draft course to review and publish,
  // an open booking/report to resolve) so a trainee can exercise the whole
  // system, then reset it back to a clean slate for the next person.
  Future<void> resetDemoData() async {
    const parishId = 'demo-parish';
    const churchId = 'demo-church';
    final churchRef = _db.collection('parishes').doc(parishId).collection('churches').doc(churchId);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in first to reset the demo data');

    // Clear simple flat collections first.
    for (final coll in ['services', 'devotions', 'associations', 'notices', 'events', 'confessionBookingRequests', 'reports', 'media']) {
      final snap = await churchRef.collection(coll).get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    // Comments: only clear ones this same trainee created before (rules
    // don't allow deleting other users' comments, which is correct - a
    // "reset" shouldn't be able to erase someone else's content).
    final commentsSnap = await churchRef.collection('comments').where('userId', isEqualTo: uid).get();
    for (final doc in commentsSnap.docs) {
      await doc.reference.delete();
    }

    // Courses: clear lessons subcollection first (Firestore doesn't
    // cascade-delete), then the course docs themselves. Enrollments are
    // left alone for the same ownership reason as comments above.
    final coursesSnap = await churchRef.collection('courses').get();
    for (final courseDoc in coursesSnap.docs) {
      final lessonsSnap = await courseDoc.reference.collection('lessons').get();
      for (final lesson in lessonsSnap.docs) {
        await lesson.reference.delete();
      }
      final ownEnrollment = await courseDoc.reference.collection('enrollments').doc(uid).get();
      if (ownEnrollment.exists) await ownEnrollment.reference.delete();
      await courseDoc.reference.delete();
    }

    // --- Now write fresh, realistic practice content ---

    await addDevotion(parishId: parishId, churchId: churchId, name: 'Eucharistic Adoration', dayOfWeek: 'Thursday', time: '19:00');

    await addChurchAssociation(
      parishId: parishId, churchId: churchId,
      name: 'Youth Group', purpose: 'Weekly fellowship and faith formation for teens',
      contactPerson: 'Demo Coordinator', meetingDay: 'Friday', meetingTime: '18:00',
    );

    await addNotice(parishId: parishId, churchId: churchId, title: 'Baptisms', body: 'Contact the parish office to book a baptism date. This is a standing notice - practice editing or deleting it.');
    await addNotice(parishId: parishId, churchId: churchId, title: 'Parish Bazaar', body: 'Annual fundraising bazaar - stalls, food, and games for the whole family.');

    await addEvent(
      parishId: parishId, churchId: churchId,
      title: 'Training Fun Day', description: 'A sample event - notice it can also cross-list into Parochial Notices.',
      date: DateTime.now().add(const Duration(days: 7)), time: '10:00', category: 'Community', showInNotices: true,
    );

    await _db.collection('parishes').doc(parishId).collection('churches').doc(churchId).collection('services').add({
      'date': Timestamp.fromDate(DateTime.now().add(Duration(days: (7 - DateTime.now().weekday) % 7))),
      'time': '09:00', 'type': 'Mass', 'language': 'EN',
    });

    // A comment with no reply yet - practice the admin reply workflow.
    await addComment(parishId: parishId, churchId: churchId, rating: 5, text: 'Sample comment awaiting a reply - practice replying to this from the Admin Panel.');

    // A pending confession booking - practice "mark as contacted".
    await submitConfessionBooking(parishId: parishId, churchId: churchId, name: 'Demo Trainee', contactPhone: '000 000 0000', availability: 'Weekday afternoons');

    // An open report - practice "mark as resolved".
    await submitReport(parishId: parishId, churchId: churchId, text: 'Sample report - practice marking this resolved from the Admin Panel.');

    // A draft course with one lesson - practice the full review workflow
    // (submit for review, then approve as priest, since every trainee is
    // treated as a priest-level admin in the demo parish).
    await addCourse(
      parishId: parishId, churchId: churchId,
      title: 'Sample Course - Introduction to the Faith',
      description: 'A practice course. Submit it for review, then approve it, then enroll and read the lesson.',
      catechistName: 'Demo Catechist',
    );
    final freshCourses = await getCourses(parishId, churchId, onlyPublished: false);
    if (freshCourses.isNotEmpty) {
      await addLesson(
        parishId: parishId, churchId: churchId, courseId: freshCourses.first['id'],
        title: 'Lesson 1: Getting Started',
        blocks: [{'type': 'text', 'text': 'This is sample lesson content for training purposes.'}],
        order: 1,
      );
    }
  }

  // ---------- Role assignment (Super Admin only, enforced by rules) ----------

  /// The user must have signed in at least once already - that's what
  /// creates their users/{uid} doc in the first place. No way around that
  /// with a normal login flow, and there shouldn't be one.
  /// Generic profile field update for the Users admin screen - merges
  /// whatever fields are passed rather than requiring a full profile
  /// object, so this works for editing a single field (a phone number)
  /// or several at once without a rigid, all-fields-required shape.
  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> findUserByEmail(String email) async {
    final snap = await _db.collection('users').where('email', isEqualTo: email.trim()).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return {'uid': snap.docs.first.id, ...snap.docs.first.data()};
  }

  /// Broader than findUserByEmail - matches a partial name or email
  /// substring, not just an exact address. Firestore has no native
  /// substring search, so this fetches a capped batch and filters
  /// client-side - the same honest, accepted-at-current-scale pattern
  /// already used elsewhere in this codebase (resolveAudience's
  /// province scope, searchBibleVerses). Fine for hundreds of users;
  /// would need a real search index (Algolia or similar) well before
  /// this app reaches thousands.
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final snap = await _db.collection('users').limit(500).get();
    final results = snap.docs.where((d) {
      final data = d.data();
      final name = (data['displayName'] as String? ?? '').toLowerCase();
      final email = (data['email'] as String? ?? '').toLowerCase();
      return name.contains(q) || email.contains(q);
    }).map((d) => {'uid': d.id, ...d.data()}).toList();
    return results;
  }

  Future<List<Map<String, dynamic>>> getParishAdmins(String parishId) async {
    final snap = await _db.collection('parishes').doc(parishId).collection('admins').get();
    return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
  }

  /// The inverse of getParishAdmins - given a user, which parishes are
  /// they actually admin of. Parish admin docs are keyed by uid
  /// (parishes/{id}/admins/{uid}) with no uid field inside the document
  /// itself, so a collection-group query can't filter server-side by
  /// document ID here - this scans every admin doc across every parish
  /// and matches by doc.id client-side. Same honest full-scan pattern
  /// as searchUsers above; fine at current scale (dozens of parishes,
  /// not thousands).
  Future<List<Map<String, dynamic>>> getParishesUserAdministers(String uid) async {
    final snap = await _db.collectionGroup('admins').get();
    final matches = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      if (doc.id != uid) continue;
      final parishRef = doc.reference.parent.parent;
      if (parishRef == null) continue;
      final parishDoc = await parishRef.get();
      matches.add({
        'parishId': parishRef.id,
        'parishName': parishDoc.exists ? (parishDoc.data()?['name'] ?? '') : '(deleted parish)',
        'role': doc.data()['role'],
      });
    }
    return matches;
  }

  Future<void> assignParishAdmin({
    required String parishId,
    required String uid,
    required String role,
    required String displayName,
    required String email,
  }) async {
    await _db.collection('parishes').doc(parishId).collection('admins').doc(uid).set({
      'role': role, 'displayName': displayName, 'email': email,
      'status': 'active', 'verified': true, 'addedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeParishAdmin(String parishId, String uid) async {
    await _db.collection('parishes').doc(parishId).collection('admins').doc(uid).delete();
  }

  Future<void> submitMassIntentionRequest({
    required String parishId,
    required String churchId,
    required String requesterName,
    required String intentionFor,
    String? preferredDate,
    required String contactPhone,
    String? contactEmail,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to request a Mass intention');
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('massIntentionRequests')
        .add({
      'userId': uid,
      'requesterName': requesterName,
      'intentionFor': intentionFor,
      'preferredDate': preferredDate,
      'contactPhone': contactPhone,
      'contactEmail': contactEmail,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getMassIntentionRequests(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('massIntentionRequests')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> updateMassIntentionStatus(String parishId, String churchId, String requestId, String status) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('massIntentionRequests').doc(requestId)
        .update({'status': status});
  }

  Future<List<Map<String, dynamic>>> getAllSaints() async {
    final snap = await _db.collection('saints').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> addSaint(Map<String, dynamic> data) async {
    await _db.collection('saints').add(data);
  }

  Future<void> updateSaint(String id, Map<String, dynamic> data) async {
    await _db.collection('saints').doc(id).update(data);
  }

  Future<void> deleteSaint(String id) async {
    await _db.collection('saints').doc(id).delete();
  }

  /// Same upload pattern already used elsewhere in this app (media,
  /// products) - bytes in, real download URL out.
  Future<String> uploadSaintImage(XFile file) async {
    final bytes = await file.readAsBytes();
    final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
    final storagePath = 'saints/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<List<String>> getPatronageTags() async {
    final snap = await _db.collection('patronageTags').get();
    return snap.docs.map((d) => d.data()['name'] as String? ?? '').where((n) => n.isNotEmpty).toList()..sort();
  }

  /// Called automatically whenever a saint is saved with a patronage tag
  /// that isn't already in the shared list - the list grows on its own
  /// as real data gets entered, no separate admin step required.
  Future<void> ensurePatronageTagsExist(List<String> tags) async {
    final existing = await getPatronageTags();
    final existingLower = existing.map((t) => t.toLowerCase()).toSet();
    for (final tag in tags) {
      if (!existingLower.contains(tag.toLowerCase())) {
        await _db.collection('patronageTags').add({'name': tag});
      }
    }
  }

  Future<void> updateUserBirthday(String uid, String? birthMonthDay) async {
    await _db.collection('users').doc(uid).update({'birthMonthDay': birthMonthDay});
  }

  /// Deliberately separate from feastMonthDay - a saint's actual birth
  /// date (when known) versus the feast day the Church celebrates them
  /// on are two different things, and this specifically needs the
  /// former to answer "which saint shares my birthday."
  Future<List<Map<String, dynamic>>> getSaintsSharingBirthday(String monthDay) async {
    final snap = await _db.collection('saints').where('birthMonthDay', isEqualTo: monthDay).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ---------- Marketplace listings (Phase 1: listings only, no payment) ----------

  Future<String> submitProduct({
    required String parishId,
    required String churchId,
    required String title,
    required String description,
    required double price,
    required String sellerName,
    required String sellerContact,
    required String fulfillmentMethod, // 'pickup' | 'courier'
    required double refundPercent, // 0-100, seller's own policy for this item
    String? groupId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to list an item');
    final ref = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').add({
      'sellerId': uid,
      'title': title,
      'description': description,
      'price': price,
      'currency': 'ZAR',
      'sellerName': sellerName,
      'sellerContact': sellerContact,
      'fulfillmentMethod': fulfillmentMethod,
      'refundPercent': refundPercent,
      'groupId': groupId,
      'imageUrl': null,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Uploaded after the product doc exists (needs its ID for the storage
  /// path), same two-step shape already used for proof-of-payment. Public
  /// read once approved - a listing photo isn't sensitive the way a bank
  /// deposit slip is, so this can sit in the same public tier as gallery
  /// media rather than the signed-in-only proof tiers.
  Future<void> uploadProductImage({
    required String parishId,
    required String churchId,
    required String productId,
    required Uint8List bytes,
  }) async {
    final storagePath = 'churches/$parishId/$churchId/products/$productId.jpg';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .update({'imageUrl': url});
  }

  Future<List<Map<String, dynamic>>> getApprovedProducts(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products')
        .where('status', isEqualTo: 'approved')
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getAllProducts(String parishId, String churchId) async {
    final snap = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> updateProductStatus(String parishId, String churchId, String productId, String status) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .update({'status': status});
  }

  /// A seller's own listings across every church they've sold at - the
  /// missing counterpart to getMyOrders/getMyDonations. Without this, a
  /// seller could list an item and never see it again to fix a typo or
  /// update the price, even though the rule has always supported them
  /// doing exactly that.
  Future<List<Map<String, dynamic>>> getMyProducts(String uid) async {
    final snap = await _db.collectionGroup('products').where('sellerId', isEqualTo: uid).get();
    return snap.docs.map((d) => {'id': d.id, 'parishId': d.reference.parent.parent!.parent.parent!.id, 'churchId': d.reference.parent.parent!.id, ...d.data()}).toList();
  }

  /// Content fields only - matches the rule exactly, which is what
  /// actually enforces that a seller editing their own listing can never
  /// touch status this way. This method existing at all doesn't bypass
  /// that; the rule would reject an attempt to slip status in here too.
  Future<void> updateProduct({
    required String parishId, required String churchId, required String productId,
    required String title, required String description, required double price,
    required String fulfillmentMethod, required double refundPercent, String? groupId,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .update({
      'title': title, 'description': description, 'price': price,
      'fulfillmentMethod': fulfillmentMethod, 'refundPercent': refundPercent, 'groupId': groupId,
    });
  }

  Future<void> deleteProduct(String parishId, String churchId, String productId) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .delete();
  }

  // ---------- Store item groups (Bible, Rosary, Candle, etc.) - platform-wide ----------

  Future<List<Map<String, dynamic>>> getProductGroups() async {
    final snap = await _db.collection('productGroups').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> addProductGroup(String name) async {
    await _db.collection('productGroups').add({'name': name});
  }

  Future<void> updateProductGroup(String groupId, String name) async {
    await _db.collection('productGroups').doc(groupId).update({'name': name});
  }

  Future<void> deleteProductGroup(String groupId) async {
    await _db.collection('productGroups').doc(groupId).delete();
  }

  // Same rollup composition used for Notices/Prayers/Courses/Gallery -
  // Parish walks its churches, Diocese walks its parishes (reusing the
  // Parish version), Province walks its dioceses, National walks every
  // province. One pattern, four levels, nothing new to design each time.

  Future<List<Map<String, dynamic>>> getParishProducts(String parishId) async {
    final churches = await getChurches(parishId);
    final results = <Map<String, dynamic>>[];
    for (final c in churches) {
      final products = await getApprovedProducts(parishId, c.id);
      for (final p in products) {
        results.add({...p, 'churchId': c.id, 'churchName': c.name});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getDioceseProducts(String dioceseId) async {
    final parishes = await getParishes(dioceseId);
    final results = <Map<String, dynamic>>[];
    for (final p in parishes) {
      final products = await getParishProducts(p['id']);
      for (final prod in products) {
        results.add({...prod, 'parishId': p['id'], 'parishName': p['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getProvinceProducts(String provinceId) async {
    final dioceses = await getDioceses(provinceId);
    final results = <Map<String, dynamic>>[];
    for (final d in dioceses) {
      final products = await getDioceseProducts(d['id']);
      for (final prod in products) {
        results.add({...prod, 'dioceseId': d['id'], 'dioceseName': d['name']});
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getNationalProducts() async {
    final provinces = await getProvinces();
    final results = <Map<String, dynamic>>[];
    for (final prov in provinces) {
      final products = await getProvinceProducts(prov['id']);
      for (final prod in products) {
        results.add({...prod, 'provinceId': prov['id'], 'provinceName': prov['name']});
      }
    }
    return results;
  }

  // ---------- Payment gateway config (Phase 2: settings only, not a working checkout) ----------

  Future<Map<String, dynamic>?> getPaymentGatewayConfig(String parishId) async {
    final doc = await _db.collection('parishes').doc(parishId).collection('private').doc('paymentGateway').get();
    return doc.exists ? doc.data() : null;
  }

  /// Fields left null/omitted here are simply not overwritten - lets the
  /// UI send only what actually changed (e.g. a blank secret-key field
  /// means "keep the existing one", not "clear it").
  Future<void> savePaymentGatewayConfig(String parishId, Map<String, dynamic> data) async {
    await _db.collection('parishes').doc(parishId).collection('private').doc('paymentGateway')
        .set({...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    // Mirrored onto the public parish doc deliberately - which gateway is
    // in use isn't sensitive (only the actual keys are), and a buyer
    // needs to know this to know whether a platform fee applies, without
    // ever needing read access to the private credentials themselves.
    await _db.collection('parishes').doc(parishId).update({'paymentProvider': data['provider']});
  }

  Future<String> getPublicPaymentProvider(String parishId) async {
    final doc = await _db.collection('parishes').doc(parishId).get();
    return doc.data()?['paymentProvider'] ?? 'platform';
  }

  // ---------- Bank details (for the manual "deposit to bank" flow) ----------

  Future<void> updateBankDetails(String parishId, Map<String, dynamic> data) async {
    await _db.collection('parishes').doc(parishId).update({'bankDetails': data});
  }

  Future<Map<String, dynamic>?> getBankDetails(String parishId) async {
    final doc = await _db.collection('parishes').doc(parishId).get();
    return doc.data()?['bankDetails'] as Map<String, dynamic>?;
  }

  // ---------- Coupons (parish-wide, usable across any of its listings) ----------

  Future<List<Map<String, dynamic>>> getCoupons(String parishId) async {
    final snap = await _db.collection('parishes').doc(parishId).collection('coupons').get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> addCoupon(String parishId, Map<String, dynamic> data) async {
    await _db.collection('parishes').doc(parishId).collection('coupons').add(data);
  }

  Future<void> updateCoupon(String parishId, String couponId, Map<String, dynamic> data) async {
    await _db.collection('parishes').doc(parishId).collection('coupons').doc(couponId).update(data);
  }

  Future<void> deleteCoupon(String parishId, String couponId) async {
    await _db.collection('parishes').doc(parishId).collection('coupons').doc(couponId).delete();
  }

  /// Returns the coupon if it exists, is active, and hasn't expired -
  /// null otherwise so the UI can show one clear "invalid code" message
  /// rather than needing to know which of the three reasons applied.
  /// [productId] is the item being purchased right now - a seller-created
  /// coupon is scoped to their own product, so a code meant for one
  /// listing shouldn't quietly work on someone else's in the same parish.
  /// Parish-wide coupons (scope 'parish', priest-created) apply everywhere.
  Future<Map<String, dynamic>?> validateCoupon(String parishId, String code, {String? productId}) async {
    final snap = await _db.collection('parishes').doc(parishId).collection('coupons')
        .where('code', isEqualTo: code.trim().toUpperCase()).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final coupon = snap.docs.first.data();
    if (coupon['active'] != true) return null;
    if (coupon['scope'] == 'product' && coupon['productId'] != productId) return null;
    final expiresAt = coupon['expiresAt'] as String?;
    if (expiresAt != null && expiresAt.isNotEmpty) {
      final expiry = DateTime.tryParse(expiresAt);
      if (expiry != null && DateTime.now().isAfter(expiry)) return null;
    }
    return {'id': snap.docs.first.id, ...coupon};
  }

  /// Coupons a specific seller created for their own listing - used to
  /// show "my coupons" on their product, separate from the priest's
  /// parish-wide list managed in Payment Settings.
  Future<List<Map<String, dynamic>>> getCouponsForProduct(String parishId, String productId) async {
    final snap = await _db.collection('parishes').doc(parishId).collection('coupons')
        .where('productId', isEqualTo: productId).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> addProductCoupon({
    required String parishId,
    required String churchId,
    required String productId,
    required String code,
    required String discountType,
    required double discountValue,
    String? expiresAt,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to create a coupon');
    await _db.collection('parishes').doc(parishId).collection('coupons').add({
      'code': code.trim().toUpperCase(),
      'discountType': discountType,
      'discountValue': discountValue,
      'active': true,
      'expiresAt': expiresAt,
      'scope': 'product',
      'productId': productId,
      'churchId': churchId,
      'createdBy': uid,
    });
  }

  // ---------- Orders (manual bank-deposit flow, ahead of real online checkout) ----------

  Future<String> createOrder({
    required String parishId,
    required String churchId,
    required String productId,
    required String productTitle,
    required String sellerId,
    required int quantity,
    required double originalAmount,
    required double discountAmount,
    required double finalAmount,
    String? couponCode,
    required String buyerName,
    required String buyerContact,
    required String fulfillmentMethod, // 'pickup' | 'courier', copied from the product
    String? deliveryAddress, // required only when fulfillmentMethod == 'courier'
    required double refundPercent, // snapshot from the product's own policy at purchase time
    required bool sellerHasOwnGateway, // if true, no platform fee applies - the parish/seller has their own PayFast/PayStack/PayPal
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to place an order');

    // The platform fee only makes sense when money is actually landing
    // with the platform (no gateway configured, "platform default").
    // Once a parish/seller has their own gateway, PayFast's own Split
    // Payments feature is the right place for a commission - not this.
    double feePercent = 0;
    if (!sellerHasOwnGateway) {
      feePercent = await getPlatformFeePercent();
    }
    final feeAmount = finalAmount * (feePercent / 100);
    final payoutAmount = finalAmount - feeAmount;

    final ref = await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .collection('orders').add({
      'parishId': parishId, 'churchId': churchId, 'productId': productId, 'productTitle': productTitle, 'sellerId': sellerId,
      'buyerId': uid, 'buyerName': buyerName, 'buyerContact': buyerContact,
      'quantity': quantity, 'couponCode': couponCode,
      'originalAmount': originalAmount, 'discountAmount': discountAmount, 'finalAmount': finalAmount,
      'paymentMethod': 'bank_deposit',
      'proofOfPaymentUrl': null,
      'status': 'awaiting_payment',
      'fulfillmentMethod': fulfillmentMethod,
      'deliveryAddress': deliveryAddress,
      'fulfillmentStatus': 'pending',
      'fulfillmentUpdates': [],
      'refundPercent': refundPercent,
      'refundStatus': null,
      'refundReason': null,
      'refundAmount': null,
      'platformFeePercent': feePercent,
      'platformFeeAmount': feeAmount,
      'sellerPayoutAmount': payoutAmount,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // ---------- Dev flags: hide in-development features until ready ----------
  // Three states, not a plain boolean:
  //   'off'     - hidden from everyone, including super admins
  //   'preview' - visible ONLY to super admins, so it can be tested for
  //               real before anyone else sees it
  //   'live'    - visible to everyone
  // Reuses platformConfig, same as the marketplace fee - no new rules.

  Future<Map<String, dynamic>> getDevFlags() async {
    final doc = await _db.collection('platformConfig').doc('devFlags').get();
    return doc.data() ?? {};
  }

  Future<void> setDevFlag(String key, String state) async {
    await _db.collection('platformConfig').doc('devFlags').set({key: state}, SetOptions(merge: true));
  }

  Future<void> deleteDevFlag(String key) async {
    await _db.collection('platformConfig').doc('devFlags').update({key: FieldValue.delete()});
  }

  /// The one call every gated feature actually uses. Isolated here so the
  /// "am I allowed to see this" logic lives in exactly one place - a
  /// screen just does `if (await isFeatureVisible('someFlag')) ...`
  /// without needing to know or care about super-admin checks itself.
  Future<bool> isFeatureVisible(String key) async {
    final flags = await getDevFlags();
    final state = flags[key] ?? 'live'; // an unregistered flag defaults open, not hidden
    if (state == 'live') return true;
    if (state == 'off') return false;
    // 'preview'
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final user = await getUserDoc(uid);
    return user?['isSuperAdmin'] == true || user?['isDeveloper'] == true ||
        user?['isDesigner'] == true || user?['isAuditor'] == true;
  }

  // ---------- Platform-wide marketplace fee (super admin only) ----------

  Future<double> getPlatformFeePercent() async {
    final doc = await _db.collection('platformConfig').doc('marketplace').get();
    return (doc.data()?['feePercent'] as num?)?.toDouble() ?? 0;
  }

  Future<void> setPlatformFeePercent(double percent) async {
    await _db.collection('platformConfig').doc('marketplace').set({'feePercent': percent}, SetOptions(merge: true));
  }

  // ---------- Fulfillment (pickup / courier) ----------

  /// 'ready' means "ready for pickup" or "dispatched" depending on
  /// fulfillmentMethod - same underlying value, the UI labels it
  /// differently per method rather than needing two parallel status sets.
  Future<void> updateOrderFulfillmentStatus({
    required String parishId,
    required String churchId,
    required String productId,
    required String orderId,
    required String fulfillmentStatus,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .collection('orders').doc(orderId)
        .update({'fulfillmentStatus': fulfillmentStatus});
  }

  // ---------- Refunds (percentage-based, per seller's own listing policy) ----------

  /// The buyer can only ever set this to 'requested' (enforced by the
  /// rules, not just this method) - approving, denying, or marking it
  /// processed is an admin action. The refund amount is calculated from
  /// the percentage snapshotted on the order at purchase time, not looked
  /// up fresh - a seller changing their policy later shouldn't silently
  /// change what an existing order is owed.
  Future<void> requestRefund({
    required String parishId,
    required String churchId,
    required String productId,
    required String orderId,
    required double finalAmount,
    required double refundPercent,
    required String reason,
  }) async {
    final refundAmount = finalAmount * (refundPercent / 100);
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .collection('orders').doc(orderId)
        .update({
      'refundStatus': 'requested',
      'refundReason': reason,
      'refundAmount': refundAmount,
      'refundRequestedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateOrderRefundStatus({
    required String parishId,
    required String churchId,
    required String productId,
    required String orderId,
    required String refundStatus, // 'approved' | 'denied' | 'processed'
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .collection('orders').doc(orderId)
        .update({'refundStatus': refundStatus});
  }

  /// A buyer's own past orders across every product/church - needed so
  /// they have somewhere to actually find an order again and request a
  /// refund on it, rather than only ever seeing it once at purchase time.
  /// A donor's own donation history across every church - the equivalent
  /// of getMyOrders for the marketplace side. This didn't exist before -
  /// a donor got a one-time push notification on status change and then
  /// had no way to ever see their donation history or read an admin's
  /// note again if they missed it.
  Future<List<Map<String, dynamic>>> getMyDonations(String uid) async {
    final snap = await _db.collectionGroup('donations').where('donorId', isEqualTo: uid)
        .orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// A buyer's own past orders across every product/church - needed so
  /// they have somewhere to actually find an order again and request a
  /// refund on it, rather than only ever seeing it once at purchase time.
  Future<List<Map<String, dynamic>>> getMyOrders(String uid) async {
    final snap = await _db.collectionGroup('orders').where('buyerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Orders where the signed-in user is the seller - what a self-couriering
  /// seller uses to find their own sales and post delivery updates on them.
  Future<List<Map<String, dynamic>>> getMySales(String uid) async {
    final snap = await _db.collectionGroup('orders').where('sellerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Firestore's serverTimestamp() sentinel can't be used inside an array
  /// element (a real Firestore limitation, not a choice) - Timestamp.now()
  /// (the device clock) is used here instead, which is fine for a
  /// human-readable delivery log where exact server precision doesn't matter.
  Future<void> addFulfillmentUpdate({
    required String parishId,
    required String churchId,
    required String productId,
    required String orderId,
    required String note,
    String? photoUrl,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .collection('orders').doc(orderId)
        .update({
      'fulfillmentUpdates': FieldValue.arrayUnion([
        {'note': note, 'photoUrl': photoUrl, 'createdAt': Timestamp.now()},
      ]),
    });
  }

  Future<String> uploadFulfillmentProofPhoto({
    required String parishId,
    required String churchId,
    required String orderId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
    final storagePath = 'churches/$parishId/$churchId/fulfillmentProof/$orderId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<void> uploadProofOfPayment({
    required String parishId,
    required String churchId,
    required String productId,
    required String orderId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
    final isPdf = ext == 'pdf';
    final contentType = isPdf ? 'application/pdf' : 'image/jpeg';
    final storagePath = 'churches/$parishId/$churchId/proofOfPayment/$orderId.$ext';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();

    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .collection('orders').doc(orderId)
        .update({
      'proofOfPaymentUrl': url,
      'proofOfPaymentType': isPdf ? 'pdf' : 'image',
      'status': 'proof_submitted',
    });
  }

  /// collectionGroup query filtered by the churchId field stored on each
  /// order - same reasoning as the favouriteChurches pattern used
  /// elsewhere: collectionGroup queries can't filter by parent document ID
  /// directly, so the field has to be denormalized onto the doc itself.
  /// First run of this query may prompt Firestore to ask for a composite
  /// index to be created - that's normal, just follow the link it gives.
  Future<List<Map<String, dynamic>>> getOrdersForChurch(String churchId) async {
    final snap = await _db.collectionGroup('orders').where('churchId', isEqualTo: churchId).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> updateOrderStatus({
    required String parishId,
    required String churchId,
    required String productId,
    required String orderId,
    required String status,
  }) async {
    await _db
        .collection('parishes').doc(parishId)
        .collection('churches').doc(churchId)
        .collection('products').doc(productId)
        .collection('orders').doc(orderId)
        .update({'status': status});
  }
}