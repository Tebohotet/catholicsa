import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart' as prod;
import 'firebase_options_dev.dart' as dev;
import 'config/app_environment.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Production unless this build was made with --dart-define=APP_ENV=staging
  // (see config/app_environment.dart) - staging talks to the separate
  // catholicsa-dev project, with its own Firestore/Auth/Storage.
  await Firebase.initializeApp(
    options: isStaging
        ? dev.DefaultFirebaseOptions.currentPlatform
        : prod.DefaultFirebaseOptions.currentPlatform,
  );

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
  runApp(const ProviderScope(child: _StagingBanner(child: CatholicSAApp())));
}

/// Puts a "STAGING" corner ribbon over the whole app in staging builds, so
/// nobody mistakes the dev site for the real one (or vice versa). Does
/// nothing at all in production builds.
class _StagingBanner extends StatelessWidget {
  const _StagingBanner({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isStaging) return child;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Banner(
        message: 'STAGING',
        location: BannerLocation.topStart,
        color: Colors.deepOrange,
        child: child,
      ),
    );
  }
}
