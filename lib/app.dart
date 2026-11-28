import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/home_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/map_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/readings_screen.dart';
import 'screens/hymns_screen.dart';
import 'screens/church_detail_screen.dart';
import 'screens/parish_detail_screen.dart';
import 'screens/pdf_viewer_screen.dart';
import 'providers/design_tokens_provider.dart';
import 'providers/branding_provider.dart';
import 'widgets/developer_debug_overlay.dart';

/// Lets NotificationService show a SnackBar for a foreground push message
/// from anywhere, without needing a BuildContext from whichever tab happens
/// to be active - the alternative (reaching into the current tab's nested
/// Navigator) is exactly the kind of fragile context-chasing worth avoiding.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Lets a screen (Readings, Hymns, Map) detect when it's been navigated
/// back to - e.g. after an admin ran a sync or edit on a different screen
/// and popped back - and refresh its own data automatically, instead of
/// staying stale until the whole app is manually reloaded. go_router
/// applies this same observer to every Navigator it builds (root and
/// every bottom-nav tab's own branch alike), so this keeps working
/// exactly as before now that those Navigators are built by
/// StatefulShellRoute instead of by hand.
final rootRouteObserver = RouteObserver<ModalRoute<void>>();

/// Real, URL-backed routing (go_router) - added 2026-11-28 to fix two
/// real problems the project owner hit and reported the same night:
/// a browser refresh always landing back on the About Us page no matter
/// how deep into the app you were ("no start over from about us"), and
/// losing which bottom-nav tab you were on across a refresh ("I need
/// refresh to keep in hymns"). Before this, the whole app was one
/// unnamed widget tree - `_RootDecider` -> `_OnboardingDecider` ->
/// `HomeScreen`'s own manually-built per-tab Navigators - with no URL at
/// all behind any of it, so a refresh had no way to know where you'd
/// been and always just started over from the very first screen.
///
/// **Phase 1, done this pass**: the 4 bottom-nav tabs (/map, /browse,
/// /readings, /hymns), the Hymns tab's built-in PDF viewer
/// (/hymns/pdf), and the existing church/parish share-links
/// (previously hand-parsed from Uri.base in this same file - see git
/// history) are all real go_router routes now. Refreshing on any of
/// these keeps you exactly there, not back at About Us.
///
/// **Phase 2, not done yet**: everything pushed *on top of* a tab or
/// the PDF viewer (church/parish detail reached by drilling into
/// Browse, Admin Panel, Account, Messages, and dozens more screens
/// throughout the app) still uses plain in-memory Navigator pushes, the
/// same as before this pass. Refreshing there now drops back to that
/// tab's own root (e.g. Browse) instead of all the way to About Us -
/// already a real improvement - but not back to the exact pushed screen
/// you were on. Converting those too means giving each one its own
/// go_router route, a much bigger job (genuinely "dozens of screens"),
/// left for its own future pass rather than risking a much larger,
/// riskier change in one go tonight.
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  observers: [rootRouteObserver, HomeNavObserver()],
  initialLocation: '/',
  routes: [
    // The app's first screen on a true cold start (or anyone who
    // bookmarks/refreshes bare "/" itself) - shown every time, not just
    // once, same deliberate choice as before this migration (church/
    // parish links below still skip it entirely, same priority as
    // before too).
    GoRoute(
      path: '/',
      // 2026-11-28: the 4-slide onboarding carousel (OnboardingScreen,
      // '/onboarding') is gone - the project owner's own call, after
      // finding new visitors still saw it and it never actually pointed
      // at the real Map/Browse/Readings/Hymns tabs ("why am I still
      // seeing this when we have replaced it with the small ones, and
      // why are they not pointing to map, browse, readings and hymns").
      // Every visitor now goes straight from About Us into the app; the
      // small first-run-tips coach-marks (first_run_tips.dart) - already
      // on Map, now also added to Browse/Readings/Hymns - are the only
      // "here's what this does" guidance left, each shown once on that
      // screen's own first visit instead of four slides shown up front
      // before anyone's even seen the app.
      builder: (context, state) => LandingScreen(onContinue: () => context.go('/map')),
    ),
    // A church link in the starting URL / from a QR code, e.g.
    // catholicsa.co.za/church/<parishId>/<churchId> - the exact shape
    // ShareButton and a church page's own QR code already generate, so
    // this path can't change without breaking links already printed or
    // shared. `parentNavigatorKey` is what makes that possible together
    // with keeping the bottom nav/mini-player visible underneath: the
    // URL itself stays a plain top-level path, but the actual screen is
    // pushed onto the Map tab's own Navigator (branch index 0) rather
    // than the app's root one - same place `_openInitialChurchLinkIfAny`
    // used to push it by hand before real routing existed.
    GoRoute(
      path: '/church/:parishId/:churchId',
      parentNavigatorKey: homeBranchNavigatorKeys[0],
      builder: (context, state) => ChurchDetailScreen(
        parishId: state.pathParameters['parishId']!,
        churchId: state.pathParameters['churchId']!,
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => HomeShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          navigatorKey: homeBranchNavigatorKeys[0],
          routes: [GoRoute(path: '/map', builder: (context, state) => const MapScreen())],
        ),
        StatefulShellBranch(
          navigatorKey: homeBranchNavigatorKeys[1],
          routes: [GoRoute(path: '/browse', builder: (context, state) => const BrowseScreen())],
        ),
        StatefulShellBranch(
          navigatorKey: homeBranchNavigatorKeys[2],
          routes: [GoRoute(path: '/readings', builder: (context, state) => const ReadingsScreen())],
        ),
        StatefulShellBranch(
          navigatorKey: homeBranchNavigatorKeys[3],
          routes: [
            GoRoute(
              path: '/hymns',
              builder: (context, state) => const HymnsScreen(),
              routes: [
                // The built-in PDF viewer, reached either from a hymn's
                // "Preview" button or the audio-player dialog's "View
                // PDF" button (see hymns_screen.dart) - url/title travel
                // as query parameters specifically so this URL survives
                // a refresh intact, which a route needing more than
                // plain strings in its path/query generally can't do as
                // cleanly.
                GoRoute(
                  path: 'pdf',
                  builder: (context, state) => PdfViewerScreen(
                    url: state.uri.queryParameters['url'] ?? '',
                    title: state.uri.queryParameters['title'] ?? '',
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    // A bare parish link, e.g. catholicsa.co.za/st-jude-parish - shown
    // standalone, with no bottom nav underneath, same as before this
    // migration (unlike the church link above, which deliberately nests
    // inside the Map tab instead - that was already the one difference
    // between the two kinds of link before real routing existed, not
    // something new here). Registered LAST deliberately: go_router tries
    // routes in list order and this single-segment wildcard would
    // otherwise swallow /map, /browse, /readings, /hymns, and /onboarding
    // before any of them got a chance to match.
    GoRoute(
      path: '/:parishSlug',
      builder: (context, state) => ParishDetailScreen(parishId: state.pathParameters['parishSlug']!),
    ),
  ],
);

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

    return MaterialApp.router(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      // routerConfig replaces home: - routing/navigation now flows
      // through appRouter (defined above, built once at module load, not
      // rebuilt on every CatholicSAApp rebuild - recreating the GoRouter
      // itself on every design-token/branding update would destroy all
      // navigation state, so it deliberately lives outside this build
      // method).
      routerConfig: appRouter,
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
    );
  }
}
