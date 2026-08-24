import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:intl/intl.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_section.dart';
import '../../widgets/share_button.dart';


Future<List<Map<String, dynamic>>> _mergedNoticesAndEvents(String parishId, String churchId) async {
  final service = FirestoreService();
  final notices = await service.getNotices(parishId, churchId);
  final events = await service.getEvents(parishId, churchId);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final merged = notices.map((n) => {
        'title': n['title'],
        'body': n['body'],
        'isEvent': false,
      }).toList();

  for (final e in events) {
    if (e['showInNotices'] != true) continue;
    final date = (e['date'] as Timestamp?)?.toDate();
    if (date == null || date.isBefore(today)) continue; // expired - don't show
    merged.add({
      'title': e['title'],
      'body': '${DateFormat('d MMM').format(date)}${e['time'] != null ? ' · ${e['time']}' : ''} — ${e['description'] ?? ''}',
      'isEvent': true,
    });
  }
  return merged;
}

class NoticesSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const NoticesSection({super.key, required this.parishId, required this.churchId});

  @override
  State<NoticesSection> createState() => _NoticesSectionState();
}

class _NoticesSectionState extends State<NoticesSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.stone),
              const SizedBox(width: 6),
              Text(_expanded ? 'Hide notices' : 'Tap to view notices & policies', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _mergedNoticesAndEvents(widget.parishId, widget.churchId),
            builder: (context, snap) {
              if (snap.hasError) return Text('Error: ${snap.error}');
              if (!snap.hasData) return const LinearProgressIndicator();
              final notices = snap.data!;
              if (notices.isEmpty) {
                return const Text('No notices posted right now.', style: TextStyle(fontSize: 12, color: Colors.black45));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: notices.map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              if (n['isEvent'] == true) ...[const SizedBox(width: 6), const Pill('Event', tone: 'outline')],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(n['body'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                        ],
                      ),
                    )).toList(),
              );
            },
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _showSafeguardingPolicy(context, widget.parishId),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, size: 15, color: AppColors.sage),
                SizedBox(width: 6),
                Text('Safeguarding Policy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.sage, decoration: TextDecoration.underline)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

void _showSafeguardingPolicy(BuildContext context, String parishId) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('Safeguarding Policy', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: SizedBox(
        width: 400,
        child: AsyncSection<String?>(
          future: FirestoreService().getSafeguardingPolicy(parishId),
          builder: (context, body) => SingleChildScrollView(
            child: Text(body ?? 'Not published yet.', style: const TextStyle(fontSize: 13)),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
    ),
  );
}

/// Quick-access shortcut + unread indicator for Parochial Notices, living
/// next to the other quick actions rather than on the banner itself (which
/// is already a tightly laid-out area with the logo, back button, and
/// parish tag). "Seen" is tracked for this session only - a proper
/// per-user read receipt would need either local persistent storage or a
/// signed-in-user record, neither of which exist yet.
class NoticesBellButton extends StatefulWidget {
  final String parishId;
  final String churchId;
  const NoticesBellButton({super.key, required this.parishId, required this.churchId});

  @override
  State<NoticesBellButton> createState() => _NoticesBellButtonState();
}

class _NoticesBellButtonState extends State<NoticesBellButton> {
  List<Map<String, dynamic>>? _notices;
  bool _seen = false;

  @override
  void initState() {
    super.initState();
    _mergedNoticesAndEvents(widget.parishId, widget.churchId).then((n) {
      if (mounted) setState(() => _notices = n);
    });
  }

  void _open(BuildContext context) {
    setState(() => _seen = true);
    showDialog(
      context: context,
      builder: (dialogContext) => _NoticesPopup(notices: _notices ?? [], onClose: () => Navigator.pop(dialogContext)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _notices?.length ?? 0;
    final showBadge = !_seen && count > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Parochial notices',
          icon: const Icon(Icons.campaign_outlined, size: 20, color: AppColors.ink),
          onPressed: () => _open(context),
        ),
        if (showBadge)
          Positioned(
            right: 6, top: 6,
            child: Container(
              padding: const EdgeInsets.all(3),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
              child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}

class _NoticesPopup extends StatelessWidget {
  final List<Map<String, dynamic>> notices;
  final VoidCallback onClose;
  const _NoticesPopup({required this.notices, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.paper,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Parochial Notice', style: TextStyle(fontFamily: appSerif, fontSize: 18))),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClose),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: notices.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No notices posted right now.', style: TextStyle(fontSize: 12, color: Colors.black45)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: notices.length,
                        itemBuilder: (context, i) {
                          final n = notices[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(child: Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                          if (n['isEvent'] == true) ...[const SizedBox(width: 6), const Pill('Event', tone: 'outline')],
                                        ],
                                      ),
                                    ),
                                    ShareButton(
                                      title: n['title'] ?? '',
                                      body: n['body'] ?? '',
                                      iconSize: 15,
                                      iconColor: AppColors.stone,
                                    ),
                                  ],
                                ),
                                Text(n['body'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Song 245? What is that?" - type the number the priest/song leader
/// just announced, get the title back instantly instead of flipping
/// through a hymnal blind. Lyrics only show if the parish has entered
/// them (and presumably has the rights to).
