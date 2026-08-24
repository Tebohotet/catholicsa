import 'package:flutter/material.dart';

/// Design tokens matching the original St Jude prototype - reused across
/// every screen so the app has one consistent visual language instead of
/// generic Material defaults.
class AppColors {
  static const ink = Color(0xFF26241F);
  static const paper = Color(0xFFE9E2D0);
  static const paperDark = Color(0xFFDDD3BA);
  static const stone = Color(0xFF324054);
  static const stoneDark = Color(0xFF232C3A);
  static const brass = Color(0xFFA9822F);
  static const sage = Color(0xFF4C7A5E);
}

const appSerif = 'Times New Roman';

/// The same centered, max-width content wrapper used on the church detail
/// page - one definition, reused on every screen.
class CenteredContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const CenteredContent({super.key, required this.child, this.maxWidth = 960});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// "I. Section Title ─────" - the roman-numeral section header style
/// used throughout the prototype.
class SectionLabel extends StatelessWidget {
  final String numeral;
  final String title;
  const SectionLabel({super.key, required this.numeral, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(numeral, style: const TextStyle(color: AppColors.brass, fontStyle: FontStyle.italic, fontFamily: appSerif, fontSize: 14)),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontFamily: appSerif, fontSize: 22, color: AppColors.stoneDark)),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: AppColors.ink.withValues(alpha: 0.13))),
        ],
      ),
    );
  }
}

/// Small uppercase tag - "Mass", "Live", "Communion Service", etc.
class Pill extends StatelessWidget {
  final String text;
  final String tone; // 'brass' | 'sage' | 'outline'
  const Pill(this.text, {super.key, this.tone = 'brass'});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    BoxBorder? border;
    switch (tone) {
      case 'sage':
        bg = AppColors.sage;
        fg = Colors.white;
        break;
      case 'outline':
        bg = Colors.transparent;
        fg = AppColors.ink;
        border = Border.all(color: AppColors.ink.withValues(alpha: 0.35));
        break;
      default:
        bg = AppColors.brass;
        fg = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, border: border, borderRadius: BorderRadius.circular(3)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
    );
  }
}

/// The gradient placeholder banner used for a church/parish that has no
/// uploaded photo yet - stone-to-dark gradient with a faint icon watermark.
class BannerPlaceholder extends StatelessWidget {
  final double height;
  final IconData icon;
  const BannerPlaceholder({super.key, this.height = 140, this.icon = Icons.church});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppColors.stone, AppColors.stoneDark],
        ),
      ),
      child: Center(child: Icon(icon, size: height * 0.3, color: Colors.white.withValues(alpha: 0.2))),
    );
  }
}
