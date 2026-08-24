import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
// Aliased - google_sign_in_all_platforms exports its own GoogleSignIn /
// GoogleSignInParams classes that would otherwise collide with the
// mobile/web package above. Only ever used on Windows (see
// signInWithGoogleWindows) - everywhere else keeps using google_sign_in.
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart'
    as gsi_desktop;
import '../config/google_desktop_oauth_config.dart';
import 'notification_service.dart';
import 'engagement_service.dart';

/// Handles Google Sign-In and makes sure a corresponding /users/{uid}
/// document exists in Firestore (created on first login only).
///
/// Singleton, deliberately - AuthService() is called from dozens of
/// places throughout the app, and without this, each call constructed
/// its own GoogleSignIn instance. On web, that re-triggers Google's
/// underlying JS SDK initialization every time (visible in the browser
/// console as "google.accounts.id.initialize() is called multiple
/// times... only the last initialized instance will be used" - a real
/// warning about real behavior, not just noise). This fixes it without
/// touching any of the existing call sites, since AuthService() still
/// works exactly as written everywhere - it just now always returns the
/// same instance.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  // Lazily constructed - only ever touched from signInWithGoogleWindows,
  // but built once and reused so repeat sign-ins on Windows can benefit
  // from the package's own lightweight/stored-token reuse in signIn(),
  // the same way _googleSignIn above is a single shared instance rather
  // than one built fresh per call.
  gsi_desktop.GoogleSignIn? _desktopGoogleSignIn;
  gsi_desktop.GoogleSignIn get _windowsGoogleSignIn =>
      _desktopGoogleSignIn ??= gsi_desktop.GoogleSignIn(
        params: gsi_desktop.GoogleSignInParams(
          clientId: GoogleDesktopOAuthConfig.clientId,
          clientSecret: GoogleDesktopOAuthConfig.clientSecret,
          redirectPort: GoogleDesktopOAuthConfig.redirectPort,
          scopes: const ['openid', 'email', 'profile'],
        ),
      );

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user != null) {
      await _ensureUserDoc(user);
      // Fire-and-forget - a denied permission or a failed token fetch
      // shouldn't ever block sign-in itself.
      NotificationService().requestPermissionAndSaveToken();
      // Same reasoning - a gamification write failing should never
      // block or slow down sign-in.
      EngagementService().recordActivity('login');
    }
    return user;
  }

  /// Real Google Sign-In on Windows, via google_sign_in_all_platforms
  /// instead of the google_sign_in package used everywhere else (which
  /// has no Windows implementation at all). Deliberately mirrors
  /// signInWithGoogle()'s structure - same _ensureUserDoc call, same
  /// fire-and-forget notification/engagement calls - so a Windows user
  /// ends up in exactly the same state as anyone signing in with Google
  /// on mobile/web.
  ///
  /// Requires a one-time Google Cloud Console setup - see
  /// lib/config/google_desktop_oauth_config.dart. Throws a clear
  /// StateError if that hasn't been done yet, rather than letting the
  /// package fail with an opaque OAuth error.
  Future<User?> signInWithGoogleWindows() async {
    if (!GoogleDesktopOAuthConfig.isConfigured) {
      throw StateError(
        'Google Sign-In for Windows is not set up yet - fill in the '
        'client ID/secret in lib/config/google_desktop_oauth_config.dart '
        '(see the setup instructions at the top of that file).',
      );
    }

    final googleCredentials = await _windowsGoogleSignIn.signIn();
    if (googleCredentials == null) return null; // user cancelled, or timed out

    final credential = GoogleAuthProvider.credential(
      accessToken: googleCredentials.accessToken,
      idToken: googleCredentials.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user != null) {
      await _ensureUserDoc(user);
      NotificationService().requestPermissionAndSaveToken();
      EngagementService().recordActivity('login');
    }
    return user;
  }

  /// Windows-only path (Google Sign-In has no Windows implementation,
  /// confirmed directly from the Flutter team) - deliberately mirrors
  /// signInWithGoogle()'s own structure exactly, reusing the same
  /// _ensureUserDoc call rather than duplicating that logic. This is
  /// the actual fix for a real bug found from a real screenshot: email
  /// sign-in was previously called directly against FirebaseAuth from
  /// the UI layer, bypassing this service entirely, so no /users/{uid}
  /// document was ever created and every Firestore read requiring one
  /// failed with permission-denied.
  ///
  /// Now that signInWithGoogleWindows() above exists, this is no longer
  /// Windows' only sign-in option - it's still offered as an
  /// alternative (same as on mobile/web) since it comes with its own
  /// "Forgot password?" flow already built.
  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    final userCredential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = userCredential.user;
    if (user != null) {
      await _ensureUserDoc(user);
      NotificationService().requestPermissionAndSaveToken();
      EngagementService().recordActivity('login');
    }
    return user;
  }

  Future<void> _ensureUserDoc(User user) async {
    final ref = _db.collection('users').doc(user.uid);
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      await ref.set({
        'email': user.email,
        'displayName': user.displayName,
        'photoUrl': user.photoURL,
        'isSuperAdmin': false,
        'createdAt': FieldValue.serverTimestamp(),
        'preferences': {
          'language': 'en',
          'notifications': {
            'massReminders': true, 'eventReminders': true,
            'newsletterEmail': false, 'pushEnabled': true,
          },
          'autoDetectNearestChurch': true,
          'privacy': {'profileVisible': true, 'showAttendanceHistory': false},
        },
      });
    }
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await NotificationService().removeTokenOnSignOut(uid);
      } catch (_) {
        // Not fatal to signing out - a failed token cleanup shouldn't
        // leave someone unable to sign out of their own account.
      }
    }
    // Isolated deliberately - the Google SDK's own signOut is secondary
    // to the actual Firebase Auth signOut below, which is what the rest
    // of the app actually reacts to. A failure here (real and known -
    // see the "initialize() called multiple times" GSI warning) must
    // never block the real sign-out from happening.
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    // Only bother if the Windows path was ever actually used this
    // session - _desktopGoogleSignIn stays null otherwise, and
    // constructing it here for nothing would need real (possibly still
    // unconfigured) client credentials for no reason.
    if (_desktopGoogleSignIn != null) {
      try {
        await _desktopGoogleSignIn!.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }

  /// Returns true if the current user is listed as an admin for [parishId].
  /// Used client-side to decide whether to show edit/reply controls
  /// (Firestore rules enforce this server-side regardless).
  Future<bool> isAdminForParish(String parishId) async {
    final uid = currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db
        .collection('parishes')
        .doc(parishId)
        .collection('admins')
        .doc(uid)
        .get();
    return doc.exists;
  }

  /// Returns the admin doc (role, verified status) for the current user
  /// at a given parish, or null if they aren't an admin there.
  Future<Map<String, dynamic>?> getAdminProfile(String parishId) async {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    final doc = await _db
        .collection('parishes')
        .doc(parishId)
        .collection('admins')
        .doc(uid)
        .get();
    return doc.data();
  }
}