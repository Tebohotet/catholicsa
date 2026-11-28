import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// One step of a first-run guided tour: a real widget on screen (via its
/// own GlobalKey) plus the short message explaining what it does.
class TipStep {
  final GlobalKey targetKey;
  final String title;
  final String message;
  const TipStep({required this.targetKey, required this.title, required this.message});
}

/// A minimal, pure-Flutter "look here" coach-mark overlay - the project
/// owner's own ask: "I need it to be those small message box showing you
/// where a certain feature is at on the site, a tooltip, onboarding tour
/// ... But for only things we have at the moment." No new package added
/// (this session already hit one real pub dependency conflict earlier -
/// see PROJECT_STATUS.md's pdfviewer/xml note - so a hand-rolled overlay
/// using only what's already in pubspec.yaml is the safer choice here).
///
/// Shows once per device (SharedPreferences-gated by [prefsKey]) the
/// first time this is called for that key, walking through [steps] one
/// at a time: a dark scrim, a highlighted box drawn around the real
/// widget at that step's [TipStep.targetKey], and a small message card
/// near it with Next/Skip. If a step's target isn't actually on screen
/// when its turn comes (e.g. "Use my location" already hid itself
/// because permission was already granted before the tour got there),
/// that step is skipped rather than crashing or drawing a highlight
/// around nothing.
Future<void> showFirstRunTips(BuildContext context, {required String prefsKey, required List<TipStep> steps}) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(prefsKey) ?? false) return;
  if (!context.mounted) return;
  await _TourRunner(context: context, prefsKey: prefsKey, steps: steps).start();
}

class _TourRunner {
  final BuildContext context;
  final String prefsKey;
  final List<TipStep> steps;
  OverlayEntry? _entry;
  int _index = 0;

  _TourRunner({required this.context, required this.prefsKey, required this.steps});

  Future<void> start() async {
    _showStep();
  }

  Rect? _targetRect(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    final overlayBox = Overlay.of(context).context.findRenderObject();
    if (overlayBox is! RenderBox) return null;
    final topLeft = renderObject.localToGlobal(Offset.zero, ancestor: overlayBox);
    return topLeft & renderObject.size;
  }

  void _showStep() {
    if (_index >= steps.length) {
      _finish();
      return;
    }
    final step = steps[_index];
    final rect = _targetRect(step.targetKey);
    if (rect == null) {
      // Target not actually on screen right now - skip it rather than
      // draw a spotlight around nothing.
      _index++;
      _showStep();
      return;
    }
    _entry?.remove();
    final screenSize = MediaQuery.of(context).size;
    final below = rect.bottom + 120 < screenSize.height;
    _entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // Dimmed backdrop - tapping it just advances, same as Next.
          Positioned.fill(
            child: GestureDetector(
              onTap: _next,
              child: Container(color: Colors.black54),
            ),
          ),
          // The actual highlighted box around the real widget, inset
          // slightly so the border doesn't sit flush on top of it.
          Positioned(
            left: rect.left - 4,
            top: rect.top - 4,
            width: rect.width + 8,
            height: rect.height + 8,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.brass, width: 2.5),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          // Project owner's own ask: "does it have to be that big?" - kept
          // as a small bubble near the button (capped width, tighter
          // padding/type) rather than a banner stretching edge to edge.
          Positioned(
            left: 16,
            right: 16,
            top: below ? rect.bottom + 10 : null,
            bottom: below ? null : (screenSize.height - rect.top + 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Material(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(10),
                  elevation: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(step.title, style: const TextStyle(fontFamily: appSerif, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(step.message, style: const TextStyle(fontSize: 11.5)),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 30)),
                              onPressed: _finish,
                              child: const Text('Skip', style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 2),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.brass, padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 30)),
                              onPressed: _next,
                              child: Text(_index == steps.length - 1 ? 'Got it' : 'Next', style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _next() {
    _index++;
    _showStep();
  }

  void _finish() {
    _entry?.remove();
    _entry = null;
    SharedPreferences.getInstance().then((p) => p.setBool(prefsKey, true));
  }
}
