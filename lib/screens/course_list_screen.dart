import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import 'course_detail_screen.dart';

class CourseListScreen extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String churchName;
  const CourseListScreen({super.key, required this.parishId, required this.churchId, required this.churchName});

  @override
  State<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends State<CourseListScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _sort = 'latest'; // 'latest' | 'topRated'

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getCoursesWithRatings(widget.parishId, widget.churchId);
  }

  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> courses) {
    final list = [...courses];
    if (_sort == 'topRated') {
      // Unrated courses sort last, not first - a course with zero
      // reviews shouldn't outrank one people have actually vouched for.
      list.sort((a, b) {
        final ra = a['averageRating'] as double?;
        final rb = b['averageRating'] as double?;
        if (ra == null && rb == null) return 0;
        if (ra == null) return 1;
        if (rb == null) return -1;
        return rb.compareTo(ra);
      });
    } else {
      // Same "push missing data to the end, don't leave it unspecified"
      // pattern as the topRated branch above - every course created
      // through the real admin flow or the demo seed does set createdAt,
      // so this is defensive rather than fixing something reachable
      // today, but it's the same one-line fix either way.
      list.sort((a, b) {
        final ta = a['createdAt'] as Timestamp?;
        final tb = b['createdAt'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
    }
    return list;
  }

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
              padding: const EdgeInsets.fromLTRB(4, 12, 16, 20),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Courses', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                        Text(widget.churchName, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  const Text('Sort:', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Latest', style: TextStyle(fontSize: 12)),
                    selected: _sort == 'latest',
                    selectedColor: AppColors.brass,
                    onSelected: (_) => setState(() => _sort = 'latest'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Top Rated', style: TextStyle(fontSize: 12)),
                    selected: _sort == 'topRated',
                    selectedColor: AppColors.brass,
                    onSelected: (_) => setState(() => _sort = 'topRated'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: CenteredContent(
                  child: AsyncSection<List<Map<String, dynamic>>>(
                    future: _future,
                    isEmpty: (l) => l.isEmpty,
                    emptyMessage: 'No courses published for this church yet — Baptism prep, First Communion, Confirmation classes will show up here once a catechist adds one.',
                    builder: (context, coursesRaw) {
                      final courses = _sorted(coursesRaw);
                      return ListView.builder(
                        itemCount: courses.length,
                        itemBuilder: (context, i) {
                          final c = courses[i];
                          final rating = c['averageRating'] as double?;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            color: AppColors.paperDark,
                            elevation: 0,
                            child: ListTile(
                              title: Text(c['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${c['catechistName'] ?? ''}\n${c['description'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                              isThreeLine: true,
                              trailing: rating != null
                                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.star, size: 14, color: AppColors.brass),
                                      const SizedBox(width: 2),
                                      Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 12)),
                                    ])
                                  : const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => CourseDetailScreen(parishId: widget.parishId, churchId: widget.churchId, courseId: c['id']),
                              )),
                            ),
                          );
                        },
                      );
                    },
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
