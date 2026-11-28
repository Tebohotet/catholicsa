import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'services/log_service.dart';
import 'app.dart';

Future<void> main() async {
  // Everything (including runApp itself) runs inside this guarded zone -
  // the project owner's own ask: "I normally use Console.WriteLine in
  // C#... Lets have that in our coding so that we just go to the logs and
  // see if all went well." This is the automatic net: three different
  // handlers because Flutter/Dart has three different kinds of "uncaught"
  // - a widget build/layout error (FlutterError.onError), an error from
  // native/platform code or an async gap Flutter's own zone doesn't see
  // (PlatformDispatcher.onError), and anything else truly uncaught
  // anywhere in the zone (runZonedGuarded's own handler). All three just
  // call LogService - see that file for where this actually ends up
  // (Firestore, readable from the new Super Admin -> Logs screen).
  runZonedGuarded(() async {
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

    FlutterError.onError = (details) {
      FlutterError.presentError(details); // still prints to the browser/IDE console as before
      // LogService.error's own `stack` parameter is a real StackTrace?,
      // not a String - it converts internally for storage (see
      // log_service.dart). Pre-converting with .toString() here, like
      // the first version of this file did, is a type mismatch flutter
      // analyze correctly fails the build on.
      LogService.error(details.exceptionAsString(), source: 'FlutterError', stack: details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      LogService.error('Uncaught platform error', source: 'PlatformDispatcher', error: error, stack: stack);
      return true; // tells Flutter this was handled, not that it's being ignored
    };

    // ProviderScope must wrap everything, including the MaterialApp itself -
    // it's what makes ref.watch()/ref.read() work anywhere below it.
    runApp(const ProviderScope(child: CatholicSAApp()));
  }, (error, stack) {
    LogService.error('Uncaught zone error', source: 'runZonedGuarded', error: error, stack: stack);
  });
}
