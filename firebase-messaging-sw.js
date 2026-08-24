// Required for Firebase Cloud Messaging to work on Flutter Web at all -
// without this file, web push notifications silently never arrive, even
// with everything else configured correctly.
//
// This file can't contain your real project's values because
// lib/firebase_options.dart isn't part of this sandbox - it's generated
// locally on your machine by `flutterfire configure` and never uploaded
// here. Copy the matching values from your own lib/firebase_options.dart,
// specifically from the `web` FirebaseOptions block (NOT android or ios).

importScripts("https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyCmq5s22LQrUvZU-bwCR5PH44rnmlLtOg4",
  appId: "1:38606314792:web:5900760d39706470a8041d",
  messagingSenderId: "38606314792",
  projectId: "catholicsa-61b87",
  authDomain: "catholicsa-61b87.firebaseapp.com",
  storageBucket: "catholicsa-61b87.firebasestorage.app",
});



const messaging = firebase.messaging();

// Handles a push arriving while the browser tab is closed or backgrounded.
// Foreground messages (tab open and focused) are handled separately in
// Dart via NotificationService.listenForForegroundMessages - this only
// covers the background/closed case.
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || "CatholicSA";
  const body = payload.notification?.body || "";
  self.registration.showNotification(title, { body, icon: "/icons/Icon-192.png" });
});