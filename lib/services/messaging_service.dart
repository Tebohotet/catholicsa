import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';

/// See content_courses_service.dart for why this file exists - same
/// reasoning, different domain slice: real 1:1 in-app messaging, backed
/// by a top-level `conversations` collection (see firestore.rules for the
/// participants-only access rule this all depends on).
extension MessagingService on FirestoreService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Deterministic, not random - two people always land on the same
  /// conversation no matter who messages whom first, by sorting the two
  /// uids. This is also exactly what firestore.rules' create check on
  /// `participants` relies on being stable.
  String _conversationIdFor(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Finds (or silently creates) the one conversation between the
  /// signed-in user and [otherUid]. Stores both display names on the
  /// conversation doc itself, so an inbox list can render immediately
  /// without a second read per conversation.
  Future<String> getOrCreateConversation(String otherUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to message');
    if (uid == otherUid) throw Exception("You can't message yourself");
    final conversationId = _conversationIdFor(uid, otherUid);
    final ref = _db.collection('conversations').doc(conversationId);
    final doc = await ref.get();
    if (!doc.exists) {
      final myDoc = await _db.collection('users').doc(uid).get();
      final otherDoc = await _db.collection('users').doc(otherUid).get();
      await ref.set({
        'participants': [uid, otherUid],
        'participantNames': {
          uid: myDoc.data()?['displayName'] ?? 'Someone',
          otherUid: otherDoc.data()?['displayName'] ?? 'Someone',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    }
    return conversationId;
  }

  Future<void> sendMessage({required String conversationId, required String text}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sign in to message');
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final conversationRef = _db.collection('conversations').doc(conversationId);
    await conversationRef.collection('messages').add({
      'senderId': uid,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await conversationRef.set({
      'lastMessage': trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': uid,
    }, SetOptions(merge: true));
  }

  Stream<List<Map<String, dynamic>>> streamMessages(String conversationId) {
    return _db
        .collection('conversations').doc(conversationId).collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// This signed-in user's conversation inbox, most recently active first.
  Stream<List<Map<String, dynamic>>> streamMyConversations() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.empty();
    return _db
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              final names = Map<String, dynamic>.from(data['participantNames'] as Map? ?? {});
              final otherUid = (data['participants'] as List).firstWhere((p) => p != uid, orElse: () => uid);
              return {
                'id': d.id,
                'otherUid': otherUid,
                'otherName': names[otherUid] ?? 'Someone',
                'lastMessage': data['lastMessage'],
                'lastMessageAt': data['lastMessageAt'],
              };
            }).toList());
  }
}
