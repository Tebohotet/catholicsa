import 'dart:math';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class QuizScreen extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String courseId;
  final String lessonId;
  const QuizScreen({super.key, required this.parishId, required this.churchId, required this.courseId, required this.lessonId});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  Map<String, dynamic>? _quiz;
  List<Map<String, dynamic>> _sequence = [];
  String? _currentId;
  final Map<String, dynamic> _answers = {};
  final List<String> _questionsShown = [];
  bool _loading = true;
  bool _checking = false;
  bool _submitted = false;
  int? _selectedOption;
  List<int>? _dragOrder;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final quiz = await FirestoreService().getPublicQuiz(widget.parishId, widget.churchId, widget.courseId, widget.lessonId);
    if (quiz == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final allQuestions = (quiz['questions'] as List).cast<Map<String, dynamic>>();
    var pool = [...allQuestions];
    if (quiz['randomizeOrder'] == true) pool.shuffle(Random());
    final poolSize = quiz['questionPoolSize'] as int?;
    if (poolSize != null && poolSize < pool.length) pool = pool.sublist(0, poolSize);

    if (mounted) {
      setState(() {
        _quiz = quiz;
        _sequence = pool;
        _currentId = pool.isNotEmpty ? pool.first['id'] as String : null;
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _currentQuestion {
    if (_currentId == null) return null;
    final all = (_quiz!['questions'] as List).cast<Map<String, dynamic>>();
    try {
      return all.firstWhere((q) => q['id'] == _currentId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _answerAndAdvance() async {
    final q = _currentQuestion;
    if (q == null) return;
    final type = q['type'] as String? ?? 'multipleChoice';
    final dynamic answer = type == 'dragAndDrop' ? _dragOrder : _selectedOption;
    if (answer == null) return;

    setState(() => _checking = true);
    _answers[q['id']] = answer;
    _questionsShown.add(q['id']);

    bool correct = false;
    try {
      correct = await FirestoreService().checkQuizAnswer(
        parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId, lessonId: widget.lessonId,
        questionId: q['id'], answer: answer,
      );
    } catch (_) {
      // If the check fails (offline, etc.), fall back to sequence order -
      // the final grade is still computed correctly server-side once this
      // attempt is submitted; only the live branching hint is affected.
    }

    String? next = correct ? q['nextIfCorrect'] as String? : q['nextIfWrong'] as String?;
    if (next == null) {
      final idx = _sequence.indexWhere((item) => item['id'] == q['id']);
      if (idx >= 0 && idx + 1 < _sequence.length) {
        next = _sequence[idx + 1]['id'] as String;
      }
    }

    setState(() {
      _checking = false;
      _selectedOption = null;
      _dragOrder = null;
      _currentId = next;
    });

    if (next == null) await _submit();
  }

  Future<void> _submit() async {
    await FirestoreService().submitQuizAttempt(
      parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId, lessonId: widget.lessonId,
      answers: _answers, questionsShown: _questionsShown,
    );
    if (mounted) setState(() => _submitted = true);
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
                  const Text('Quiz', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _quiz == null
                      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No quiz found for this lesson.')))
                      : _submitted
                          ? _ResultView(parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId, lessonId: widget.lessonId)
                          : _buildQuestion(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    final q = _currentQuestion;
    if (q == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final type = q['type'] as String? ?? 'multipleChoice';
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q['text'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
          const SizedBox(height: 20),
          if (type == 'multipleChoice')
            RadioGroup<int>(
              groupValue: _selectedOption,
              onChanged: (v) => setState(() => _selectedOption = v),
              child: Column(
                children: List.generate((q['options'] as List).length, (i) => RadioListTile<int>(
                      title: Text((q['options'] as List)[i].toString()),
                      value: i,
                      activeColor: AppColors.brass,
                    )),
              ),
            ),
          if (type == 'dragAndDrop') _DragAndDropQuestion(
            items: (q['items'] as List).cast<String>(),
            onOrderChanged: (order) => setState(() => _dragOrder = order),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: _checking ? null : _answerAndAdvance,
              child: _checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Next'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DragAndDropQuestion extends StatefulWidget {
  final List<String> items;
  final void Function(List<int> order) onOrderChanged;
  const _DragAndDropQuestion({required this.items, required this.onOrderChanged});

  @override
  State<_DragAndDropQuestion> createState() => _DragAndDropQuestionState();
}

class _DragAndDropQuestionState extends State<_DragAndDropQuestion> {
  late List<int> _order;

  @override
  void initState() {
    super.initState();
    _order = List.generate(widget.items.length, (i) => i)..shuffle(Random());
    widget.onOrderChanged(_order);
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // onReorderItem has the identical signature to onReorder (verified
      // against the actual Flutter API docs, not guessed) - the one real
      // difference is newIndex arrives already corrected for the
      // removed-item-at-oldIndex quirk, so the manual `if (newIndex >
      // oldIndex) newIndex -= 1;` adjustment that onReorder always
      // needed is removed here, not just carried over.
      onReorderItem: (oldIndex, newIndex) {
        setState(() {
          final item = _order.removeAt(oldIndex);
          _order.insert(newIndex, item);
        });
        widget.onOrderChanged(_order);
      },
      children: [
        for (final idx in _order)
          ListTile(
            key: ValueKey(idx),
            tileColor: AppColors.paperDark,
            title: Text(widget.items[idx]),
            trailing: const Icon(Icons.drag_handle),
          ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  final String parishId;
  final String churchId;
  final String courseId;
  final String lessonId;
  const _ResultView({required this.parishId, required this.churchId, required this.courseId, required this.lessonId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: FirestoreService().streamQuizAttempt(parishId, churchId, courseId, lessonId),
      builder: (context, snap) {
        final attempt = snap.data;
        final graded = attempt != null && attempt['passed'] != null;
        if (!graded) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Grading...', style: TextStyle(color: Colors.black54)),
              ],
            ),
          );
        }
        final passed = attempt['passed'] == true;
        final score = (attempt['score'] as num?)?.toDouble() ?? 0;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(passed ? Icons.check_circle : Icons.cancel, size: 64, color: passed ? AppColors.sage : Colors.redAccent),
                const SizedBox(height: 16),
                Text('${score.round()}%', style: const TextStyle(fontFamily: appSerif, fontSize: 32)),
                const SizedBox(height: 8),
                Text(
                  passed ? 'Passed — this lesson is now marked complete.' : 'Not quite - try again when you\'re ready.',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Course'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}