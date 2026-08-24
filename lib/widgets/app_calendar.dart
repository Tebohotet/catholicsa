import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/liturgical_calendar.dart';

/// Drop this anywhere a date picker with liturgical awareness is useful -
/// Readings, Events, a future Mass-time picker, anything. One definition,
/// reused everywhere, same reasoning as ShareButton and AsyncSection.
class AppCalendar extends StatefulWidget {
  final DateTime initialMonth;
  final void Function(DateTime date)? onDateSelected;

  const AppCalendar({super.key, required this.initialMonth, this.onDateSelected});

  @override
  State<AppCalendar> createState() => _AppCalendarState();
}

class _AppCalendarState extends State<AppCalendar> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(widget.initialMonth.year, widget.initialMonth.month, 1);
  }

  void _changeMonth(int delta) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1));
  }

  void _onTapDate(DateTime date) {
    if (widget.onDateSelected != null) {
      widget.onDateSelected!(date);
    } else {
      showDialog(context: context, builder: (_) => _DateInfoDialog(date: date));
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = _visibleMonth;
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday % 7;
    final today = DateTime.now();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1)),
            Text(DateFormat('MMMM yyyy').format(_visibleMonth), style: const TextStyle(fontFamily: appSerif, fontSize: 16)),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeMonth(1)),
          ],
        ),
        Row(
          children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
              .map((d) => Expanded(child: Center(child: Text(d, style: const TextStyle(fontSize: 11, color: Colors.black45)))))
              .toList(),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // childAspectRatio matters here specifically because this
          // widget gets embedded in containers of very different widths
          // (a narrow mobile dialog vs. a wide web dialog) - without it,
          // cells default to square, sized off whatever width they're
          // given, which on a wide web viewport makes every row far
          // taller than a day number needs and overflows the dialog
          // vertically. This is what actually caused the render-overflow
          // stripes.
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1.4),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = index - leadingBlanks + 1;
            final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
            final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
            final monthDay = '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

            return InkWell(
              onTap: () => _onTapDate(date),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isToday ? AppColors.brass : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$day', style: TextStyle(fontSize: 13, color: isToday ? Colors.white : AppColors.ink, fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FutureBuilder<Map<String, dynamic>?>(
                            future: FirestoreService().getFeastForDate(date),
                            builder: (context, snap) {
                              final feast = snap.data;
                              if (feast == null) return const SizedBox(width: 4, height: 4);
                              final grade = feast['grade'] as int? ?? 0;
                              // Solemnity=6, Feast=4-5, Memorial=2-3, weekday=0-1 -
                              // matches the grade scale confirmed directly from a
                              // real API sample (Memorial=3, Solemnity=6).
                              final dotColor = grade >= 6
                                  ? const Color(0xFFD4AF37) // gold - Solemnity
                                  : grade >= 4
                                      ? AppColors.brass // Feast
                                      : grade >= 2
                                          ? AppColors.sage // Memorial
                                          : Colors.transparent; // plain weekday - no dot
                              return Container(
                                margin: const EdgeInsets.only(right: 2),
                                width: 4, height: 4,
                                decoration: BoxDecoration(color: isToday ? Colors.white : dotColor, shape: BoxShape.circle),
                              );
                            },
                          ),
                          FutureBuilder<Map<String, dynamic>?>(
                            future: FirestoreService().getSaintByMonthDay(monthDay),
                            builder: (context, snap) {
                              if (snap.data == null) return const SizedBox(width: 4, height: 4);
                              return Container(width: 4, height: 4, decoration: BoxDecoration(color: isToday ? Colors.white : AppColors.sage, shape: BoxShape.circle));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DateInfoDialog extends StatelessWidget {
  final DateTime date;
  const _DateInfoDialog({required this.date});

  @override
  Widget build(BuildContext context) {
    final info = LiturgicalCalendar.infoFor(date);
    final monthDay = '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text(DateFormat('EEEE, d MMMM yyyy').format(date), style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info.displayTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Sunday Cycle ${info.sundayCycle} · Weekday Cycle ${info.weekdayCycle}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 14),
            FutureBuilder<Map<String, dynamic>?>(
              future: FirestoreService().getFeastForDate(date),
              builder: (context, snap) {
                if (!snap.hasData || snap.data == null) return const SizedBox.shrink();
                final feast = snap.data!;
                final grade = feast['grade'] as int? ?? 0;
                final gradeColor = grade >= 6
                    ? const Color(0xFFD4AF37)
                    : grade >= 4
                        ? AppColors.brass
                        : grade >= 2
                            ? AppColors.sage
                            : Colors.black45;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  color: AppColors.paperDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: gradeColor, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(feast['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (feast['gradeLabel'] != null) feast['gradeLabel'],
                          if (feast['liturgicalSeasonLabel'] != null) feast['liturgicalSeasonLabel'],
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      if (feast['commonLabel'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('Common: ${feast['commonLabel']}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                        ),
                      if (feast['color'] != null && (feast['color'] as List).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('Vestment colour: ${(feast['color'] as List).join(', ')}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                        ),
                      if (feast['psalterWeek'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('Psalter week ${feast['psalterWeek']}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                        ),
                      if (feast['holyDayOfObligation'] == true)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('Holy Day of Obligation', style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w600)),
                        ),
                      if (feast['hasVigilMass'] == true || feast['hasVesperI'] == true || feast['hasVesperII'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            [
                              if (feast['hasVigilMass'] == true) 'Vigil Mass',
                              if (feast['hasVesperI'] == true) 'First Vespers',
                              if (feast['hasVesperII'] == true) 'Second Vespers',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 11, color: AppColors.brass, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            FutureBuilder<Map<String, dynamic>?>(
              future: FirestoreService().getSaintByMonthDay(monthDay),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final saint = snap.data;
                if (saint == null) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(10),
                  color: AppColors.paperDark,
                  child: Row(
                    children: [
                      const Icon(Icons.church, size: 16, color: AppColors.brass),
                      const SizedBox(width: 8),
                      Expanded(child: Text(saint['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}