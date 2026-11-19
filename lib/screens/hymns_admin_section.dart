import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';
import '../services/hymn_conversion_service.dart';
import '../theme/app_theme.dart';

/// Imports the verified CMAA hymn list (title + real PDF link, bundled
/// as assets/hymns/cmaa_hymns.json) into Firestore. Deliberately not a
/// live scrape of CMAA's page - that would mean guessing at HTML
/// structure never directly verified, the exact mistake this session's
/// Bible sync made repeatedly before switching to real diagnostics.
/// This data was transcribed directly from the actual page content
/// instead.
///
/// Re-hosting and manual-add are separate, later steps - "I want the
/// PDF, not a link" meant the imported CMAA docs originally pointed at
/// an external host; rehostHymnPdfs pulls each real PDF into this
/// project's own Storage. Manually adding a hymn afterward supports
/// either an uploaded PDF or plain typed lyrics, for hymns that don't
/// come from CMAA at all.
class HymnsAdminSection extends StatefulWidget {
  const HymnsAdminSection({super.key});

  @override
  State<HymnsAdminSection> createState() => _HymnsAdminSectionState();
}

class _HymnsAdminSectionState extends State<HymnsAdminSection> {
  bool _importing = false;
  String? _importResult;
  bool _rehosting = false;
  String? _rehostResult;
  bool _showAddForm = false;
  Future<List<Map<String, dynamic>>>? _hymnsFuture;

  // Windows-only conversion feature - kIsWeb/defaultTargetPlatform are
  // both safe to check on every platform (they come from foundation.dart,
  // not dart:io), so this check itself never breaks the web build even
  // though the feature it gates does.
  bool get _isWindowsDesktop => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  // Real, confirmed need: these three paths are specific to whatever's
  // actually installed on this one admin PC - the hardcoded fallbacks
  // below are only a best guess (and were wrong for both Audiveris and
  // FluidSynth the first time this was tried for real), so once
  // someone has typed in the paths that actually work here, they
  // should stick - not revert to the guess every time the app
  // restarts. Persisted locally (SharedPreferences, this machine
  // only), loaded in initState, saved on every edit.
  static const _kAudiverisPathPref = 'hymnOmrAudiverisPath';
  static const _kFluidsynthPathPref = 'hymnOmrFluidsynthPath';
  static const _kSoundfontPathPref = 'hymnOmrSoundfontPath';
  static const _kTempoPref = 'hymnOmrTempoBpm';
  static const _kInstrumentPref = 'hymnOmrInstrumentProgram';
  static const _kRepeatPref = 'hymnOmrRepeatCount';

  final _audiverisPathCtrl = TextEditingController(text: r'C:\Program Files\Audiveris\bin\Audiveris.exe');
  final _fluidsynthPathCtrl = TextEditingController(text: r'C:\Program Files\FluidSynth\bin\fluidsynth.exe');
  final _soundfontPathCtrl = TextEditingController();
  String? _convertingHymnId;
  List<String> _lastConversionLog = [];
  String? _lastConversionError;

  // Real, confirmed gaps found after the first real conversions: a
  // fixed 120 BPM (hymns are usually sung much slower than that, and
  // Audiveris essentially never recognizes a printed tempo marking to
  // use instead), a generic default instrument (no program-change was
  // ever written, so FluidSynth just falls back to whatever program 0
  // is on the soundfont - not organ, not voices, not whatever
  // Audiveris itself guessed in the MusicXML), and only ever playing
  // one pass through the tune (a short, correct render of a hymn
  // still sounds "too short" next to the real multi-verse hymn it's
  // being compared to). All three are now adjustable here rather than
  // guessed once in code, and persist the same way the three tool
  // paths above do.
  final _tempoCtrl = TextEditingController(text: '84');
  final _repeatCtrl = TextEditingController(text: '1');
  int _instrumentProgram = 18; // General MIDI program 19 "Church Organ", 0-indexed

  // A short, named subset of General MIDI programs relevant to hymns -
  // not the full list of 128, which would be unwieldy and mostly
  // irrelevant here. Values are 0-indexed (raw MIDI program-change
  // byte), one less than GM's usual 1-128 numbering.
  static const _instrumentOptions = {
    18: 'Church Organ',
    0: 'Acoustic Grand Piano',
    52: 'Choir Aahs',
    53: 'Voice Oohs',
    73: 'Flute',
  };

  // Lets an already-converted hymn be played right from this screen,
  // next to its Convert/Re-convert button, without re-running the
  // whole OMR pipeline just to hear it again. Keyed by hymn id;
  // populated right after a successful conversion, and also probed
  // from disk on load so a hymn converted in an earlier session still
  // shows a Play button after an app restart.
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, String> _localAudioPaths = {};
  final Set<String> _hasSavedMxl = {};
  String? _playingHymnId;
  // Separate from _convertingHymnId so a full Convert/Re-convert and a
  // quick Re-render audio can each show their own spinner and disable
  // only their own button, not the other one too.
  String? _rerenderingHymnId;

  @override
  void initState() {
    super.initState();
    _hymnsFuture = _loadHymnsAndProbeAudio();
    _loadSavedOmrPaths();
    _audiverisPathCtrl.addListener(() => _saveOmrPath(_kAudiverisPathPref, _audiverisPathCtrl.text));
    _fluidsynthPathCtrl.addListener(() => _saveOmrPath(_kFluidsynthPathPref, _fluidsynthPathCtrl.text));
    _soundfontPathCtrl.addListener(() => _saveOmrPath(_kSoundfontPathPref, _soundfontPathCtrl.text));
    _tempoCtrl.addListener(() => _saveOmrPath(_kTempoPref, _tempoCtrl.text));
    _repeatCtrl.addListener(() => _saveOmrPath(_kRepeatPref, _repeatCtrl.text));
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingHymnId = null);
    });
  }

  Future<List<Map<String, dynamic>>> _loadHymnsAndProbeAudio() async {
    final hymns = await FirestoreService().getHymns();
    if (_isWindowsDesktop) {
      for (final h in hymns) {
        final id = h['id'] as String;
        final path = await HymnConversionService.localAudioPathIfExists(id);
        if (path != null) _localAudioPaths[id] = path;
        if (await HymnConversionService.hasSavedMxl(id)) _hasSavedMxl.add(id);
      }
    }
    return hymns;
  }

  Future<void> _togglePlay(String hymnId, String path) async {
    if (_playingHymnId == hymnId) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingHymnId = null);
      return;
    }
    await _audioPlayer.stop();
    setState(() => _playingHymnId = hymnId);
    await _audioPlayer.play(DeviceFileSource(path));
  }

  Future<void> _loadSavedOmrPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final audiveris = prefs.getString(_kAudiverisPathPref);
    final fluidsynth = prefs.getString(_kFluidsynthPathPref);
    final soundfont = prefs.getString(_kSoundfontPathPref);
    final tempo = prefs.getString(_kTempoPref);
    final repeat = prefs.getString(_kRepeatPref);
    final instrument = prefs.getInt(_kInstrumentPref);
    if (!mounted) return;
    if (audiveris != null && audiveris.isNotEmpty) _audiverisPathCtrl.text = audiveris;
    if (fluidsynth != null && fluidsynth.isNotEmpty) _fluidsynthPathCtrl.text = fluidsynth;
    if (soundfont != null && soundfont.isNotEmpty) _soundfontPathCtrl.text = soundfont;
    if (tempo != null && tempo.isNotEmpty) _tempoCtrl.text = tempo;
    if (repeat != null && repeat.isNotEmpty) _repeatCtrl.text = repeat;
    if (instrument != null && _instrumentOptions.containsKey(instrument)) {
      setState(() => _instrumentProgram = instrument);
    }
  }

  Future<void> _saveOmrPath(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _setInstrument(int program) async {
    setState(() => _instrumentProgram = program);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kInstrumentPref, program);
  }

  void _refresh() => setState(() { _hymnsFuture = _loadHymnsAndProbeAudio(); });

  Future<void> _convertHymn(Map<String, dynamic> hymn) async {
    if (_soundfontPathCtrl.text.trim().isEmpty) {
      setState(() { _lastConversionError = 'Set a soundfont (.sf2) path first.'; });
      return;
    }
    final id = hymn['id'] as String;
    setState(() { _convertingHymnId = id; _lastConversionLog = []; _lastConversionError = null; });
    try {
      final pdfBytes = await HymnConversionService.downloadPdf(hymn['pdfUrl'], id);
      final service = HymnConversionService(
        audiverisPath: _audiverisPathCtrl.text.trim(),
        fluidsynthPath: _fluidsynthPathCtrl.text.trim(),
        soundfontPath: _soundfontPathCtrl.text.trim(),
      );
      final bpm = int.tryParse(_tempoCtrl.text.trim()) ?? 84;
      final repeatCount = int.tryParse(_repeatCtrl.text.trim()) ?? 1;
      final result = await service.convert(
        hymnId: id,
        pdfBytes: pdfBytes,
        bpm: bpm,
        instrumentProgram: _instrumentProgram,
        repeatCount: repeatCount,
      );
      setState(() {
        _lastConversionLog = result.log;
        _lastConversionError = result.success ? null : (result.error ?? 'Conversion failed.');
        if (result.success && result.localWavPath != null) {
          _localAudioPaths[id] = result.localWavPath!;
        }
      });
      if (result.success) _refresh();
    } catch (e) {
      setState(() { _lastConversionError = e.toString(); });
    } finally {
      if (mounted) setState(() { _convertingHymnId = null; });
    }
  }

  /// Re-renders a hymn's audio from the MusicXML already saved by a
  /// previous Convert/Re-convert, instead of re-running Audiveris (the
  /// slow step) just to try a different tempo/instrument/repeat count
  /// on notes that were already recognized correctly.
  Future<void> _rerenderHymn(Map<String, dynamic> hymn) async {
    if (_soundfontPathCtrl.text.trim().isEmpty) {
      setState(() { _lastConversionError = 'Set a soundfont (.sf2) path first.'; });
      return;
    }
    final id = hymn['id'] as String;
    setState(() { _rerenderingHymnId = id; _lastConversionLog = []; _lastConversionError = null; });
    try {
      final service = HymnConversionService(
        audiverisPath: _audiverisPathCtrl.text.trim(),
        fluidsynthPath: _fluidsynthPathCtrl.text.trim(),
        soundfontPath: _soundfontPathCtrl.text.trim(),
      );
      final bpm = int.tryParse(_tempoCtrl.text.trim()) ?? 84;
      final repeatCount = int.tryParse(_repeatCtrl.text.trim()) ?? 1;
      final result = await service.rerenderFromSavedMxl(
        hymnId: id,
        bpm: bpm,
        instrumentProgram: _instrumentProgram,
        repeatCount: repeatCount,
      );
      setState(() {
        _lastConversionLog = result.log;
        _lastConversionError = result.success ? null : (result.error ?? 'Re-render failed.');
        if (result.success && result.localWavPath != null) {
          _localAudioPaths[id] = result.localWavPath!;
        }
      });
      if (result.success) _refresh();
    } catch (e) {
      setState(() { _lastConversionError = e.toString(); });
    } finally {
      if (mounted) setState(() { _rerenderingHymnId = null; });
    }
  }

  Widget _buildWindowsConversionSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: AppColors.paperDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Convert to Audio (Windows only)', style: TextStyle(fontFamily: appSerif, fontSize: 14)),
          const Text(
            'Runs locally on this PC - PDF -> Audiveris -> MusicXML -> MIDI -> FluidSynth -> WAV. Both tools must already be installed here; this only shells out to them. Only visible when this app is actually running as a native Windows build.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
          const Text(
            'Once a hymn has been converted at least once, "Re-render audio" skips the slow Audiveris scan and just re-applies the tempo/instrument/repeat settings above to the notes already recognized - use it to quickly try different settings. Use Convert/Re-convert instead when the PDF itself changed, or the notes were misread the first time.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
          const SizedBox(height: 8),
          TextField(controller: _audiverisPathCtrl, decoration: const InputDecoration(labelText: 'Audiveris.exe path', isDense: true)),
          const SizedBox(height: 6),
          TextField(controller: _fluidsynthPathCtrl, decoration: const InputDecoration(labelText: 'fluidsynth.exe path', isDense: true)),
          const SizedBox(height: 6),
          TextField(controller: _soundfontPathCtrl, decoration: const InputDecoration(labelText: 'Soundfont (.sf2) path', isDense: true)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _tempoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tempo (BPM)', isDense: true, helperText: 'Hymns are usually slower than the 120 default most music software assumes.'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _instrumentProgram,
                  decoration: const InputDecoration(labelText: 'Instrument', isDense: true),
                  items: _instrumentOptions.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) { if (v != null) _setInstrument(v); },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _repeatCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Repeat (verses)', isDense: true, helperText: 'Loops the recognized tune this many times.'),
                ),
              ),
            ],
          ),
          if (_lastConversionError != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_lastConversionError!, style: const TextStyle(fontSize: 12, color: Colors.redAccent))),
          if (_lastConversionLog.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              color: Colors.black87,
              width: double.infinity,
              child: Text(_lastConversionLog.join('\n'), style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace')),
            ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _hymnsFuture,
            builder: (context, snap) {
              final hymns = (snap.data ?? []).where((h) => (h['pdfUrl'] as String? ?? '').isNotEmpty).toList();
              if (hymns.isEmpty) return const SizedBox.shrink();
              return Column(
                children: hymns.map((h) {
                  final id = h['id'] as String;
                  final hasAudio = h['hasAudio'] == true;
                  final isConverting = _convertingHymnId == id;
                  final isRerendering = _rerenderingHymnId == id;
                  final canRerender = _hasSavedMxl.contains(id);
                  final localPath = _localAudioPaths[id];
                  final isPlaying = _playingHymnId == id;
                  final pdfUrl = h['pdfUrl'] as String? ?? '';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(h['title'] ?? '', style: const TextStyle(fontSize: 13)),
                    subtitle: Text(hasAudio ? 'Audio already generated' : 'Not yet converted', style: const TextStyle(fontSize: 11)),
                    trailing: (isConverting || isRerendering)
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (pdfUrl.isNotEmpty) ...[
                                IconButton(
                                  tooltip: 'View original PDF - open it alongside Play to check the audio against the actual sheet music',
                                  icon: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.stone),
                                  onPressed: () => launchUrl(Uri.parse(pdfUrl), mode: LaunchMode.externalApplication),
                                ),
                                const SizedBox(width: 4),
                              ],
                              if (localPath != null) ...[
                                IconButton(
                                  tooltip: isPlaying ? 'Stop' : 'Play',
                                  icon: Icon(isPlaying ? Icons.stop_circle_outlined : Icons.play_circle_outline, color: AppColors.stone),
                                  onPressed: () => _togglePlay(id, localPath),
                                ),
                                const SizedBox(width: 4),
                              ],
                              if (canRerender) ...[
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.brass, side: const BorderSide(color: AppColors.brass)),
                                  onPressed: (_convertingHymnId != null || _rerenderingHymnId != null) ? null : () => _rerenderHymn(h),
                                  child: const Text('Re-render audio', style: TextStyle(fontSize: 12)),
                                ),
                                const SizedBox(width: 4),
                              ],
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                                onPressed: (_convertingHymnId != null || _rerenderingHymnId != null) ? null : () => _convertHymn(h),
                                child: Text(hasAudio ? 'Re-convert' : 'Convert', style: const TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    setState(() { _importing = true; _importResult = null; });
    try {
      final count = await FirestoreService().importHymnsFromAsset();
      setState(() { _importResult = '$count hymns imported.'; });
      _refresh();
    } catch (e) {
      setState(() { _importResult = 'Import failed: $e'; });
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _rehost() async {
    setState(() { _rehosting = true; _rehostResult = null; });
    try {
      final result = await FirestoreService().rehostHymnPdfs();
      setState(() {
        _rehostResult = '${result['rehosted']} PDFs re-hosted, ${result['skipped']} already done or had no link.'
            '${(result['failureCount'] ?? 0) > 0 ? ' ${result['failureCount']} failed - see below.' : ''}';
      });
      _refresh();
    } catch (e) {
      setState(() { _rehostResult = 'Re-host failed: $e'; });
    } finally {
      if (mounted) setState(() => _rehosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: AppColors.stone,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Import Hymns', style: TextStyle(fontFamily: appSerif, fontSize: 14, color: Colors.white)),
              const Text(
                '214 hymns from CMAA (Church Music Association of America) - real, confirmed Catholic source, transcribed directly from their actual page.',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                onPressed: _importing ? null : _import,
                icon: _importing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.library_music_outlined, size: 16),
                label: Text(_importing ? 'Importing...' : 'Import Hymns'),
              ),
              if (_importResult != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(_importResult!, style: const TextStyle(fontSize: 12, color: Colors.white))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: AppColors.paperDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Re-host PDFs Into This App\'s Storage', style: TextStyle(fontFamily: appSerif, fontSize: 14)),
              const Text(
                'Imported hymns point at CMAA\'s own external link at first - this pulls the real PDF file itself into this project\'s Storage instead, so it isn\'t dependent on CMAA\'s site staying up. Safe to re-run; already-rehosted hymns are skipped.',
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.sage),
                onPressed: _rehosting ? null : _rehost,
                icon: _rehosting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_outlined, size: 16),
                label: Text(_rehosting ? 'Re-hosting... this can take a few minutes' : 'Re-host PDFs'),
              ),
              if (_rehostResult != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(_rehostResult!, style: const TextStyle(fontSize: 12))),
            ],
          ),
        ),
        if (_isWindowsDesktop) ...[
          const SizedBox(height: 12),
          _buildWindowsConversionSection(),
        ],
        const SizedBox(height: 16),
        if (!_showAddForm)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => setState(() => _showAddForm = true),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Hymn Manually'),
          )
        else
          _AddHymnForm(onDone: () { setState(() => _showAddForm = false); _refresh(); }, onCancel: () => setState(() => _showAddForm = false)),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _hymnsFuture,
          builder: (context, snap) {
            final hymns = snap.data ?? [];
            if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            if (hymns.isEmpty) return const Text('No hymns imported yet - use the button above.', style: TextStyle(fontSize: 12, color: Colors.black54));
            return Text('${hymns.length} hymns currently in Firestore.', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _audiverisPathCtrl.dispose();
    _fluidsynthPathCtrl.dispose();
    _soundfontPathCtrl.dispose();
    _tempoCtrl.dispose();
    _repeatCtrl.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

class _AddHymnForm extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onCancel;
  const _AddHymnForm({required this.onDone, required this.onCancel});

  @override
  State<_AddHymnForm> createState() => _AddHymnFormState();
}

class _AddHymnFormState extends State<_AddHymnForm> {
  final _titleCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  String _mode = 'pdf'; // 'pdf' or 'text'
  String? _pickedFileName;
  Uint8List? _pickedBytes;
  bool _saving = false;

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _pickedFileName = result.files.single.name;
        _pickedBytes = result.files.single.bytes;
      });
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    if (_mode == 'pdf' && _pickedBytes == null) return;
    if (_mode == 'text' && _textCtrl.text.trim().isEmpty) return;

    setState(() { _saving = true; });
    try {
      if (_mode == 'pdf') {
        await FirestoreService().addHymnWithPdf(title: _titleCtrl.text.trim(), pdfBytes: _pickedBytes!);
      } else {
        await FirestoreService().addHymnWithText(title: _titleCtrl.text.trim(), lyricsText: _textCtrl.text.trim());
      }
      widget.onDone();
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.paperDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Add Hymn Manually', style: TextStyle(fontFamily: appSerif, fontSize: 14))),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: widget.onCancel),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Hymn title')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: RadioListTile<String>(
                contentPadding: EdgeInsets.zero, dense: true,
                title: const Text('Upload PDF', style: TextStyle(fontSize: 13)),
                value: 'pdf', groupValue: _mode,
                onChanged: (v) => setState(() => _mode = v!),
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                contentPadding: EdgeInsets.zero, dense: true,
                title: const Text('Type Lyrics', style: TextStyle(fontSize: 13)),
                value: 'text', groupValue: _mode,
                onChanged: (v) => setState(() => _mode = v!),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (_mode == 'pdf')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
              onPressed: _pickPdf,
              icon: const Icon(Icons.upload_file, size: 16),
              label: Text(_pickedFileName ?? 'Choose PDF file'),
            )
          else
            TextField(
              controller: _textCtrl, maxLines: 8,
              decoration: const InputDecoration(labelText: 'Lyrics', hintText: 'Type or paste the words here'),
            ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Hymn'),
          ),
        ],
      ),
    );
  }
}