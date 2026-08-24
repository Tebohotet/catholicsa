import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/engagement_service.dart';

/// Drop this anywhere something needs a share action - a church page, a
/// notice, a parish page, anything. One definition, reused everywhere, so
/// nothing gets redesigned or duplicated per screen.
///
/// For a page with a real link:
///   ShareButton(title: church.name, url: 'https://catholicsa.co.za/church/$parishId/$churchId')
///
/// For plain content with no page of its own (e.g. a notice):
///   ShareButton(title: notice.title, body: notice.body)
class ShareButton extends StatelessWidget {
  final String title;
  final String? body;
  final String? url;
  final double iconSize;
  final Color? iconColor;

  const ShareButton({
    super.key,
    required this.title,
    this.body,
    this.url,
    this.iconSize = 20,
    this.iconColor,
  });

  String get _shareText {
    final parts = [title];
    if (body != null && body!.isNotEmpty) parts.add(body!);
    if (url != null && url!.isNotEmpty) parts.add(url!);
    return parts.join('\n\n');
  }

  Future<void> _shareNative(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      _shareText,
      subject: title,
      sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
    EngagementService().recordActivity('share');
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _shareText));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    EngagementService().recordActivity('share');
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Share',
      icon: Icon(Icons.share_outlined, size: iconSize, color: iconColor ?? AppColors.ink),
      onSelected: (value) {
        if (value == 'share') _shareNative(context);
        if (value == 'copy') _copy(context);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'share', child: Row(children: [
          Icon(Icons.ios_share, size: 16), SizedBox(width: 10), Text('Share...'),
        ])),
        PopupMenuItem(value: 'copy', child: Row(children: [
          const Icon(Icons.link, size: 16), const SizedBox(width: 10), Text(url != null ? 'Copy link' : 'Copy text'),
        ])),
      ],
    );
  }
}