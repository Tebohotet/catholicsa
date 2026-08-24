import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import 'church_detail_screen.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: AppColors.stone,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: const Text('Events', style: TextStyle(fontFamily: appSerif, fontSize: 26, color: Colors.white)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CenteredContent(
                  child: AsyncSection<List<Map<String, dynamic>>>(
                  future: FirestoreService().getAllUpcomingEvents(),
                  isEmpty: (list) => list.isEmpty,
                  emptyMessage: 'No upcoming events right now.',
                  builder: (context, events) => ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final e = events[i];
                      final date = (e['date'] as Timestamp).toDate();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: AppColors.paperDark,
                        elevation: 0,
                        child: ListTile(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChurchDetailScreen(parishId: e['parishId'], churchId: e['churchId']),
                          )),
                          title: Text(e['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${DateFormat('EEEE, d MMM').format(date)}${e['time'] != null ? ' · ${e['time']}' : ''}${e['category'] != null ? ' · ${e['category']}' : ''}\n${e['churchName'] ?? ''}',
                          ),
                          isThreeLine: true,
                          trailing: _EventRsvpChip(parishId: e['parishId'], churchId: e['churchId'], eventId: e['id']),
                        ),
                      );
                    },
                  ),
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

/// Self-contained per-event RSVP - fetches its own attendance summary
/// and the church's seating capacity independently, rather than
/// widening the main events query for every tile whether someone
/// interacts with it or not.
class _EventRsvpChip extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String eventId;
  const _EventRsvpChip({required this.parishId, required this.churchId, required this.eventId});

  @override
  State<_EventRsvpChip> createState() => _EventRsvpChipState();
}

class _EventRsvpChipState extends State<_EventRsvpChip> {
  bool? _rsvped;
  Map<String, int>? _summary;
  int? _capacity;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = FirestoreService();
    final results = await Future.wait([
      service.isRsvpedToEvent(widget.parishId, widget.churchId, widget.eventId),
      service.getEventAttendanceSummary(widget.parishId, widget.churchId, widget.eventId),
      service.getChurch(widget.parishId, widget.churchId),
    ]);
    if (!mounted) return;
    setState(() {
      _rsvped = results[0] as bool;
      _summary = results[1] as Map<String, int>;
      _capacity = (results[2] as dynamic).seatingCapacity as int?;
    });
  }

  bool get _isFull => _capacity != null && (_summary?['total'] ?? 0) >= _capacity!;

  Future<void> _toggle() async {
    final service = FirestoreService();
    setState(() => _busy = true);
    try {
      if (_rsvped == true) {
        await service.cancelEventRsvp(widget.parishId, widget.churchId, widget.eventId);
      } else {
        if (_isFull) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This event is full.')));
          return;
        }
        final name = await showDialog<String>(
          context: context,
          builder: (dialogContext) {
            final ctrl = TextEditingController();
            String? need;
            return StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                backgroundColor: AppColors.paper,
                title: const Text('RSVP', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Your name')),
                    const SizedBox(height: 10),
                    const Text('Do you need a reserved seat?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    DropdownButton<String?>(
                      value: need, isExpanded: true,
                      hint: const Text('No, thanks', style: TextStyle(fontSize: 13)),
                      items: const [
                        DropdownMenuItem<String?>(value: null, child: Text('No, thanks')),
                        DropdownMenuItem<String?>(value: 'hearing', child: Text('Hearing assistance')),
                        DropdownMenuItem<String?>(value: 'vision', child: Text('Vision assistance')),
                        DropdownMenuItem<String?>(value: 'mobility', child: Text('Mobility / wheelchair access')),
                      ],
                      onChanged: (v) => setDialogState(() => need = v),
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                    onPressed: ctrl.text.trim().isEmpty ? null : () => Navigator.pop(dialogContext, '${ctrl.text.trim()}|${need ?? ''}'),
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            );
          },
        );
        if (name == null) return;
        final parts = name.split('|');
        await service.rsvpToEvent(
          parishId: widget.parishId, churchId: widget.churchId, eventId: widget.eventId,
          name: parts[0], accessibilityNeed: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
        );
      }
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rsvped == null) return const SizedBox(width: 60, height: 24);
    final total = _summary?['total'] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: _rsvped! ? AppColors.sage : AppColors.stone,
            side: BorderSide(color: _rsvped! ? AppColors.sage : AppColors.stone),
            minimumSize: const Size(0, 30),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _busy ? null : _toggle,
          child: Text(_rsvped! ? 'Going ✓' : (_isFull ? 'Full' : 'RSVP'), style: const TextStyle(fontSize: 11)),
        ),
        if (_capacity != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('$total/$_capacity', style: const TextStyle(fontSize: 10, color: Colors.black45)),
          ),
      ],
    );
  }
}