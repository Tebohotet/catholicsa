import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../services/firestore_service.dart';
import '../services/engagement_service.dart';
import '../providers/page_diagnostics_provider.dart';
import '../theme/app_theme.dart';
import '../utils/bible_citation_parser.dart';
import '../widgets/share_button.dart';

/// Works two ways now - opened from a reading citation (book/chapter
/// parsed automatically, verses highlighted), or opened directly with no
/// citation at all for genuine standalone browsing (pick a book, pick a
/// chapter). Same screen, same data, just a different starting point.
class BibleScreen extends StatefulWidget {
  final String? citation;
  final String? label;
  const BibleScreen({super.key, this.citation, this.label});

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  List<Map<String, dynamic>> _manifestBooks = [];
  ParsedCitation? _parsed;
  String? _selectedBookCode;
  String? _selectedBookName;
  int? _selectedChapter;
  String? _selectedTranslation;
  Future<List<Map<String, dynamic>>>? _translationsFuture;
  Future<Map<String, dynamic>?>? _chapterFuture;

  bool get _isBrowseMode => widget.citation == null;

  @override
  void initState() {
    super.initState();
    _init();
    registerPageDiagnostics('Bible', [
      TestCase('getBibleTranslations', () => FirestoreService().getBibleTranslations()),
      TestCase('searchBibleVerses (test query)', () async {
        final translations = await FirestoreService().getBibleTranslations();
        if (translations.isEmpty) return 'No translations exist yet - nothing to search';
        return FirestoreService().searchBibleVerses(translationCode: translations.first['id'], query: 'god');
      }),
    ]);
  }

  Future<void> _init() async {
    final raw = await rootBundle.loadString('assets/bible/manifest.json');
    final manifest = json.decode(raw) as Map<String, dynamic>;
    final books = (manifest['books'] as List).cast<Map<String, dynamic>>();
    if (BibleCitationParser.booksLoaded == false) BibleCitationParser.loadBooks(books);
    if (!mounted) return;
    setState(() {
      _manifestBooks = books;
      _translationsFuture = FirestoreService().getBibleTranslations();
    });

    if (widget.citation != null) {
      final parsed = BibleCitationParser.parse(widget.citation!);
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        if (parsed != null) { _selectedBookCode = parsed.bookCode; _selectedChapter = parsed.chapter; }
      });
    }

    final translations = await FirestoreService().getBibleTranslations();
    if (translations.isEmpty || !mounted) return;
    final preferred = translations.firstWhere((t) => t['id'] == 'douayRheims', orElse: () => translations.first);
    setState(() => _selectedTranslation = preferred['id'] as String?);
    if (_selectedBookCode != null && _selectedChapter != null) _loadChapter();
  }

  int? get _chapterCountForSelectedBook {
    if (_selectedBookCode == null) return null;
    final book = _manifestBooks.firstWhere((b) => b['code'] == _selectedBookCode, orElse: () => {});
    return book['chapters'] as int?;
  }

  void _loadChapter() {
    if (_selectedBookCode == null || _selectedChapter == null || _selectedTranslation == null) return;
    _chapterFuture = FirestoreService().getBibleChapter(
      translationCode: _selectedTranslation!,
      bookCode: _selectedBookCode!,
      chapter: _selectedChapter!,
    );
    _checkBookmarkStatus();
    EngagementService().recordActivity('bibleChapterRead');
  }

  bool _bookmarked = false;

  Future<void> _checkBookmarkStatus() async {
    if (_selectedBookCode == null || _selectedChapter == null || _selectedTranslation == null) return;
    final result = await FirestoreService().isBibleBookmarked(_selectedTranslation!, _selectedBookCode!, _selectedChapter!);
    if (mounted) setState(() => _bookmarked = result);
  }

  Future<void> _toggleBookmark() async {
    if (_selectedBookCode == null || _selectedChapter == null || _selectedTranslation == null) return;
    final bookName = _selectedBookName ?? _parsed?.bookName ?? _manifestBooks.firstWhere((b) => b['code'] == _selectedBookCode, orElse: () => {'name': ''})['name'];
    if (_bookmarked) {
      await FirestoreService().removeBibleBookmark(_selectedTranslation!, _selectedBookCode!, _selectedChapter!);
    } else {
      await FirestoreService().addBibleBookmark(
        translationCode: _selectedTranslation!, bookCode: _selectedBookCode!, bookName: bookName ?? '', chapter: _selectedChapter!,
      );
    }
    if (mounted) setState(() => _bookmarked = !_bookmarked);
  }

  Future<void> _showSearch() async {
    if (_selectedTranslation == null) return;
    final searchCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<Map<String, dynamic>>? searchFuture;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Search Scripture', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
                  const SizedBox(height: 4),
                  const Text('Searches whatever\'s actually been added for this translation so far.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl, autofocus: true,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'e.g. shepherd'),
                    onSubmitted: (v) => setSheetState(() => searchFuture = FirestoreService().searchBibleVerses(translationCode: _selectedTranslation!, query: v)),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                    child: searchFuture == null
                        ? const SizedBox.shrink()
                        : FutureBuilder<Map<String, dynamic>>(
                            future: searchFuture,
                            builder: (context, snap) {
                              if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator()));
                              final results = List<Map<String, dynamic>>.from(snap.data?['results'] ?? []);
                              if (results.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('No matches found in what\'s populated so far.', style: TextStyle(fontSize: 13, color: Colors.black54)));
                              return ListView.builder(
                                shrinkWrap: true,
                                itemCount: results.length,
                                itemBuilder: (context, i) {
                                  final r = results[i];
                                  final bookName = _manifestBooks.firstWhere((b) => b['code'] == r['bookCode'], orElse: () => {'name': r['bookCode']})['name'];
                                  return ListTile(
                                    title: Text('$bookName ${r['chapter']}:${r['verse']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    subtitle: Text(r['text'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                    onTap: () {
                                      Navigator.pop(sheetContext);
                                      setState(() {
                                        _selectedBookCode = r['bookCode'];
                                        _selectedBookName = bookName;
                                        _selectedChapter = r['chapter'];
                                        _loadChapter();
                                      });
                                    },
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showBookPicker() async {
    final searchCtrl = TextEditingController();
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? _manifestBooks
              : _manifestBooks.where((b) => (b['name'] as String).toLowerCase().contains(query)).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choose a book', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl, autofocus: true,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search books...'),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final b = filtered[i];
                        return ListTile(
                          title: Text(b['name'] ?? ''),
                          subtitle: Text(b['testament'] == 'OT' ? 'Old Testament' : 'New Testament', style: const TextStyle(fontSize: 11)),
                          onTap: () => Navigator.pop(sheetContext, b),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (selected != null) {
      setState(() {
        _selectedBookCode = selected['code'] as String;
        _selectedBookName = selected['name'] as String;
        _selectedChapter = null;
        _chapterFuture = null;
      });
    }
  }

  Future<void> _showTranslationSearch(List<Map<String, dynamic>> translations) async {
    final searchCtrl = TextEditingController();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? translations
              : translations.where((t) => (t['name'] as String? ?? '').toLowerCase().contains(query)).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choose a translation', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search translations...'),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text('No translations match that search.', style: TextStyle(fontSize: 13, color: Colors.black54)),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final t = filtered[i];
                              return ListTile(
                                title: Text(t['name'] ?? ''),
                                subtitle: t['isPublicDomain'] == true ? const Text('Public domain', style: TextStyle(fontSize: 11, color: AppColors.sage)) : null,
                                trailing: t['id'] == _selectedTranslation ? const Icon(Icons.check, color: AppColors.brass) : null,
                                onTap: () => Navigator.pop(sheetContext, t['id'] as String),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (selected != null) setState(() { _selectedTranslation = selected; _loadChapter(); });
  }

  @override
  Widget build(BuildContext context) {
    final headerLabel = widget.label ?? 'Bible';
    final headerTitle = widget.citation ?? (_selectedBookName != null && _selectedChapter != null ? '$_selectedBookName $_selectedChapter' : 'Browse Scripture');

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
                        Text(headerLabel, style: const TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 0.4)),
                        Text(headerTitle, style: const TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                      ],
                    ),
                  ),
                  if (_selectedBookCode != null && _selectedChapter != null && _selectedTranslation != null)
                    IconButton(
                      icon: Icon(_bookmarked ? Icons.bookmark : Icons.bookmark_border, color: Colors.white),
                      tooltip: _bookmarked ? 'Remove bookmark' : 'Bookmark this chapter',
                      onPressed: _toggleBookmark,
                    ),
                  if (_selectedTranslation != null)
                    IconButton(
                      icon: const Icon(Icons.search, color: Colors.white),
                      tooltip: 'Search scripture',
                      onPressed: _showSearch,
                    ),
                ],
              ),
            ),
            if (_isBrowseMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                        onPressed: _showBookPicker,
                        icon: const Icon(Icons.menu_book_outlined, size: 16),
                        label: Text(_selectedBookName ?? 'Choose a book', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_chapterCountForSelectedBook != null)
                      Expanded(
                        child: DropdownButton<int>(
                          value: _selectedChapter,
                          isExpanded: true,
                          hint: const Text('Ch.', style: TextStyle(fontSize: 13)),
                          items: List.generate(_chapterCountForSelectedBook!, (i) => i + 1).map((c) => DropdownMenuItem(value: c, child: Text('$c'))).toList(),
                          onChanged: (v) => setState(() { _selectedChapter = v; _loadChapter(); }),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _translationsFuture,
                builder: (context, snap) {
                  final translations = snap.data ?? [];
                  if (translations.isEmpty) return const SizedBox.shrink();
                  final selectedName = translations.firstWhere(
                    (t) => t['id'] == _selectedTranslation,
                    orElse: () => {'name': 'Select a translation'},
                  )['name'];
                  return InkWell(
                    onTap: () => _showTranslationSearch(translations),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 18, color: Colors.black45),
                          const SizedBox(width: 8),
                          Expanded(child: Text(selectedName, style: const TextStyle(fontSize: 14))),
                          const Icon(Icons.arrow_drop_down, color: Colors.black45),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: (_selectedBookCode == null || _selectedChapter == null)
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _isBrowseMode
                            ? 'Choose a book and chapter above to start reading.'
                            : 'This citation couldn\'t be matched to a specific book and chapter automatically - the citation text is shown above, but the full passage isn\'t available here yet.',
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                    )
                  : FutureBuilder<Map<String, dynamic>?>(
                      future: _chapterFuture,
                      builder: (context, snap) {
                        if (_selectedTranslation == null || snap.connectionState != ConnectionState.done) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final data = snap.data;
                        if (data == null) {
                          return Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '${_selectedBookName ?? _parsed?.bookName ?? ''} chapter $_selectedChapter hasn\'t been added for this translation yet.',
                              style: const TextStyle(fontSize: 14, color: Colors.black54),
                            ),
                          );
                        }
                        final verses = Map<String, String>.from(data['verses'] ?? {});
                        final sortedKeys = verses.keys.toList()..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
                        final fullText = sortedKeys.map((k) => '$k ${verses[k]}').join(' ');
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Align(alignment: Alignment.centerRight, child: ShareButton(title: headerTitle, body: fullText)),
                              const SizedBox(height: 8),
                              ...sortedKeys.map((k) {
                                final verseNum = int.tryParse(k) ?? 0;
                                final isHighlighted = _parsed?.startVerse != null &&
                                    verseNum >= _parsed!.startVerse! &&
                                    verseNum <= (_parsed!.endVerse ?? _parsed!.startVerse!);
                                return Container(
                                  color: isHighlighted ? AppColors.brass.withValues(alpha: 0.12) : null,
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: RichText(
                                    text: TextSpan(
                                      style: const TextStyle(fontSize: 17, color: Colors.black87, height: 1.6),
                                      children: [
                                        TextSpan(text: '$k ', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brass)),
                                        TextSpan(text: verses[k]),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              _CrossReferencesBlock(bookCode: _selectedBookCode!, chapter: _selectedChapter!, manifestBooks: _manifestBooks),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows nothing at all when no cross-references exist for this
/// chapter, rather than an empty "Related Passages" heading - most
/// chapters won't have any curated yet, and an empty section header
/// would look like a bug rather than an honest absence of content.
class _CrossReferencesBlock extends StatelessWidget {
  final String bookCode;
  final int chapter;
  final List<Map<String, dynamic>> manifestBooks;
  const _CrossReferencesBlock({required this.bookCode, required this.chapter, required this.manifestBooks});

  String _bookName(String? code) => manifestBooks.firstWhere((b) => b['code'] == code, orElse: () => {'name': code ?? ''})['name'];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: FirestoreService().getCrossReferencesForChapter(bookCode, chapter),
      builder: (context, snap) {
        final refs = snap.data ?? [];
        if (refs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Related Passages', style: TextStyle(fontFamily: appSerif, fontSize: 15)),
              const SizedBox(height: 6),
              ...refs.map((r) {
                final isFrom = r['direction'] == 'to';
                final otherBook = isFrom ? r['toBookCode'] : r['fromBookCode'];
                final otherChapter = isFrom ? r['toChapter'] : r['fromChapter'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => BibleScreen(citation: '${_bookName(otherBook)} $otherChapter:1', label: 'Related Passage'),
                    )),
                    child: Row(
                      children: [
                        const Icon(Icons.link, size: 14, color: AppColors.brass),
                        const SizedBox(width: 6),
                        Text('${_bookName(otherBook)} $otherChapter', style: const TextStyle(fontSize: 13, color: AppColors.brass, decoration: TextDecoration.underline)),
                        if (r['note'] != null) Expanded(child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(r['note'], style: const TextStyle(fontSize: 12, color: Colors.black54), overflow: TextOverflow.ellipsis))),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}