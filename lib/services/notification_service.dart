import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Turns the existing Settings > Notifications toggles into something real.
/// Scope, deliberately: this saves the token and handles foreground display.
/// It does NOT yet handle notification-tap deep-linking (opening the right
/// church/notice when someone taps a notification) - that's real, separate
/// work worth doing once this base pipeline is confirmed working end to end.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;

  // Web specifically requires a VAPID key to fetch a token at all -
  // getToken() otherwise fails silently on web (Android/iOS don't need
  // this). Generate one in Firebase Console under Project Settings >
  // Cloud Messaging > Web Push certificates, and paste it here. Push
  // notifications on web will not work until this is filled in.
  static const String _webVapidKey = 'BCXhfRwkPTgNTRKgdFT7V1WyUj05VZkiwKtFpkGsvrPjuD2_a2Af-d_iYG0NXWr5RGqSrkrCNjU86NtwB64TbvM';

  /// Call this after sign-in, and on app startup if already signed in.
  /// Silently does nothing if the user denies permission or isn't signed in -
  /// there's no good way to force this, and there shouldn't be one.
  Future<void> requestPermissionAndSaveToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }

    final token = kIsWeb
        ? await _messaging.getToken(vapidKey: _webVapidKey)
        : await _messaging.getToken();
    if (token != null) {
      await _saveToken(user.uid, token);
    }

    // Devices can get reassigned a new token at any time (app reinstall,
    // token expiry) - without this, notifications would silently stop
    // working for that device until the person happened to sign out and in.
    _messaging.onTokenRefresh.listen((newToken) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) _saveToken(currentUser.uid, newToken);
    });
  }

  Future<void> _saveToken(String uid, String token) async {
    await _db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// Call once, near app startup - shows a simple in-app banner when a
  /// push notification arrives while the app is already open (foreground
  /// messages don't show a system notification automatically on their own).
  void listenForForegroundMessages(void Function(RemoteMessage message) onMessage) {
    FirebaseMessaging.onMessage.listen(onMessage);
  }

  /// Best-effort removal of this device's token on sign-out, so a shared or
  /// previously-used device doesn't keep receiving another account's
  /// notifications after the person signs out of it.
  Future<void> removeTokenOnSignOut(String uid) async {
    final token = await _messaging.getToken();
    if (token == null) return;
    await _db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
    }, SetOptions(merge: true));
  }
}
