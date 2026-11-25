/// Which Firebase project this build talks to.
///
/// Chosen at build time, never at runtime, so a production build can
/// never accidentally point at dev data (or the other way round):
///
///   flutter run                                  -> production (default)
///   flutter run --dart-define=APP_ENV=staging    -> catholicsa-dev
///   flutter build web --dart-define=APP_ENV=staging
///
/// `.github/workflows/deploy.yml` passes `APP_ENV=staging` when building
/// from the `develop` branch, and nothing (i.e. production) from `main`.
library;

enum AppEnvironment { production, staging }

const String _appEnvRaw = String.fromEnvironment('APP_ENV', defaultValue: 'production');

/// The environment this build was compiled for. Anything other than
/// `staging`/`dev` falls back to production, matching the pre-existing
/// behaviour of every build made before this switch existed.
const AppEnvironment appEnvironment =
    (_appEnvRaw == 'staging' || _appEnvRaw == 'dev') ? AppEnvironment.staging : AppEnvironment.production;

const bool isStaging = appEnvironment == AppEnvironment.staging;
