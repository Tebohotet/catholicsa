import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';
import '../services/offline_service.dart';
import '../services/auth_service.dart';
import '../services/engagement_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import '../widgets/verified_name.dart';
import 'quiz_screen.dart';

class CourseDetailScreen extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String courseId;
  const CourseDetailScreen({super.key, required this.parishId, required this.churchId, required this.courseId});

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  Map<String, dynamic>? _course;
  Map<String, dynamic>? _enrollment;
  bool _loading = true;
  bool _enrolling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = FirestoreService();
    final course = await service.getCourse(widget.parishId, widget.churchId, widget.courseId);
    final enrollment = await service.getEnrollment(widget.parishId, widget.churchId, widget.courseId);
    if (mounted) setState(() { _course = course; _enrollment = enrollment; _loading = false; });
    _syncPendingCompletions();
  }

  /// Runs on every load, not reactively on connectivity change - a
  /// simple, honest retry rather than adding a new package just to
  /// listen for network state. Silently skips anything that still fails
  /// (still offline) - it stays queued for the next load.
  Future<void> _syncPendingCompletions() async {
    final pending = await OfflineService().getPendingCompletions();
    var syncedAny = false;
    for (final p in pending) {
      if (p['parishId'] != widget.parishId || p['churchId'] != widget.churchId || p['courseId'] != widget.courseId) continue;
      try {
        await FirestoreService().markLessonComplete(p['parishId'], p['churchId'], p['courseId'], p['lessonId']);
        await OfflineService().clearPendingCompletion(parishId: p['parishId'], churchId: p['churchId'], courseId: p['courseId'], lessonId: p['lessonId']);
        syncedAny = true;
      } catch (_) {
        // Still offline or still failing - stays queued, tried again
        // next time this screen loads.
      }
    }
    if (syncedAny && mounted) {
      final freshEnrollment = await FirestoreService().getEnrollment(widget.parishId, widget.churchId, widget.courseId);
      if (mounted) setState(() => _enrollment = freshEnrollment);
    }
  }

  Future<List<Map<String, dynamic>>> _getLessonsWithOfflineFallback() async {
    try {
      final lessons = await FirestoreService().getLessons(widget.parishId, widget.churchId, widget.courseId);
      return lessons;
    } catch (_) {
      final offline = await OfflineService().getOfflineCourse(widget.parishId, widget.churchId, widget.courseId);
      if (offline == null) rethrow;
      return List<Map<String, dynamic>>.from(offline['lessons'] ?? []);
    }
  }

  bool _downloading = false;

  Future<void> _downloadForOffline() async {
    setState(() => _downloading = true);
    try {
      final lessons = await FirestoreService().getLessons(widget.parishId, widget.churchId, widget.courseId);
      await OfflineService().saveCourseForOffline(
        parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId,
        courseTitle: _course?['title'] ?? '', lessons: lessons,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Course saved for offline reading.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not download - check your connection: $e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Compares completed lesson count against the real total - a course
  /// is "complete" only once every lesson genuinely has been, checked
  /// fresh each time rather than assumed.
  Future<void> _checkCourseCompletion() async {
    final lessons = await FirestoreService().getLessons(widget.parishId, widget.churchId, widget.courseId);
    final freshEnrollment = await FirestoreService().getEnrollment(widget.parishId, widget.churchId, widget.courseId);
    final completedIds = List<String>.from(freshEnrollment?['completedLessonIds'] ?? []);
    if (lessons.isNotEmpty && lessons.every((l) => completedIds.contains(l['id']))) {
      await EngagementService().recordActivity('courseComplete');
    }
  }

  Future<void> _enroll() async {
    setState(() => _enrolling = true);
    try {
      if (AuthService().currentUser == null) {
        await AuthService().signInWithGoogle();
      }
      if (AuthService().currentUser != null) {
        await FirestoreService().enrollInCourse(widget.parishId, widget.churchId, widget.courseId);
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not enroll: $e')));
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  Future<void> _openLesson(Map<String, dynamic> lesson) async {
    final completed = (_enrollment?['completedLessonIds'] as List?)?.contains(lesson['id']) ?? false;
    // A lesson with a quiz is gated - completion only ever happens via a
    // passing grade (server-side, via the Cloud Function), never a direct
    // tap here. Lessons with no quiz keep working exactly as before.
    final quiz = await FirestoreService().getPublicQuiz(widget.parishId, widget.churchId, widget.courseId, lesson['id']);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text(lesson['title'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(child: _LessonContentView(lesson: lesson)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          if (_enrollment != null && !completed && quiz != null)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => QuizScreen(parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId, lessonId: lesson['id']),
                ));
                _load();
              },
              child: const Text('Take Quiz'),
            ),
          if (_enrollment != null && !completed && quiz == null)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                try {
                  await FirestoreService().markLessonComplete(widget.parishId, widget.churchId, widget.courseId, lesson['id']);
                  EngagementService().recordActivity('lessonComplete');
                  await _checkCourseCompletion();
                } catch (_) {
                  // Genuinely offline, or a real network error either way -
                  // queue it rather than lose the action or show a raw
                  // error for something that isn't really a failure from
                  // the person's point of view.
                  await OfflineService().queuePendingCompletion(
                    parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId, lessonId: lesson['id'],
                  );
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _load();
              },
              child: const Text('Mark as Read'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
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
                              Text(_course?['title'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 20, color: Colors.white)),
                              VerifiedName(
                                uid: _course?['createdBy'] ?? '',
                                name: 'with ${_course?['catechistName'] ?? ''}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: CenteredContent(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_course?['description'] ?? '', style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 16),
                            if (_course?['meetingLink'] != null)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                                onPressed: () => launchUrl(Uri.parse(_course!['meetingLink']), mode: LaunchMode.externalApplication),
                                icon: const Icon(Icons.videocam_outlined, size: 16),
                                label: const Text('Join Live Session'),
                              ),
                            const SizedBox(height: 16),
                            if (_enrollment == null)
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                                  onPressed: _enrolling ? null : _enroll,
                                  icon: _enrolling
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.school_outlined, size: 16),
                                  label: const Text('Enroll in this Course'),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(10),
                                color: AppColors.paperDark,
                                child: const Row(children: [
                                  Icon(Icons.check_circle, color: AppColors.sage, size: 18),
                                  SizedBox(width: 8),
                                  Text("You're enrolled", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            if (_enrollment != null) ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                                onPressed: _downloading ? null : _downloadForOffline,
                                icon: _downloading
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.download_outlined, size: 16),
                                label: Text(_downloading ? 'Downloading...' : 'Download for Offline'),
                              ),
                            ],
                            const SizedBox(height: 24),
                            const SectionLabel(numeral: 'I', title: 'Lessons'),
                            AsyncSection<List<Map<String, dynamic>>>(
                              future: _getLessonsWithOfflineFallback(),
                              isEmpty: (l) => l.isEmpty,
                              emptyMessage: 'No lessons added yet.',
                              builder: (context, lessons) => Column(
                                children: lessons.map((l) {
                                  final completed = (_enrollment?['completedLessonIds'] as List?)?.contains(l['id']) ?? false;
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(completed ? Icons.check_circle : Icons.circle_outlined, color: completed ? AppColors.sage : Colors.black26, size: 20),
                                    title: Text(l['title'] ?? ''),
                                    trailing: const Icon(Icons.chevron_right, size: 18),
                                    onTap: () => _openLesson(l),
                                  );
                                }).toList(),
                              ),
                            ),

                            const SizedBox(height: 24),
                            const SectionLabel(numeral: 'II', title: 'Reviews'),
                            AsyncSection<List<Map<String, dynamic>>>(
                              future: FirestoreService().getCourseReviews(widget.parishId, widget.churchId, widget.courseId),
                              isEmpty: (l) => l.isEmpty,
                              emptyMessage: 'No reviews yet.',
                              builder: (context, reviews) {
                                final avg = reviews.isEmpty ? null : reviews.fold<num>(0, (a, r) => a + ((r['rating'] as num?) ?? 0)) / reviews.length;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (avg != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: Row(children: [
                                          const Icon(Icons.star, size: 16, color: AppColors.brass),
                                          const SizedBox(width: 4),
                                          Text('${avg.toStringAsFixed(1)} (${reviews.length} review${reviews.length == 1 ? '' : 's'})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                        ]),
                                      ),
                                    ...reviews.map((r) => Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(children: [
                                                Text(r['reviewerName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                                const SizedBox(width: 6),
                                                ...List.generate(5, (i) => Icon(
                                                      i < ((r['rating'] as num?) ?? 0) ? Icons.star : Icons.star_border,
                                                      size: 12, color: AppColors.brass,
                                                    )),
                                              ]),
                                              if ((r['comment'] as String?)?.isNotEmpty ?? false)
                                                Text(r['comment'], style: const TextStyle(fontSize: 12)),
                                            ],
                                          ),
                                        )),
                                  ],
                                );
                              },
                            ),
                            if (_enrollment != null) ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                                onPressed: () async {
                                  await showDialog(context: context, builder: (_) => _WriteReviewDialog(
                                    parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId,
                                  ));
                                  setState(() {});
                                },
                                icon: const Icon(Icons.rate_review_outlined, size: 16),
                                label: const Text('Write a Review'),
                              ),
                            ],
                          ],
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

class _WriteReviewDialog extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String courseId;
  const _WriteReviewDialog({required this.parishId, required this.churchId, required this.courseId});

  @override
  State<_WriteReviewDialog> createState() => _WriteReviewDialogState();
}

class _WriteReviewDialogState extends State<_WriteReviewDialog> {
  final _commentCtrl = TextEditingController();
  int _rating = 5;
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await FirestoreService().submitCourseReview(
        parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId,
        rating: _rating, comment: _commentCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit review: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('Write a Review', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) => IconButton(
                  icon: Icon(i < _rating ? Icons.star : Icons.star_border, color: AppColors.brass),
                  onPressed: () => setState(() => _rating = i + 1),
                )),
          ),
          TextField(controller: _commentCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Comment (optional)')),
        ],
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit'),
        ),
      ],
    );
  }
}

/// Renders real content blocks (heading/text/image) if present, falling
/// back to the old flat content field for any lesson written before
/// this structured model existed - no migration step needed, nothing
/// breaks for older content.
class _LessonContentView extends StatelessWidget {
  final Map<String, dynamic> lesson;
  const _LessonContentView({required this.lesson});

  @override
  Widget build(BuildContext context) {
    final blocks = List<Map<String, dynamic>>.from(lesson['blocks'] ?? []);
    if (blocks.isEmpty) {
      return Text(lesson['content'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((b) {
        switch (b['type']) {
          case 'heading':
            return Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(b['text'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 17, fontWeight: FontWeight.bold)),
            );
          case 'image':
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: b['imageUrl'] ?? '',
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
                      errorWidget: (context, url, error) => Container(
                        height: 80, color: AppColors.paperDark,
                        child: const Center(child: Text('Image unavailable offline', style: TextStyle(fontSize: 11, color: Colors.black45))),
                      ),
                    ),
                  ),
                  if ((b['caption'] as String?)?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(b['caption'], style: const TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
                    ),
                ],
              ),
            );
          default: // 'text'
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(b['text'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
            );
        }
      }).toList(),
    );
  }
}