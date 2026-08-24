/// OAuth 2.0 "Desktop app" client credentials for Google Sign-In on Windows.
///
/// Google Sign-In (the `google_sign_in` package used everywhere else in
/// this app) has no Windows implementation at all - confirmed directly
/// from the Flutter team, not fixable via config. The Windows build uses
/// `google_sign_in_all_platforms` instead (see AuthService.
/// signInWithGoogleWindows), which needs its OWN OAuth client. The
/// existing Web/Android/iOS client IDs already used elsewhere in this
/// project will NOT work for this - a fresh "Desktop app" client is
/// required.
///
/// ---------------------------------------------------------------------
/// ONE-TIME SETUP (do this once, in Google Cloud Console):
/// ---------------------------------------------------------------------
/// 1. Go to https://console.cloud.google.com/apis/credentials and make
///    sure the project selected top-left is `catholicsa-61b87` - the
///    SAME project as Firebase. This matters: Firebase's Google
///    sign-in provider only accepts tokens issued to OAuth clients that
///    live in this project.
/// 2. Click "+ CREATE CREDENTIALS" -> "OAuth client ID".
/// 3. Application type: "Desktop app". Name it e.g. "CatholicSA Windows".
/// 4. Click into the newly created client and add this to
///    "Authorized redirect URIs":
///        http://localhost:8000
///    (8000 matches `redirectPort` below - the package defaults to it.
///    If you ever change one, change both.)
/// 5. Copy the "Client ID" and "Client secret" it shows you and paste
///    them in below, replacing the placeholders.
///
///    Note on the secret: for a Desktop-type OAuth client, Google's own
///    docs say this secret is not treated as confidential - it's baked
///    into installed apps by design, and security comes from the
///    loopback redirect + PKCE, not from keeping it hidden. Since this
///    Windows build also isn't distributed to end users (admin/internal
///    use only, per earlier discussion), there's no real exposure
///    either way.
/// 6. Test it: run the Windows build, hit "Sign in with Google". If it
///    fails with something like `auth/invalid-credential` or
///    `admin-restricted-operation`, double check step 1 - a client ID
///    from a different GCP project is the most likely cause.
/// ---------------------------------------------------------------------
class GoogleDesktopOAuthConfig {
  static const String clientId = 'PASTE_YOUR_DESKTOP_CLIENT_ID_HERE';
  static const String clientSecret = 'PASTE_YOUR_DESKTOP_CLIENT_SECRET_HERE';
  static const int redirectPort = 8000;

  /// True once the placeholders above have actually been filled in.
  /// Checked before attempting sign-in so a forgotten setup step fails
  /// with a clear message instead of a confusing OAuth error.
  static bool get isConfigured =>
      !clientId.startsWith('PASTE_') && !clientSecret.startsWith('PASTE_');
}
