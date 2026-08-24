import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Web has offline persistence OFF by default (mobile already has it ON
  // by default, so this is a no-op there but harmless to set explicitly).
  // Matters here specifically because data cost is a real constraint for
  // our users - once something's been read once, it's cached locally and
  // doesn't need a fresh network round-trip every time the app reopens.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // ProviderScope must wrap everything, including the MaterialApp itself -
  // it's what makes ref.watch()/ref.read() work anywhere below it.
  runApp(const ProviderScope(child: CatholicSAApp()));
}
