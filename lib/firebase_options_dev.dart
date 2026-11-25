// PLACEHOLDER - NOT YET GENERATED. (CI's staging build checks for the word
// on the line above and refuses to build/deploy until it's gone.)
//
// Firebase client config for the `catholicsa-dev` (staging) project. Used
// only by builds made with `--dart-define=APP_ENV=staging` - see
// lib/config/app_environment.dart. Production builds never touch this file.
//
// To fill it in, from the repo root on a machine logged in to Firebase
// (`firebase login`) with access to catholicsa-dev:
//
//   flutterfire configure --project=catholicsa-dev --out=lib/firebase_options_dev.dart
//
// That overwrites this whole file with the real generated one (same class
// name, `DefaultFirebaseOptions`, which is why main.dart imports it with a
// `dev.` prefix). The values it writes are public client identifiers, not
// secrets - same as lib/firebase_options.dart - so it's fine to commit.
//
// NOTE: do NOT let it overwrite android/app/google-services.json or the iOS
// plist with the dev project's - answer "no" if flutterfire asks, or move
// them back afterwards. Those still belong to production.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Staging build, but lib/firebase_options_dev.dart has not been generated yet. '
      'Run: flutterfire configure --project=catholicsa-dev --out=lib/firebase_options_dev.dart',
    );
  }
}
