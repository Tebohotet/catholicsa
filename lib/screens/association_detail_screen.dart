import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';

/// Reachable by tapping an association anywhere it's listed. Shows its
/// own events/notices merged with every parish-wide one - a parish-wide
/// item (associationId null) is meant to be "seen by every association",
/// so it cascades down to appear here too, not just in the main Events
/// tab.
class AssociationDetailScreen extends StatefulWidget {
  final String parishId;
  final Map<String, dynamic> association;
  const AssociationDetailScreen({super.key, required this.parishId, required this.association});

  @override
  State<AssociationDetailScreen> createState() => _AssociationDetailScreenState();
}

class _AssociationDetailScreenState extends State<AssociationDetailScreen> {
  late Future<List<Map<String, dynamic>>> _eventsFuture;
  late Future<List<Map<String, dynamic>>> _noticesFuture;

  @override
  void initState() {
    super.initState();
    final id = widget.association['id'];
    _eventsFuture = FirestoreService().getEventsForAssociation(widget.parishId, id);
    _noticesFuture = FirestoreService().getNoticesForAssociation(widget.parishId, id);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.association;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: AppColors.stone,
              padding: const EdgeInsets.fromLTRB(4, 12, 16, 20),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  Expanded(child: Text(a['name'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 20, color: Colors.white))),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (a['purpose'] != null) Text(a['purpose'], style: const TextStyle(fontSize: 13)),
                  if (a['meetingDay'] != null || a['meetingTime'] != null || a['contactPerson'] != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: AppColors.paperDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (a['meetingDay'] != null || a['meetingTime'] != null)
                            Text('Meets: ${[a['meetingDay'], a['meetingTime']].where((e) => e != null).join(' at ')}', style: const TextStyle(fontSize: 12)),
                          if (a['contactPerson'] != null)
                            Text('Contact: ${a['contactPerson']}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text('Events', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
                  const SizedBox(height: 8),
                  AsyncSection<List<Map<String, dynamic>>>(
                    future: _eventsFuture,
                    isEmpty: (l) => l.isEmpty,
                    emptyMessage: 'No upcoming events.',
                    builder: (context, events) => Column(
                      children: events.map((e) {
                        final date = (e['date'] as dynamic)?.toDate();
                        final isOwn = e['associationId'] == a['id'];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          color: AppColors.paperDark,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(e['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                if (!isOwn) const Pill('Parish-wide', tone: 'outline'),
                              ]),
                              if (date != null) Text('${DateFormat('EEE, d MMM').format(date)} \u00b7 ${e['time'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Notices', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
                  const SizedBox(height: 8),
                  AsyncSection<List<Map<String, dynamic>>>(
                    future: _noticesFuture,
                    isEmpty: (l) => l.isEmpty,
                    emptyMessage: 'No notices.',
                    builder: (context, notices) => Column(
                      children: notices.map((n) {
                        final isOwn = n['associationId'] == a['id'];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          color: AppColors.paperDark,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                if (!isOwn) const Pill('Parish-wide', tone: 'outline'),
                              ]),
                              const SizedBox(height: 2),
                              Text(n['body'] ?? '', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}