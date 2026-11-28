import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import '../services/log_service.dart';
import '../theme/app_theme.dart';

/// The project owner's "Logs" page - same spot AuditLogSection already
/// has in super_admin_panel_screen.dart, but for real crashes/errors
/// (LogService) rather than admin actions (AuditLogService). Reached from
/// the Super Admin hub, same AdminSectionHost wrapper every other section
/// there uses.
class LogsSection extends StatefulWidget {
  const LogsSection({super.key});

  @override
  State<LogsSection> createState() => _LogsSectionState();
}

class _LogsSectionState extends State<LogsSection> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _future = LogService.getRecentLogs();
  }

  void _refresh() => setState(() => _future = LogService.getRecentLogs());

  Future<void> _clearAll() async {
    setState(() => _clearing = true);
    try {
      await LogService.clearAll();
      _refresh();
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _levelColor(String? level) {
    switch (level) {
      case 'error':
        return Colors.redAccent;
      case 'warning':
        return Colors.orange;
      default:
        return AppColors.sage;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Every crash and error the app itself caught - signed in or not, newest first. Nothing here means nothing's failed since it was last cleared.",
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
              onPressed: _clearing ? null : _clearAll,
              icon: _clearing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear all'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Text('Could not load logs: ${snap.error}', style: const TextStyle(fontSize: 12, color: Colors.redAccent));
            }
            final logs = snap.data ?? [];
            if (logs.isEmpty) {
              return const Text(
                "No errors logged. Either everything's working, or nothing's been tried yet.",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              );
            }
            return Column(
              children: logs.map((l) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.paperDark, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(Icons.circle, size: 8, color: _levelColor(l['level'] as String?)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l['message'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          if ((l['source'] as String?)?.isNotEmpty == true)
                            Text(l['source'], style: const TextStyle(fontSize: 11, color: Colors.black54)),
                          if ((l['userEmail'] as String?)?.isNotEmpty == true)
                            Text('by ${l['userEmail']}', style: const TextStyle(fontSize: 10, color: Colors.black38)),
                        ],
                      ),
                    ),
                    Text(_timeAgo(l['timestamp'] as Timestamp?), style: const TextStyle(fontSize: 10, color: Colors.black38)),
                  ],
                ),
              )).toList(),
            );
          },
        ),
      ],
    );
  }
}
