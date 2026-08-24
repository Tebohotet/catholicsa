import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/liturgical_day.dart';
import '../theme/app_theme.dart';
import '../providers/page_diagnostics_provider.dart';
import '../app.dart';
import '../providers/view_as_role_provider.dart';
import '../widgets/share_button.dart';
import '../widgets/app_calendar.dart';
import '../utils/bible_citation_parser.dart';
import 'bible_screen.dart';
import 'hymns_screen.dart';
import 'super_admin_panel_screen.dart' show SaintsManagementSection;
import '../widgets/super_admin_menu_widgets.dart';

class ReadingsScreen extends ConsumerStatefulWidget {
  const ReadingsScreen({super.key});

  @override
  ConsumerState<ReadingsScreen> createState() => _ReadingsScreenState();
}

class _ReadingsScreenState extends ConsumerState<ReadingsScreen> with RouteAware {
  DateTime _selectedDate = DateTime.now();
  late Future<LiturgicalDay?> _future;
  bool _editMode = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) rootRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    // Called specifically when navigating BACK to this screen from
    // something pushed on top of it - e.g. returning from Super Admin
    // after running a sync. Re-fetches so a change made elsewhere is
    // visible immediately, not just after a full app reload.
    setState(_load);
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadManifestIfNeeded();
    registerPageDiagnostics('Readings', [
      TestCase('getLiturgicalDay (selected date)', () => FirestoreService().getLiturgicalDay(_selectedDate)),
      TestCase('getFeastForDate (selected date)', () => FirestoreService().getFeastForDate(_selectedDate)),
    ]);
  }

  Future<void> _loadManifestIfNeeded() async {
    if (BibleCitationParser.booksLoaded) return;
    final raw = await rootBundle.loadString('assets/bible/manifest.json');
    final manifest = json.decode(raw) as Map<String, dynamic>;
    final books = (manifest['books'] as List).cast<Map<String, dynamic>>();
    BibleCitationParser.loadBooks(books);
    if (mounted) setState(() {});
  }

  void _load() {
    _future = FirestoreService().getLiturgicalDay(_selectedDate);
  }

  /// index is null when adding a new item, or the position of an
  /// existing one being edited/removed. Every path here ends by
  /// rewriting the whole vigilReadings array - Firestore has no way to
  /// touch a single array element directly.
  Future<void> _editVigilReading(List<VigilReadingItem> current, int? index) async {
    final isNew = index == null;
    final existing = isNew ? null : current[index];
    final readingCtrl = TextEditingController(text: existing?.reading ?? '');
    final psalmCtrl = TextEditingController(text: existing?.psalm ?? '');
    final psalmResponseCtrl = TextEditingController(text: existing?.psalmResponse ?? '');

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text(isNew ? 'Add Vigil Reading' : 'Edit Vigil Reading', style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: readingCtrl, maxLines: 2, autofocus: isNew, decoration: const InputDecoration(labelText: 'Reading citation')),
              const SizedBox(height: 8),
              TextField(controller: psalmCtrl, decoration: const InputDecoration(labelText: 'Psalm citation (optional)')),
              const SizedBox(height: 8),
              TextField(controller: psalmResponseCtrl, decoration: const InputDecoration(labelText: 'Psalm response (optional)')),
            ],
          ),
        ),
        actions: [
          if (!isNew)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(dialogContext, 'delete'),
              child: const Text('Remove'),
            ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (action == null) return;

    final updated = List<VigilReadingItem>.from(current);
    if (action == 'delete') {
      updated.removeAt(index!);
    } else if (readingCtrl.text.trim().isNotEmpty) {
      final newItem = VigilReadingItem(
        order: isNew ? updated.length : existing!.order,
        reading: readingCtrl.text.trim(),
        psalm: psalmCtrl.text.trim().isEmpty ? null : psalmCtrl.text.trim(),
        psalmResponse: psalmResponseCtrl.text.trim().isEmpty ? null : psalmResponseCtrl.text.trim(),
      );
      if (isNew) {
        updated.add(newItem);
      } else {
        updated[index] = newItem;
      }
    } else {
      return; // empty reading on save - nothing meaningful to persist
    }

    await _saveVigilReadings(updated);
  }

  /// Opens a table-style editor for the whole vigil readings list at
  /// once - fill in as many rows as needed (the Easter Vigil's 7 is the
  /// real example), then one save writes the entire list together,
  /// rather than 7 separate open/save cycles through the single-item
  /// dialog.
  Future<void> _bulkEditVigilReadings(List<VigilReadingItem> current) async {
    final saved = await showDialog<List<VigilReadingItem>>(
      context: context,
      builder: (_) => _BulkVigilReadingsDialog(initial: current),
    );
    if (saved == null) return;
    await _saveVigilReadings(saved);
  }

  /// Real save confirmation, not silence either way - this was the
  /// actual gap: a save with no error handling and no success feedback
  /// looks identical whether it worked or failed silently, which is
  /// exactly what happened.
  Future<void> _saveVigilReadings(List<VigilReadingItem> updated) async {
    try {
      await FirestoreService().updateVigilReadings(_dateKey, updated.map((v) => v.toMap()).toList());
      setState(_load);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved — ${updated.length} vigil reading${updated.length == 1 ? '' : 's'}.'), backgroundColor: AppColors.sage),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _changeDay(int delta) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: delta));
      _load();
    });
  }

  String get _dateKey => '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Readings', style: TextStyle(fontFamily: appSerif, fontSize: 26, color: Colors.white))),
                      Consumer(
                        builder: (context, ref, _) {
                          final isSuperAdminAsync = ref.watch(isRealSuperAdminProvider);
                          final isSuperAdmin = isSuperAdminAsync.maybeWhen(data: (v) => v, orElse: () => false);
                          if (!isSuperAdmin) return const SizedBox.shrink();
                          return IconButton(
                            tooltip: _editMode ? 'Exit edit mode' : 'Edit this page',
                            icon: Icon(_editMode ? Icons.edit : Icons.edit_outlined, color: _editMode ? AppColors.brass : Colors.white),
                            onPressed: () => setState(() => _editMode = !_editMode),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'View Hymns',
                        icon: const Icon(Icons.library_music_outlined, color: Colors.white),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HymnsScreen())),
                      ),
                      IconButton(
                        tooltip: 'Browse the Bible',
                        icon: const Icon(Icons.menu_book_outlined, color: Colors.white),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BibleScreen())),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.white),
                        onPressed: () => _changeDay(-1),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              isToday ? 'Today' : DateFormat('EEEE').format(_selectedDate),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(DateFormat('d MMMM yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, color: Colors.white),
                        onPressed: () => _changeDay(1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_month, color: Colors.white, size: 20),
                        tooltip: 'Jump to a date',
                        onPressed: () => showDialog(
                          context: context,
                          builder: (dialogContext) => Dialog(
                            backgroundColor: AppColors.paper,
                            child: SizedBox(
                              width: 360,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: AppCalendar(
                                  initialMonth: _selectedDate,
                                  onDateSelected: (date) {
                                    Navigator.pop(dialogContext);
                                    setState(() { _selectedDate = date; _load(); });
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: CenteredContent(
                  child: FutureBuilder<LiturgicalDay?>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Text('Could not load readings: ${snap.error}', style: const TextStyle(color: Colors.redAccent)),
                        );
                      }
                      // Checking connectionState here, not hasData - hasData
                      // is only true when the Future resolves to a NON-null
                      // value, but getLiturgicalDay legitimately resolves to
                      // null whenever a date has no seeded reading (which is
                      // most dates right now). That made "still loading" and
                      // "loaded, nothing found" indistinguishable, so the
                      // spinner below never went away for exactly the dates
                      // that should show the honest "not published yet"
                      // message instead - this is the actual bug that was
                      // making Readings look permanently stuck.
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()));
                      }
                      final day = snap.data;
                      if (day == null) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Text('No readings published for this day yet.', style: TextStyle(color: Colors.black45)),
                        );
                      }
                      final en = day.readingsByLanguage['en'];
                      if (en == null) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Text('No readings published for this day yet.', style: TextStyle(color: Colors.black45)),
                        );
                      }
                      final shareText = '${day.liturgicalTitle}\n\n'
                          'First Reading: ${en.firstReading}\n'
                          '${en.psalm != null ? 'Responsorial Psalm: ${en.psalm}\n' : ''}'
                          '${en.secondReading != null ? 'Second Reading: ${en.secondReading}\n' : ''}'
                          'Gospel: ${en.gospel}';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(day.liturgicalTitle, style: const TextStyle(fontFamily: appSerif, fontSize: 20, color: AppColors.stoneDark))),
                              ShareButton(title: day.liturgicalTitle, body: shareText),
                            ],
                          ),
                          if (day.sundayCycle != null || day.weekdayCycle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                day.sundayCycle != null ? 'Year ${day.sundayCycle}' : 'Cycle ${day.weekdayCycle}',
                                style: const TextStyle(fontSize: 11, color: Colors.black45),
                              ),
                            ),
                          const SizedBox(height: 8),
                          _SaintFeatureCard(date: _selectedDate, editMode: _editMode),
                          const SizedBox(height: 16),
                          _EditableField(
                            editMode: _editMode,
                            dateKey: _dateKey,
                            fieldKey: 'entranceAntiphon',
                            label: 'Entrance Antiphon',
                            value: en.entranceAntiphon ?? '',
                            isHidden: en.hiddenFields.contains('entranceAntiphon'),
                            onSaved: () => setState(_load),
                            child: _AntiphonBlock(label: 'Entrance Antiphon', text: en.entranceAntiphon ?? ''),
                          ),
                          _EditableField(
                            editMode: _editMode,
                            dateKey: _dateKey,
                            fieldKey: 'firstReading',
                            label: 'First Reading',
                            value: en.firstReading,
                            isHidden: en.hiddenFields.contains('firstReading'),
                            onSaved: () => setState(_load),
                            child: _ReadingRow(label: 'First Reading', citation: en.firstReading),
                          ),
                          if (en.psalm != null)
                            _EditableField(
                              editMode: _editMode,
                              dateKey: _dateKey,
                              fieldKey: 'psalm',
                              label: 'Responsorial Psalm',
                              value: en.psalm!,
                              isHidden: en.hiddenFields.contains('psalm'),
                              onSaved: () => setState(_load),
                              child: _ReadingRow(label: 'Responsorial Psalm', citation: en.psalm!),
                            ),
                          if ((en.psalmResponse ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 16, bottom: 8),
                              child: Text('℟. ${en.psalmResponse}', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.brass)),
                            ),
                          if (en.vigilReadings.isNotEmpty || _editMode) ...[
                            const SizedBox(height: 8),
                            const Text('Vigil Readings', style: TextStyle(fontSize: 11, color: AppColors.brass, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                            const SizedBox(height: 4),
                            ...en.vigilReadings.asMap().entries.map((entry) {
                              final i = entry.key;
                              final item = entry.value;
                              final rowContent = Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _ReadingRow(label: 'Reading ${i + 1}', citation: item.reading),
                                    if ((item.psalm ?? '').isNotEmpty) _ReadingRow(label: 'Psalm ${i + 1}', citation: item.psalm!),
                                    if ((item.psalmResponse ?? '').isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 16, bottom: 8),
                                        child: Text('℟. ${item.psalmResponse}', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.brass)),
                                      ),
                                  ],
                                ),
                              );
                              if (!_editMode) return rowContent;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(border: Border.all(color: AppColors.brass.withValues(alpha: 0.35)), borderRadius: BorderRadius.circular(4)),
                                child: InkWell(
                                  onTap: () => _editVigilReading(en.vigilReadings, i),
                                  child: Stack(children: [
                                    Padding(padding: const EdgeInsets.only(right: 28), child: rowContent),
                                    const Positioned(top: 6, right: 6, child: Icon(Icons.edit, size: 14, color: AppColors.brass)),
                                  ]),
                                ),
                              );
                            }),
                            if (_editMode)
                              Row(children: [
                                Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8, right: 4),
                                    decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(4)),
                                    child: InkWell(
                                      onTap: () => _editVigilReading(en.vigilReadings, null),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                          Icon(Icons.add_circle_outline, size: 16, color: AppColors.brass),
                                          SizedBox(width: 8),
                                          Flexible(child: Text('Add One', style: TextStyle(fontSize: 13, color: AppColors.brass, fontStyle: FontStyle.italic))),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8, left: 4),
                                    decoration: BoxDecoration(border: Border.all(color: AppColors.brass), borderRadius: BorderRadius.circular(4)),
                                    child: InkWell(
                                      onTap: () => _bulkEditVigilReadings(en.vigilReadings),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                          Icon(Icons.table_rows_outlined, size: 16, color: AppColors.brass),
                                          SizedBox(width: 8),
                                          Flexible(child: Text('Add / Edit as List', style: TextStyle(fontSize: 13, color: AppColors.brass, fontWeight: FontWeight.w600))),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                              ]),
                            const SizedBox(height: 8),
                          ],
                          if (en.secondReading != null)
                            _EditableField(
                              editMode: _editMode,
                              dateKey: _dateKey,
                              fieldKey: 'secondReading',
                              label: 'Second Reading',
                              value: en.secondReading!,
                              isHidden: en.hiddenFields.contains('secondReading'),
                              onSaved: () => setState(_load),
                              child: _ReadingRow(label: 'Second Reading', citation: en.secondReading!),
                            ),
                          if ((en.gospelAcclamation ?? '').isNotEmpty) _AntiphonBlock(label: 'Gospel Acclamation', text: en.gospelAcclamation!),
                          _EditableField(
                            editMode: _editMode,
                            dateKey: _dateKey,
                            fieldKey: 'gospel',
                            label: 'Gospel',
                            value: en.gospel,
                            isHidden: en.hiddenFields.contains('gospel'),
                            onSaved: () => setState(_load),
                            child: _ReadingRow(label: 'Gospel', citation: en.gospel),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap a reading to see the actual verse text (Douay-Rheims, public domain) — available for a small set of days so far, more added over time.',
                            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: 20),
                          _EditableField(
                            editMode: _editMode,
                            dateKey: _dateKey,
                            fieldKey: 'verseForTheDay',
                            label: 'Verse for the Day',
                            value: en.verseForTheDay ?? '',
                            isHidden: en.hiddenFields.contains('verseForTheDay'),
                            onSaved: () => setState(_load),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              color: AppColors.paperDark,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Verse for the Day', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brass)),
                                  const SizedBox(height: 4),
                                  Text('"${en.verseForTheDay}"', style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic)),
                                  if ((en.verseForTheDayCitation ?? '').isNotEmpty)
                                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('— ${en.verseForTheDayCitation}', style: const TextStyle(fontSize: 12, color: Colors.black54))),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _EditableField(
                            editMode: _editMode,
                            dateKey: _dateKey,
                            fieldKey: 'reflectionBody',
                            label: 'Reflection',
                            value: en.reflectionBody ?? '',
                            isHidden: en.hiddenFields.contains('reflectionBody'),
                            onSaved: () => setState(_load),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(en.reflectionTitle?.isNotEmpty == true ? en.reflectionTitle! : 'Reflection', style: const TextStyle(fontFamily: appSerif, fontSize: 16)),
                                const SizedBox(height: 6),
                                Text(en.reflectionBody ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
                              ],
                            ),
                          ),
                          if ((en.themedBoxBody ?? '').isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              color: AppColors.stone,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((en.themedBoxTitle ?? '').isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(en.themedBoxTitle!, style: const TextStyle(fontFamily: appSerif, fontSize: 14, color: Colors.white)),
                                    ),
                                  Text(en.themedBoxBody!, style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.5)),
                                ],
                              ),
                            ),
                          ],
                          if (en.petitions.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            const Text('Prayers of the Faithful', style: TextStyle(fontFamily: appSerif, fontSize: 16)),
                            if ((en.prayersIntro ?? '').isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 6), child: Text(en.prayersIntro!, style: const TextStyle(fontSize: 13, height: 1.5))),
                            if ((en.prayersResponse ?? '').isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 6), child: Text('Response: ${en.prayersResponse}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brass))),
                            const SizedBox(height: 6),
                            ...en.petitions.asMap().entries.map((entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text('${entry.key + 1}. ${entry.value} ${en.prayersResponse != null ? '℟.' : ''}', style: const TextStyle(fontSize: 13, height: 1.5)),
                            )),
                            if ((en.prayersClosing ?? '').isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 4), child: Text(en.prayersClosing!, style: const TextStyle(fontSize: 13, height: 1.5, fontStyle: FontStyle.italic))),
                          ],
                          const SizedBox(height: 20),
                          _EditableField(
                            editMode: _editMode,
                            dateKey: _dateKey,
                            fieldKey: 'communionAntiphon',
                            label: 'Communion Antiphon',
                            value: en.communionAntiphon ?? '',
                            isHidden: en.hiddenFields.contains('communionAntiphon'),
                            onSaved: () => setState(_load),
                            child: _AntiphonBlock(label: 'Communion Antiphon', text: en.communionAntiphon ?? ''),
                          ),
                          const SizedBox(height: 28),
                          _NotesSection(dateKey: _dateKey),
                        ],
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

class _ReadingRow extends StatelessWidget {
  final String label;
  final String citation;
  const _ReadingRow({required this.label, required this.citation});

  /// Shows the resolved English book name instead of whatever spelling
  /// the stored citation actually used ("Lucam" -> "Luke") - reuses the
  /// same resolution the inline scripture fetch already does, so the
  /// display and the fetch never disagree with each other. Falls back
  /// to the raw stored text if the citation can't be parsed at all,
  /// since showing something is better than showing nothing.
  static String _displayCitation(String citation) {
    if (!BibleCitationParser.booksLoaded) return citation;
    final parsed = BibleCitationParser.parse(citation);
    if (parsed == null) return citation;
    final numericPart = citation.split('|').first.trim().replaceFirst(RegExp(r'^[^\d]+'), '');
    return '${parsed.bookName} $numericPart';
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _displayCitation(citation);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => BibleScreen(citation: citation, label: label),
            )),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: AppColors.brass, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                Row(
                  children: [
                    Text(displayText, style: const TextStyle(fontSize: 16, fontFamily: appSerif, decoration: TextDecoration.underline, decorationColor: Colors.black26)),
                    const SizedBox(width: 6),
                    const Icon(Icons.menu_book_outlined, size: 14, color: Colors.black38),
                  ],
                ),
              ],
            ),
          ),
          _InlineScripture(citation: citation),
        ],
      ),
    );
  }
}

/// Shows just the cited verse range directly on the page - "the part
/// that is actually read" - by parsing the citation and pulling the
/// matching chapter from the app's own already-synced Douay-Rheims
/// data (confirmed public domain, synced from Project Gutenberg earlier
/// this session). Silently shows nothing if the citation can't be
/// parsed or that chapter isn't in the database - the tap-through link
/// above still works either way, so nothing is ever lost, just not
/// duplicated inline.
class _InlineScripture extends StatelessWidget {
  final String citation;
  const _InlineScripture({required this.citation});

  /// Confirmed directly (not assumed) from multiple sources: the
  /// Douay-Rheims, translated from the Latin Vulgate, uses the older
  /// Septuagint/Vulgate psalm numbering - but a lectionary citation like
  /// "Psalm 31" is written in the modern Hebrew numbering used by the
  /// USCCB and most contemporary sources. These two systems agree for
  /// Psalms 1-8 and 148-150, but are offset by one throughout the
  /// middle range, because the Vulgate combines Hebrew Psalms 9 and 10
  /// into a single Psalm 9. Applied only to the Psalms book code - this
  /// is specific to how the Psalter alone was historically renumbered,
  /// not a general citation issue affecting any other book.
  ///
  /// Honest limitation: this corrects the CHAPTER number. Some psalms
  /// also carry a verse-numbering shift within the chapter itself (the
  /// Vulgate counts a psalm's title/superscription as verse 1 in some
  /// psalms, shifting every verse after it by one) - that finer,
  /// psalm-by-psalm verse offset isn't corrected here, since it isn't
  /// a single, consistent rule the way the chapter offset is.
  static int _lectionaryToDouayRheimsPsalmChapter(int hebrewNumber) {
    if (hebrewNumber <= 8) return hebrewNumber;
    if (hebrewNumber == 9 || hebrewNumber == 10) return 9;
    if (hebrewNumber >= 11 && hebrewNumber <= 146) return hebrewNumber - 1;
    if (hebrewNumber == 147) return 146;
    return hebrewNumber; // 148-150, numbering re-converges
  }

  /// Session-level cache, keyed by "translationCode/bookCode/chapter" -
  /// once a chapter's been fetched, re-showing it (navigating back to a
  /// date already viewed, or two readings sharing a chapter) never hits
  /// Firestore again for the rest of the app's session. Real reduction
  /// in concurrent requests per date view, not just a theoretical one.
  static final Map<String, Map<String, dynamic>?> _chapterCache = {};

  static Future<Map<String, dynamic>?> _getChapterCached(String bookCode, int chapter) async {
    final key = 'douayRheims/$bookCode/$chapter';
    if (_chapterCache.containsKey(key)) return _chapterCache[key];
    final data = await FirestoreService().getBibleChapter(
      translationCode: 'douayRheims',
      bookCode: bookCode,
      chapter: chapter,
    );
    _chapterCache[key] = data;
    return data;
  }

  /// A citation can genuinely span more than one chapter ("Isaiah
  /// 52:13-53:12", "John 18:1-19:42") or list several separate
  /// chapter:verse groups with a semicolon ("Hebrews 4:14-16; 5:7-9") -
  /// real formats confirmed directly from an actual missal page, not
  /// assumed. Returns one entry per chapter actually needed: chapter
  /// number, plus which verses to include (null means the whole
  /// chapter, used for any chapter fully inside a wide range).
  static List<({int chapter, List<int>? verses})> _parseChapterSpecs(String citation) {
    // "everything after the book name" - the book name itself was
    // already resolved separately via BibleCitationParser, so this only
    // needs the numeric part, e.g. "52:13-53:12" or "4:14-16; 5:7-9".
    final numericPart = citation.replaceFirst(RegExp(r'^[^\d]+'), '');
    final specs = <({int chapter, List<int>? verses})>[];

    for (final group in numericPart.split(';')) {
      final g = group.trim();
      // Cross-chapter range: "52:13-53:12" or "18:1-19:42" - two
      // chapter:verse points joined by a dash (an em-dash from the
      // source text normalizes to a plain hyphen here).
      final crossChapter = RegExp(r'^(\d+):(\d+)[a-zA-Z]?\s*[-\u2014\u2013]\s*(\d+):(\d+)[a-zA-Z]?$').firstMatch(g);
      if (crossChapter != null) {
        final fromChapter = int.parse(crossChapter.group(1)!);
        final fromVerse = int.parse(crossChapter.group(2)!);
        final toChapter = int.parse(crossChapter.group(3)!);
        final toVerse = int.parse(crossChapter.group(4)!);
        if (fromChapter == toChapter) {
          specs.add((chapter: fromChapter, verses: [for (var v = fromVerse; v <= toVerse; v++) v]));
        } else {
          specs.add((chapter: fromChapter, verses: null)); // from fromVerse to the chapter's real end - shown as "whole chapter from here" since the exact last verse number isn't known without fetching it first
          for (var c = fromChapter + 1; c < toChapter; c++) {
            specs.add((chapter: c, verses: null));
          }
          specs.add((chapter: toChapter, verses: [for (var v = 1; v <= toVerse; v++) v]));
        }
        continue;
      }
      // Ordinary single-chapter group: "4:14-16" or "9:9a, 11-13a" -
      // same multi-segment comma parsing as before.
      final chapterMatch = RegExp(r'^(\d+):(.+)$').firstMatch(g);
      if (chapterMatch == null) continue;
      final chapter = int.parse(chapterMatch.group(1)!);
      final verseNumbers = <int>[];
      for (final raw in chapterMatch.group(2)!.split(',')) {
        final seg = raw.trim();
        final rangeMatch = RegExp(r'^(\d+)[a-zA-Z]?\s*-\s*(\d+)[a-zA-Z]?$').firstMatch(seg);
        if (rangeMatch != null) {
          final from = int.tryParse(rangeMatch.group(1)!);
          final to = int.tryParse(rangeMatch.group(2)!);
          if (from != null && to != null) {
            for (var v = from; v <= to; v++) {
              verseNumbers.add(v);
            }
          }
          continue;
        }
        final singleMatch = RegExp(r'^(\d+)[a-zA-Z]?$').firstMatch(seg);
        if (singleMatch != null) {
          final v = int.tryParse(singleMatch.group(1)!);
          if (v != null) verseNumbers.add(v);
        }
      }
      specs.add((chapter: chapter, verses: verseNumbers));
    }
    return specs;
  }

  @override
  Widget build(BuildContext context) {
    if (!BibleCitationParser.booksLoaded) return const SizedBox.shrink();
    final parsed = BibleCitationParser.parse(citation);
    if (parsed == null) return const SizedBox.shrink();
    final specs = _parseChapterSpecs(citation);
    if (specs.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: Future.wait(specs.map((s) {
        final chapterToFetch = parsed.bookCode == 'psa' ? _lectionaryToDouayRheimsPsalmChapter(s.chapter) : s.chapter;
        return _getChapterCached(parsed.bookCode, chapterToFetch);
      })),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final chapterDataList = snap.data;
        if (chapterDataList == null) return const SizedBox.shrink();

        final buffer = StringBuffer();
        for (var i = 0; i < specs.length; i++) {
          final spec = specs[i];
          final data = chapterDataList[i];
          if (data == null) continue;
          final verses = Map<String, dynamic>.from(data['verses'] ?? {});
          if (verses.isEmpty) continue;

          // null verses means "whole chapter from here" - genuinely
          // means every verse actually present in that chapter's data,
          // sorted numerically, not a guessed count.
          final verseNumbers = spec.verses ?? (verses.keys.map(int.parse).toList()..sort());
          for (final v in verseNumbers) {
            final text = verses[v.toString()];
            if (text != null) {
              if (buffer.isNotEmpty) buffer.write(' ');
              buffer.write('$v. $text');
            }
          }
        }
        if (buffer.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.paperDark, borderRadius: BorderRadius.circular(4)),
            child: Text(buffer.toString(), style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        );
      },
    );
  }
}

/// Auto-detects the saint/feast via the free Church Calendar API. If we
/// have a curated profile for that saint, tapping opens the rich card;
/// otherwise just shows the name honestly, no fake bio.
/// Matches the weekday missal's own layout - the saint's portrait and a
/// short bio sit prominently on the page itself, not hidden behind a
/// tap. Tapping still opens the full dialog (complete bio, patronage,
/// medals) for anyone who wants more than the snippet shown here.
class _SaintFeatureCard extends StatelessWidget {
  final DateTime date;
  final bool editMode;
  const _SaintFeatureCard({required this.date, required this.editMode});

  @override
  Widget build(BuildContext context) {
    final monthDay = '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return FutureBuilder<Map<String, dynamic>?>(
      future: FirestoreService().getSaintByMonthDay(monthDay),
      builder: (context, snap) {
        if (!snap.hasData || snap.data == null) {
          if (!editMode) return const SizedBox.shrink();
          // No dedicated inline mini-form here on purpose - a saint has
          // real structured fields (name, feast date, bio, image
          // upload) with a proper admin form already built for it;
          // duplicating a smaller version of that here would just be a
          // second, worse editor for the same data.
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(4)),
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSectionHost(title: 'Saints Database', child: SaintsManagementSection()))),
              child: Row(children: [
                const Icon(Icons.add_circle_outline, size: 16, color: AppColors.brass),
                const SizedBox(width: 8),
                const Text('Add a saint for this date', style: TextStyle(fontSize: 13, color: AppColors.brass, fontStyle: FontStyle.italic)),
              ]),
            ),
          );
        }
        final saint = snap.data!;
        final bio = saint['bio'] as String? ?? '';
        return InkWell(
          onTap: () => showDialog(context: context, builder: (_) => _SaintDialog(saint: saint)),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.paperDark,
              border: Border.all(color: AppColors.brass.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (saint['imageUrl'] != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(saint['imageUrl'], width: 84, height: 100, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(saint['name'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      if (bio.isNotEmpty)
                        Text(bio, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.black87)),
                      const SizedBox(height: 4),
                      const Text('Tap to read more', style: TextStyle(fontSize: 10, color: AppColors.brass, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SaintDialog extends StatelessWidget {
  final Map<String, dynamic> saint;
  const _SaintDialog({required this.saint});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (saint['imageUrl'] != null)
                ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(saint['imageUrl'], height: 160, width: double.infinity, fit: BoxFit.cover)),
              if (saint['imageUrl'] != null) const SizedBox(height: 12),
              Text(saint['name'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
              if (saint['feastDay'] != null)
                Text('Feast Day: ${saint['feastDay']}', style: const TextStyle(fontSize: 12, color: AppColors.brass, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(saint['bio'] ?? '', style: const TextStyle(fontSize: 13)),
              if ((saint['patronage'] as List?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 12),
                const Text('Patron of', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone)),
                Text((saint['patronage'] as List).join(', '), style: const TextStyle(fontSize: 12)),
              ],
              if ((saint['medals'] as List?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 12),
                const Text('Medals', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone)),
                ...(saint['medals'] as List).map((m) => Text('• $m', style: const TextStyle(fontSize: 12))),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

/// Sign-in gated - a private note is tied to a real account, not stored
/// anonymously, matching the same pattern used for comments and bookings.
class _NotesSection extends StatefulWidget {
  final String dateKey;
  const _NotesSection({required this.dateKey});

  @override
  State<_NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<_NotesSection> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _NotesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateKey != widget.dateKey) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (AuthService().currentUser != null) {
      final note = await FirestoreService().getReadingNote(widget.dateKey);
      _ctrl.text = note ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    try {
      await AuthService().signInWithGoogle();
      await _load();
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirestoreService().saveReadingNote(widget.dateKey, _ctrl.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note saved')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()));

    if (AuthService().currentUser == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        color: AppColors.paperDark,
        child: Row(
          children: [
            const Expanded(child: Text('Sign in to add a private note on this reading — only visible to you.', style: TextStyle(fontSize: 12, color: Colors.black54))),
            TextButton(
              onPressed: _signingIn ? null : _signIn,
              child: _signingIn ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('My Notes', style: TextStyle(fontSize: 11, color: AppColors.brass, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        const SizedBox(height: 6),
        TextField(
          controller: _ctrl,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Private — only you can see this', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Note'),
          ),
        ),
      ],
    );
  }
}

/// Simple labeled text block - reused for Entrance Antiphon, Gospel
/// Acclamation, and Communion Antiphon, which all share the same visual
/// shape in a real missal.
class _AntiphonBlock extends StatelessWidget {
  final String label;
  final String text;
  const _AntiphonBlock({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brass, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(text, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, height: 1.4)),
        ],
      ),
    );
  }
}

/// When editMode is false, renders the child exactly as it always has -
/// zero visual difference for a regular user. When true, wraps it with a
/// dashed border and a small edit affordance; tapping opens a dialog to
/// change the text or hide/unhide this specific field, without touching
/// anything else on the reading document.
class _EditableField extends StatelessWidget {
  final bool editMode;
  final String dateKey;
  final String fieldKey;
  final String label;
  final String value;
  final bool isHidden;
  final VoidCallback onSaved;
  final Widget child;
  const _EditableField({
    required this.editMode,
    required this.dateKey,
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.isHidden,
    required this.onSaved,
    required this.child,
  });

  Future<void> _openEditor(BuildContext context) async {
    final ctrl = TextEditingController(text: value);
    bool hidden = isHidden;
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: Text(value.isEmpty ? 'Add — $label' : 'Edit — $label', style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: ctrl, maxLines: 6, autofocus: value.isEmpty, decoration: const InputDecoration(border: OutlineInputBorder())),
                if (value.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.brass,
                    title: const Text('Hide from readers', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Keeps the text saved - just stops it showing on this page.', style: TextStyle(fontSize: 11, color: Colors.black45)),
                    value: hidden,
                    onChanged: (v) => setDialogState(() => hidden = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                if (ctrl.text.trim().isNotEmpty && ctrl.text.trim() != value) {
                  await FirestoreService().updateReadingFieldValue(dateKey, fieldKey, ctrl.text.trim());
                }
                if (hidden != isHidden) {
                  await FirestoreService().setReadingFieldHidden(dateKey, fieldKey, hidden);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                onSaved();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!editMode) {
      // Unchanged for a regular user: empty or hidden means nothing
      // renders here at all.
      if (value.isEmpty || isHidden) return const SizedBox.shrink();
      return child;
    }

    // The actual fix: an empty field used to simply never appear in
    // edit mode either, so there was no way to add it for the first
    // time - only ever edit something that already existed. Now shows
    // a real, tappable "+ Add [Label]" placeholder instead.
    if (value.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: InkWell(
          onTap: () => _openEditor(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              const Icon(Icons.add_circle_outline, size: 16, color: AppColors.brass),
              const SizedBox(width: 8),
              Text('Add $label', style: const TextStyle(fontSize: 13, color: AppColors.brass, fontStyle: FontStyle.italic)),
            ]),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border.all(color: isHidden ? Colors.redAccent.withValues(alpha: 0.4) : AppColors.brass.withValues(alpha: 0.35), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: () => _openEditor(context),
        child: Stack(
          children: [
            Padding(padding: const EdgeInsets.only(top: 4, right: 28), child: Opacity(opacity: isHidden ? 0.4 : 1, child: child)),
            Positioned(
              top: 2, right: 2,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (isHidden)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Text('HIDDEN', style: TextStyle(fontSize: 9, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
                const Icon(Icons.edit, size: 14, color: AppColors.brass),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Table-style bulk editor for the whole vigil readings list at once -
/// matches "# / Reading / Psalm" as a real numbered list, pre-filled
/// with any rows already there. psalmResponse is deliberately left out
/// of this view (kept simple, matching what was actually asked for) -
/// still addable per-row through the single-item edit dialog afterward
/// if needed.
class _BulkVigilReadingsDialog extends StatefulWidget {
  final List<VigilReadingItem> initial;
  const _BulkVigilReadingsDialog({required this.initial});

  @override
  State<_BulkVigilReadingsDialog> createState() => _BulkVigilReadingsDialogState();
}

class _BulkVigilReadingsDialogState extends State<_BulkVigilReadingsDialog> {
  final List<TextEditingController> _readingCtrls = [];
  final List<TextEditingController> _psalmCtrls = [];
  // Preserved from the existing item when editing, so a response
  // entered earlier through the single-item dialog isn't silently
  // dropped just because this view doesn't show it.
  final List<String?> _existingResponses = [];

  @override
  void initState() {
    super.initState();
    for (final v in widget.initial) {
      _readingCtrls.add(TextEditingController(text: v.reading));
      _psalmCtrls.add(TextEditingController(text: v.psalm ?? ''));
      _existingResponses.add(v.psalmResponse);
    }
    if (_readingCtrls.isEmpty) _addRow();
  }

  void _addRow() {
    setState(() {
      _readingCtrls.add(TextEditingController());
      _psalmCtrls.add(TextEditingController());
      _existingResponses.add(null);
    });
  }

  void _removeRow(int i) {
    setState(() {
      _readingCtrls.removeAt(i);
      _psalmCtrls.removeAt(i);
      _existingResponses.removeAt(i);
    });
  }

  void _save() {
    final result = <VigilReadingItem>[];
    for (var i = 0; i < _readingCtrls.length; i++) {
      final reading = _readingCtrls[i].text.trim();
      if (reading.isEmpty) continue; // blank rows are skipped, not saved as empty entries
      result.add(VigilReadingItem(
        order: result.length,
        reading: reading,
        psalm: _psalmCtrls[i].text.trim().isEmpty ? null : _psalmCtrls[i].text.trim(),
        psalmResponse: _existingResponses[i],
      ));
    }
    Navigator.pop(context, result);
  }

  @override
  void dispose() {
    for (final c in _readingCtrls) {
      c.dispose();
    }
    for (final c in _psalmCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.paper,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vigil Readings', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
              const Text('Fill in as many rows as needed, then save once.', style: TextStyle(fontSize: 12, color: Colors.black45)),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < _readingCtrls.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 24,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Text('${i + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brass)),
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _readingCtrls[i],
                                  decoration: const InputDecoration(labelText: 'Reading', isDense: true),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _psalmCtrls[i],
                                  decoration: const InputDecoration(labelText: 'Psalm', isDense: true),
                                ),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.redAccent),
                                onPressed: () => _removeRow(i),
                              ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addRow,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Row'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                    onPressed: _save,
                    child: const Text('Save All'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}