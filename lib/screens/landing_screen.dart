import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The app's first screen, shown on every cold start ahead of onboarding
/// and the home screen - deliberately *not* a one-time "seen it" flag
/// like onboarding has, since the project owner wants this to keep
/// showing while church data is still incomplete.
///
/// The wording is the project owner's own (their original project brief,
/// already adapted once into README.md's "The vision" section), with the
/// developer-facing built/not-built annotations trimmed for end users.
/// Keep the two in sync if either changes.
class LandingScreen extends StatelessWidget {
  /// What to do once the user taps "Continue" - checking onboarding
  /// state and going to the right next route is app.dart's job now (via
  /// go_router), not this screen's - kept as a plain callback so this
  /// screen still doesn't need to know about onboarding or routing at
  /// all. Was a WidgetBuilder before real routing existed; a VoidCallback
  /// is all that's needed now that "next" means "go to a URL", not
  /// "build a widget".
  final VoidCallback onContinue;

  const LandingScreen({super.key, required this.onContinue});

  static const intro =
      'Started as a simple question: on a Sunday, if you\'ve missed Mass at '
      'your usual church, can you find the nearest one and actually make it '
      'in time? From there it grew into a fuller directory and toolkit for '
      'parishes - inspired partly by the Archdiocese of Cape Town\'s own '
      'site, aiming to do that, modernised, for every parish in the country, '
      'and eventually beyond.';

  static const features = [
    'Find a church near you, and know if you\'ll make it in time',
    'Mass times, confession times, readings in different languages, suggested hymns, prayers',
    'A shop, in case a parish wants to sell something',
    'Priest and clergy info per church, editable by the parish\'s own admin, not just a developer',
    'Other associations/ministries in a church, with a way to support them',
    'A map of active churches, with more detail on tap',
    'Comments and ratings per church',
    'Social media links per church',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Center(child: Icon(Icons.church, size: 64, color: AppColors.brass)),
                        const SizedBox(height: 16),
                        const Center(
                          child: Text('CatholicSA',
                              style: TextStyle(fontFamily: appSerif, fontSize: 30, color: AppColors.stoneDark)),
                        ),
                        const SizedBox(height: 28),
                        const Text('About Us',
                            style: TextStyle(fontFamily: appSerif, fontSize: 22, color: AppColors.stoneDark)),
                        const SizedBox(height: 12),
                        const Text(intro, style: TextStyle(fontSize: 15, color: AppColors.ink, height: 1.5)),
                        const SizedBox(height: 20),
                        const Text('What that means in practice:',
                            style: TextStyle(fontSize: 15, color: AppColors.ink, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        for (final f in features)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 3, right: 10),
                                  child: Icon(Icons.check_circle_outline, size: 16, color: AppColors.brass),
                                ),
                                Expanded(
                                  child: Text(f, style: const TextStyle(fontSize: 14, color: AppColors.ink, height: 1.4)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                    onPressed: onContinue,
                    child: const Text('Continue'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
