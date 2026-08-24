import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
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

/// Decides once, on cold start, whether this device has seen onboarding
/// before - checked locally (not tied to a signed-in account) since
/// onboarding should show before anyone's necessarily signed in at all.
class _RootDecider extends StatelessWidget {
  const _RootDecider();

  Future<bool> _hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_seen') ?? false;
  }

  @override
  Widget build(BuildContext context) {
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