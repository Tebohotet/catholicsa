import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/firestore_service.dart';
import '../providers/view_as_role_provider.dart';
import '../app.dart';
import '../theme/app_theme.dart';

/// "Preview" here opens the real PDF in the browser's (or device's)
/// native PDF viewer via url_launcher - a genuinely good preview
/// experience with zero new rendering dependency, rather than an
/// embedded in-app PDF widget that would need separate, unverified
/// support across both web and Android.
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

  @override
  void initState() {
    super.initState();
    _hymnsFuture = FirestoreService().getHymns();
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

  Future<void> _preview(String pdfUrl, String title) async {
    final uri = Uri.parse(pdfUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open "$title".')));
    }
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
                  Consumer(
                    builder: (context, ref, _) {
                      final isSuperAdminAsync = ref.watch(isRealSuperAdminProvider);
                      final isSuperAdmin = isSuperAdminAsync.maybeWhen(data: (v) => v, orElse: () => false);
                      if (!isSuperAdmin) return const SizedBox.shrink();
                      return IconButton(
                        tooltip: _editMode ? 'Exit edit mode' : 'Edit hymns',
                        icon: Icon(_editMode ? Icons.edit : Icons.edit_outlined, color: _editMode ? AppColors.brass : Colors.white),
                        onPressed: () => setState(() => _editMode = !_editMode),
                      );
                    },
                  ),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _hymnsFuture,
                    builder: (context, snap) => IconButton(
                      tooltip: 'Browse all hymns',
                      icon: const Icon(Icons.menu_book_outlined, color: Colors.white),
                      onPressed: snap.data == null ? null : () => _showBrowsePicker(snap.data!),
                    ),
                  ),
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
                              showDialog(context: context, builder: (_) => _HymnAudioPlayerDialog(title: h['title'] ?? '', audioUrl: h['audioUrl']));
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
/// PDF -> Audiveris -> MusicXML -> MIDI -> FluidSynth pipeline) - the
/// user never touches the original PDF at all through this path, which
/// is the actual point of the whole conversion pipeline.
class _HymnAudioPlayerDialog extends StatefulWidget {
  final String title;
  final String audioUrl;
  const _HymnAudioPlayerDialog({required this.title, required this.audioUrl});

  @override
  State<_HymnAudioPlayerDialog> createState() => _HymnAudioPlayerDialogState();
}

class _HymnAudioPlayerDialogState extends State<_HymnAudioPlayerDialog> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) { if (mounted) setState(() => _state = s); });
    _player.onPositionChanged.listen((p) { if (mounted) setState(() => _position = p); });
    _player.onDurationChanged.listen((d) { if (mounted) setState(() => _duration = d); });
    _start();
  }

  Future<void> _start() async {
    try {
      await _player.play(UrlSource(widget.audioUrl));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not play this hymn: $e');
    }
  }

  Future<void> _togglePlayPause() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text(widget.title, style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
      content: SizedBox(
        width: 360,
        child: _error != null
            ? Text(_error!, style: const TextStyle(fontSize: 13, color: Colors.redAccent))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    activeColor: AppColors.brass,
                    min: 0,
                    max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1,
                    value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1),
                    onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_position), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        Text(_formatDuration(_duration), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    iconSize: 48,
                    color: AppColors.brass,
                    icon: Icon(_state == PlayerState.playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    onPressed: _togglePlayPause,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () { _player.stop(); Navigator.pop(context); },
          child: const Text('Close'),
        ),
      ],
    );
  }
}