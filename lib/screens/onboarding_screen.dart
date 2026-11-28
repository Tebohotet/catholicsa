// RETIRED 2026-11-28 - no longer used anywhere in the app.
//
// This 4-slide carousel used to show on every visitor's first visit,
// reached via app.dart's old '/onboarding' route. The project owner
// found new visitors were still seeing it, and that it never actually
// pointed at the real Map/Browse/Readings/Hymns tabs it was describing -
// his own words: "why am I still seeing this when we have replaced it
// with the small ones, and why are they not pointing to map, browse,
// readings and hymns." His call, verbatim: "Remove this carousel
// entirely." app.dart's '/' route now goes straight to '/map' with no
// onboarding check at all, and first_run_tips.dart's small coach-mark
// overlay (already on Map, now also added to Browse/Readings/Hymns) is
// the only "here's what this does" guidance left.
//
// Left in place rather than deleted, in case any of this slide content
// or layout is wanted again later - nothing in the app imports or
// builds it anymore, so it has no effect either way.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(icon: Icons.church, title: 'Find Your Parish', body: 'Mass times, confessions, and everything happening at churches across South Africa - browse by province, diocese, parish, or church.'),
    _Slide(icon: Icons.menu_book, title: 'Daily Readings', body: 'Today\'s readings and the liturgical calendar, worked out entirely on your device - available even with no signal.'),
    _Slide(icon: Icons.school, title: 'Courses & Learning', body: 'RCIA, Baptism prep, and more - enrol, work through lessons, and leave a review once you\'ve completed one.'),
    _Slide(icon: Icons.storefront, title: 'Marketplace & Donations', body: 'Buy and sell within your parish community, or donate directly to a cause you care about.'),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    // Real route now (go_router), not a pushed widget - '/map' is the
    // default bottom-nav tab, same as HomeScreen's own default index 0
    // before this.
    if (mounted) context.go('/map');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(onPressed: _finish, child: const Text('Skip', style: TextStyle(color: AppColors.stone))),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(s.icon, size: 72, color: AppColors.brass),
                        const SizedBox(height: 24),
                        Text(s.title, style: const TextStyle(fontFamily: appSerif, fontSize: 24), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text(s.body, style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.4), textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 8, height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? AppColors.brass : Colors.black12),
                  )),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                  onPressed: _page == _slides.length - 1
                      ? _finish
                      : () => _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  child: Text(_page == _slides.length - 1 ? 'Get Started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final IconData icon;
  final String title;
  final String body;
  const _Slide({required this.icon, required this.title, required this.body});
}
