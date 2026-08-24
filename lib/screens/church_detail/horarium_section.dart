import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../models/church.dart';


class HorariumSection extends StatelessWidget {
  final String parishId;
  final String churchId;
  const HorariumSection({super.key, required this.parishId, required this.churchId});

  String _dayLabel(DateTime date) {
    return const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][date.weekday - 1];
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ServiceEntry>>(
      future: FirestoreService().getUpcomingServices(parishId, churchId, daysAhead: 7, hidePast: false),
      builder: (context, snap) {
        if (snap.hasError) return Text('Error: ${snap.error}');
        if (!snap.hasData) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator());
        final services = snap.data!;
        if (services.isEmpty) {
          return const Text('Nothing published for this week yet.', style: TextStyle(fontSize: 12, color: Colors.black45));
        }
        return Column(
          children: services.map((s) {
            final isCommunion = s.type == 'CommunionService';
            final isToday = _isToday(s.date);
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: EdgeInsets.symmetric(horizontal: isToday ? 10 : 0, vertical: 8),
              decoration: isToday
                  ? BoxDecoration(border: Border.all(color: AppColors.brass, width: 1.5), borderRadius: BorderRadius.circular(4))
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 90, child: Text(_dayLabel(s.date).toUpperCase(),
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 0.4, color: isToday ? AppColors.brass : AppColors.stone))),
                  SizedBox(width: 64, child: Text(s.time, style: const TextStyle(fontFamily: appSerif, fontSize: 18))),
                  Pill(isCommunion ? 'Communion Service' : 'Mass', tone: isCommunion ? 'outline' : 'sage'),
                  const Spacer(),
                  if (isToday) ...[const Pill('Today', tone: 'brass'), const SizedBox(width: 6)],
                  Pill(s.language, tone: 'outline'),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

