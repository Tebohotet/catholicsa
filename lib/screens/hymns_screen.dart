import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/firestore_service.dart';
import '../providers/view_as_role_provider.dart';
import '../app.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_menu_button.dart';
import '../widgets/first_run_tips.dart';
import '../services/hymn_player_service.dart';

/// "Preview" here opens the PDF in the built-in PdfViewerScreen, so a
/// visitor stays inside the app instead of being handed off to the
/// browser's/device's own PDF viewer via url_launcher - see
/// pdf_viewer_screen.dart for why Syncfusion was the package chosen
/// (Web support, where this app actually lives, which flutter_pdfview
/// doesn't offer).
///
/// The browse button at the top mirrors the Bible screen's own book
/// picker (a searchable modal sheet) - the same "pick from the whole
/// list" pattern applied to hymns instead of books, alongside the
/// inline search field already on the page.
class HymnsScreen extends ConsumerStatefulWidget {
  const HymnsScreen({super.key});

  @override
  ConsumerState<HymnsScreen> createState() => _HymnsScreenState();
}

class _HymnsScreenState extends ConsumerState<HymnsScreen> with RouteAware {
  late Future<List<Map<String, dynamic>>> _hymnsFuture;
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _editMode = false;

  // First-run coach-mark targets - see first_run_tips.dart. Same pattern
  // as map_screen.dart's own tour, extended here per the project owner's
  // "Remove this carousel entirely" call (the small per-screen tours
  // replace the old 4-slide onboarding carousel).
  final _browseHymnsKey = GlobalKey();
  final _viewReadingsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _hymnsFuture = FirestoreService().getHymns();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showHymnsTips();
    });
  }

  void _showHymnsTips() {
    showFirstRunTips(context, prefsKey: 'tips_hymns_v1', steps: [
      TipStep(
        targetKey: _browseHymnsKey,
        title: 'Browse all hymns',
        message: 'Search the whole hymn list from here, instead of just the ones already on screen.',
      ),
      TipStep(
        targetKey: _viewReadingsKey,
        title: 'Readings',
        message: "Jumps straight to the Readings tab - the same place the bottom nav bar takes you.",
      ),
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) rootRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() => _refresh();

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() => setState(() { _hymnsFuture = FirestoreService().getHymns(); });

  void _preview(String pdfUrl, String title) {
    if (pdfUrl.isEmpty) return;
    // A real route (/hymns/pdf?...), not a plain Navigator.push - added
    // 2026-11-28 so refreshing while viewing a hymn's PDF keeps you
    // right here instead of resetting to About Us. See app.dart's router
    // config for where this path is actually built.
    context.push(Uri(path: '/hymns/pdf', queryParameters: {'url': pdfUrl, 'title': title}).toString());
  }

  void _showLyrics(String title, String lyrics) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text(title, style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: SingleChildScrollView(child: Text(lyrics, style: const TextStyle(fontSize: 14, height: 1.5))),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  /// Same searchable-modal-sheet pattern as the Bible screen's book
  /// picker - browse the whole list at once rather than only via the
  /// inline search field.
  Future<void> _showBrowsePicker(List<Map<String, dynamic>> allHymns) async {
    final searchCtrl = TextEditingController();
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? allHymns
              : allHymns.where((h) => (h['title'] as String? ?? '').toLowerCase().contains(query)).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Browse Hymns', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl, autofocus: true,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search hymns...'),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final h = filtered[i];
                        return ListTile(
                          title: Text(h['title'] ?? ''),
                          subtitle: Text(h['categoryLabel'] ?? '', style: const TextStyle(fontSize: 11)),
                          onTap: () => Navigator.pop(sheetContext, h),
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
      final isText = selected['fileType'] == 'text';
      if (isText) {
        _showLyrics(selected['title'] ?? '', selected['lyricsText'] ?? '');
      } else {
        _preview(selected['pdfUrl'] ?? '', selected['title'] ?? '');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same super-admin check the "Edit hymns" button already uses. The
    // original, un-converted PDF is admin-only: a regular user only ever
    // gets the instrumental audio (or lyrics text) - never a direct link
    // to the PDF itself.
    final isAdmin = ref.watch(isRealSuperAdminProvider).maybeWhen(data: (v) => v, orElse: () => false);
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
              child: Row(
                children: [
                  const Expanded(child: Text('Hymns', style: TextStyle(fontFamily: appSerif, fontSize: 26, color: Colors.white))),
                  if (isAdmin)
                    IconButton(
                      tooltip: _editMode ? 'Exit edit mode' : 'Edit hymns',
                      icon: Icon(_editMode ? Icons.edit : Icons.edit_outlined, color: _editMode ? AppColors.brass : Colors.white),
                      onPressed: () => setState(() => _editMode = !_editMode),
                    ),
                  // Same uniform-header ask as Readings' own "View Hymns"/
                  // "Browse the Bible" icons, mirrored here for symmetry -
                  // a real tab switch (go_router branch route), not a
                  // Navigator.push, for the same reason Readings' own
                  // "View Hymns" button was just fixed to do the same:
                  // ReadingsScreen is a bottom-nav tab root with no back
                  // arrow of its own, so pushing a second copy on top
                  // would be a dead end with no way back. A distinct icon
                  // from "Browse all hymns" below (also menu_book_outlined)
                  // so the two don't look identical in the same header.
                  IconButton(
                    key: _viewReadingsKey,
                    tooltip: 'View Readings',
                    icon: const Icon(Icons.today_outlined, color: Colors.white),
                    onPressed: () => context.go('/readings'),
                  ),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _hymnsFuture,
                    builder: (context, snap) => IconButton(
                      key: _browseHymnsKey,
                      tooltip: 'Browse all hymns',
                      icon: const Icon(Icons.menu_book_outlined, color: Colors.white),
                      onPressed: snap.data == null ? null : () => _showBrowsePicker(snap.data!),
                    ),
                  ),
                  const ProfileMenuButton(embedded: true),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(labelText: 'Search hymns', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _hymnsFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  var hymns = snap.data ?? [];
                  // Hidden hymns stay visible to an editor (so there's
                  // something to un-hide), but never to a regular user.
                  if (!_editMode) {
                    hymns = hymns.where((h) => h['hidden'] != true).toList();
                  }
                  if (_query.isNotEmpty) {
                    hymns = hymns.where((h) => (h['title'] as String? ?? '').toLowerCase().contains(_query)).toList();
                  }
                  if (hymns.isEmpty) {
                    return const Center(child: Text('No hymns found.', style: TextStyle(fontSize: 13, color: Colors.black45)));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: hymns.length,
                    itemBuilder: (context, i) {
                      final h = hymns[i];
                      final isText = h['fileType'] == 'text';
                      final hasAudio = h['hasAudio'] == true && (h['audioUrl'] as String? ?? '').isNotEmpty;
                      final isHidden = h['hidden'] == true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: AppColors.paperDark,
                        elevation: 0,
                        child: ListTile(
                          leading: Opacity(
                            opacity: isHidden ? 0.4 : 1,
                            child: const Icon(Icons.library_music_outlined, color: AppColors.brass),
                          ),
                          title: Text(h['title'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isHidden ? Colors.black45 : null)),
                          subtitle: Text(
                            isHidden ? '${h['categoryLabel'] ?? ''} · HIDDEN' : h['categoryLabel'] ?? '',
                            style: TextStyle(fontSize: 11, color: isHidden ? Colors.redAccent : Colors.black54),
                          ),
                          trailing: _editMode
                              ? const Icon(Icons.edit, size: 18, color: AppColors.brass)
                              : Icon(
                                  hasAudio ? Icons.play_circle_outline : (isText ? Icons.article_outlined : Icons.picture_as_pdf_outlined),
                                  size: 20, color: hasAudio ? AppColors.brass : Colors.black45,
                                ),
                          onTap: () {
                            if (_editMode) {
                              showDialog(context: context, builder: (_) => _EditHymnDialog(hymn: h, onDone: _refresh));
                            } else if (hasAudio) {
                              // Audio takes priority the moment it exists - a
                              // regular user never reaches the raw PDF link
                              // for a converted hymn at all, which is the
                              // actual protection: the PDF simply isn't
                              // offered as an option here anymore.
                              showDialog(context: context, builder: (_) => _HymnAudioPlayerDialog(
                                title: h['title'] ?? '',
                                audioUrl: h['audioUrl'],
                                pdfUrl: isAdmin ? (h['pdfUrl'] as String? ?? '') : null,
                              ));
                            } else if (isText) {
                              _showLyrics(h['title'] ?? '', h['lyricsText'] ?? '');
                            } else {
                              _preview(h['pdfUrl'] ?? '', h['title'] ?? '');
                            }
                          },
                        ),
                      );
                    },
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

class _EditHymnDialog extends StatefulWidget {
  final Map<String, dynamic> hymn;
  final VoidCallback onDone;
  const _EditHymnDialog({required this.hymn, required this.onDone});

  @override
  State<_EditHymnDialog> createState() => _EditHymnDialogState();
}

class _EditHymnDialogState extends State<_EditHymnDialog> {
  late TextEditingController _titleCtrl;
  bool _hidden = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.hymn['title'] ?? '');
    _hidden = widget.hymn['hidden'] == true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; });
    try {
      final id = widget.hymn['id'] as String;
      if (_titleCtrl.text.trim().isNotEmpty && _titleCtrl.text.trim() != widget.hymn['title']) {
        await FirestoreService().updateHymn(id, {'title': _titleCtrl.text.trim()});
      }
      if (_hidden != (widget.hymn['hidden'] == true)) {
        await FirestoreService().setHymnHidden(id, _hidden);
      }
      if (mounted) Navigator.pop(context);
      widget.onDone();
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = widget.hymn['hasAudio'] == true;
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('Edit Hymn', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.brass,
              title: const Text('Hide from Hymns list', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Keeps the hymn saved - just stops it showing to regular users.', style: TextStyle(fontSize: 11, color: Colors.black45)),
              value: _hidden,
              onChanged: (v) => setState(() => _hidden = v),
            ),
            if (hasAudio) ...[
              const Divider(height: 24),
              const Row(children: [
                Icon(Icons.check_circle, size: 16, color: AppColors.sage),
                SizedBox(width: 6),
                Text('Audio has been generated for this hymn.', style: TextStyle(fontSize: 12)),
              ]),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Plays the real, converted audio (WAV, produced server-side by the
/// PDF -> Audiveris -> MusicXML -> MIDI -> FluidSynth pipeline) - a
/// regular user never touches the original PDF at all through this path.
/// [pdfUrl] is only ever passed in for an admin (see the isAdmin check at
/// the call site above), so the "View PDF" button only renders for them.
class _HymnAudioPlayerDialog extends StatefulWidget {
  final String title;
  final String audioUrl;
  final String? pdfUrl;
  const _HymnAudioPlayerDialog({required this.title, required this.audioUrl, this.pdfUrl});

  @override
  State<_HymnAudioPlayerDialog> createState() => _HymnAudioPlayerDialogState();
}

class _HymnAudioPlayerDialogState extends State<_HymnAudioPlayerDialog> {
  // Not this dialog's own player any more - HymnPlayerService.instance is
  // one shared, app-wide player (see that file's doc comment for why).
  // This dialog is now just a UI on top of whatever it's doing - closing
  // it does NOT stop playback any more, same as minimizing a music app
  // rather than quitting it. Stopping it is what the mini-player bar's
  // own close (X) button is for (see HomeScreen's bottomNavigationBar).
  final _player = HymnPlayerService.instance;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onChange);
    _player.play(title: widget.title, audioUrl: widget.audioUrl, pdfUrl: widget.pdfUrl);
  }

  void _onChange() { if (mounted) setState(() {}); }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _player.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text(widget.title, style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
      content: SizedBox(
        width: 360,
        child: _player.error != null
            ? Text(_player.error!, style: const TextStyle(fontSize: 13, color: Colors.redAccent))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    activeColor: AppColors.brass,
                    min: 0,
                    max: _player.duration.inMilliseconds > 0 ? _player.duration.inMilliseconds.toDouble() : 1,
                    value: _player.position.inMilliseconds.toDouble().clamp(0, _player.duration.inMilliseconds > 0 ? _player.duration.inMilliseconds.toDouble() : 1),
                    onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_player.position), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        Text(_formatDuration(_player.duration), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    iconSize: 48,
                    color: AppColors.brass,
                    icon: Icon(_player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    onPressed: _player.togglePlayPause,
                  ),
                ],
              ),
      ),
      actions: [
        if (widget.pdfUrl != null && widget.pdfUrl!.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('View PDF'),
            onPressed: () {
              context.push(Uri(path: '/hymns/pdf', queryParameters: {'url': widget.pdfUrl!, 'title': widget.title}).toString());
            },
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}