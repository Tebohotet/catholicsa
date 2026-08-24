import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:file_picker/file_picker.dart';
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
  final _audiverisPathCtrl = TextEditingController(text: r'C:\Program Files\Audiveris\bin\Audiveris.exe');
  final _fluidsynthPathCtrl = TextEditingController(text: r'C:\Program Files\FluidSynth\bin\fluidsynth.exe');
  final _soundfontPathCtrl = TextEditingController();
  String? _convertingHymnId;
  List<String> _lastConversionLog = [];
  String? _lastConversionError;

  @override
  void initState() {
    super.initState();
    _hymnsFuture = FirestoreService().getHymns();
  }

  void _refresh() => setState(() { _hymnsFuture = FirestoreService().getHymns(); });

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
      final result = await service.convert(hymnId: id, pdfBytes: pdfBytes);
      setState(() {
        _lastConversionLog = result.log;
        _lastConversionError = result.success ? null : (result.error ?? 'Conversion failed.');
      });
      if (result.success) _refresh();
    } catch (e) {
      setState(() { _lastConversionError = e.toString(); });
    } finally {
      if (mounted) setState(() { _convertingHymnId = null; });
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
          const SizedBox(height: 8),
          TextField(controller: _audiverisPathCtrl, decoration: const InputDecoration(labelText: 'Audiveris.exe path', isDense: true)),
          const SizedBox(height: 6),
          TextField(controller: _fluidsynthPathCtrl, decoration: const InputDecoration(labelText: 'fluidsynth.exe path', isDense: true)),
          const SizedBox(height: 6),
          TextField(controller: _soundfontPathCtrl, decoration: const InputDecoration(labelText: 'Soundfont (.sf2) path', isDense: true)),
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
                  final hasAudio = h['hasAudio'] == true;
                  final isConverting = _convertingHymnId == h['id'];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(h['title'] ?? '', style: const TextStyle(fontSize: 13)),
                    subtitle: Text(hasAudio ? 'Audio already generated' : 'Not yet converted', style: const TextStyle(fontSize: 11)),
                    trailing: isConverting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                            onPressed: _convertingHymnId != null ? null : () => _convertHymn(h),
                            child: Text(hasAudio ? 'Re-convert' : 'Convert', style: const TextStyle(fontSize: 12)),
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