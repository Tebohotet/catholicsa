import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/parish_detail_screen.dart';
import 'screens/landing_screen.dart';
import 'providers/design_tokens_provider.dart';
import 'providers/branding_provider.dart';
import 'widgets/developer_debug_overlay.dart';

/// Lets NotificationService show a SnackBar for a foreground push message
/// from anywhere, without needing a BuildContext from whichever tab happens
/// to be active - the alternative (reaching into the current tab's nested
/// Navigator) is exactly the kind of fragile context-chasing worth avoiding.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Lets a screen (Readings, Hymns) detect when it's been navigated back
/// to - e.g. after an admin ran a sync or edit on a different screen
/// and popped back - and refresh its own data automatically, instead of
/// staying stale until the whole app is manually reloaded.
final rootRouteObserver = RouteObserver<ModalRoute<void>>();

/// A church link encoded in the page's starting URL on web - e.g.
/// `https://catholicsa.co.za/church/<parishId>/<churchId>`, the exact
/// shape `ShareButton` and the QR code on a church page already
/// generate. Parsed once, directly from the browser's address bar
/// (`Uri.base`), rather than through Flutter's own router - this app
/// has no named routes at all, so without this, a shared link or a
/// scanned QR code always opened the generic home screen instead of
/// the church it pointed at, no matter how correct the link itself
/// looked. `Uri.base` is meaningless on non-web (it reflects the
/// current working directory there), hence the `kIsWeb` guard.
(String parishId, String churchId)? _churchLinkFromCurrentUrl() {
  if (!kIsWeb) return null;
  final match = RegExp(r'^/church/([^/]+)/([^/]+)/?$').firstMatch(Uri.base.path);
  if (match == null) return null;
  return (match.group(1)!, match.group(2)!);
}

/// A parish-only link on web, e.g. `https://catholicsa.co.za/st-jude-parish`
/// - the "clean URL per parish" piece of the subdomain-per-parish idea,
/// minus the DNS/custom-domain part: this works today with no extra
/// Firebase or DNS setup, and a real subdomain can point at this same
/// path later without changing any app code. Bare top-level path (no
/// `/church/` prefix, which is handled separately above and always takes
/// priority), since that's the shape a parish would actually want to
/// share: `catholicsa.co.za/st-jude-parish`, not
/// `catholicsa.co.za/parish/st-jude-parish`. A parish's `slug` defaults
/// to its own Firestore document id (see `Parish.fromFirestore`), so the
/// id is what this matches against - exactly like the church link above.
String? _parishLinkFromCurrentUrl() {
  if (!kIsWeb) return null;
  final path = Uri.base.path;
  if (path == '/' || path.isEmpty) return null;
  final match = RegExp(r'^/([a-zA-Z0-9_-]+)/?$').firstMatch(path);
  if (match == null) return null;
  return match.group(1)!;
}

Color _parseHexColor(String hex, Color fallback) {
  try {
    final cleaned = hex.replaceAll('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  } catch (_) {
    return fallback;
  }
}

class CatholicSAApp extends ConsumerWidget {
  const CatholicSAApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokensAsync = ref.watch(designTokensProvider);
    final brandingAsync = ref.watch(brandingProvider);
    const defaultAccent = Color(0xFFA9822F); // brass
    const defaultStone = Color(0xFF324054);
    const defaultPaper = Color(0xFFE9E2D0);

    final accent = tokensAsync.maybeWhen(
      data: (t) => _parseHexColor(t['accentColor'] ?? '', defaultAccent),
      orElse: () => defaultAccent,
    );
    final cornerRadius = tokensAsync.maybeWhen(
      data: (t) => (t['cornerRadius'] as num?)?.toDouble() ?? 8.0,
      orElse: () => 8.0,
    );

    final appName = brandingAsync.maybeWhen(
      data: (b) => b['appName'] ?? 'CatholicSA',
      orElse: () => 'CatholicSA',
    );

    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [rootRouteObserver],
      title: appName,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => DeveloperDebugOverlay(child: child ?? const SizedBox.shrink()),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          primary: defaultStone,
          secondary: accent,
        ),
        scaffoldBackgroundColor: defaultPaper,
        useMaterial3: true,
        cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cornerRadius))),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cornerRadius))),
        ),
      ),
      home: const _RootDecider(),
    );
  }
}

/// The app's first screen on cold start. A church or parish link in the
/// starting URL goes straight there; otherwise the "About Us" landing
/// page shows - every time, not just once - followed by the onboarding
/// check.
class _RootDecider extends StatelessWidget {
  const _RootDecider();

  @override
  Widget build(BuildContext context) {
    // A church link in the starting URL takes priority over the landing
    // page and onboarding - someone who followed a shared link or scanned
    // a QR code wants that church, not an introduction or a first-run tour.
    final churchLink = _churchLinkFromCurrentUrl();
    if (churchLink != null) {
      return HomeScreen(initialChurchParishId: churchLink.$1, initialChurchId: churchLink.$2);
    }
    // A bare parish link (`/st-jude-parish`) opens that parish directly,
    // same priority as a church link above - someone who followed a
    // shared parish link wants that parish, not an introduction or the
    // Browse hierarchy's default landing spot.
    final parishLink = _parishLinkFromCurrentUrl();
    if (parishLink != null) {
      return ParishDetailScreen(parishId: parishLink);
    }
    return LandingScreen(next: (_) => const _OnboardingDecider());
  }
}

/// Decides whether this device has seen onboarding before - checked
/// locally (not tied to a signed-in account) since onboarding should show
/// before anyone's necessarily signed in at all.
class _OnboardingDecider extends StatelessWidget {
  const _OnboardingDecider();

  Future<bool> _hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_seen') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // Church/parish link handling now happens one step earlier, in
    // _RootDecider, ahead of the landing page - so by the time we're
    // here, neither applies and there's nothing left to check for them.
    return FutureBuilder<bool>(
      future: _hasSeenOnboarding(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(backgroundColor: Color(0xFFE9E2D0), body: Center(child: CircularProgressIndicator()));
        }
        return snap.data! ? const HomeScreen() : const OnboardingScreen();
      },
    );
  }
}
