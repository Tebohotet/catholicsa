import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'musicxml_converter.dart';


class ConversionResult {
  final bool success;
  final String? audioUrl;
  final String? musicXmlUrl;
  final String? localWavPath;
  final String? error;
  final List<String> log;
  const ConversionResult({
    required this.success,
    this.audioUrl,
    this.musicXmlUrl,
    this.localWavPath,
    this.error,
    required this.log,
  });
}

/// Real implementation - only ever compiled in on native platforms
/// (Windows, in practice, since that's the only one an admin would
/// actually run this on). Both external tools must already be
/// installed on this PC; this only shells out to them, never installs
/// them.
class HymnConversionService {
  final String audiverisPath;
  final String fluidsynthPath;
  final String soundfontPath;

  HymnConversionService({
    required this.audiverisPath,
    required this.fluidsynthPath,
    required this.soundfontPath,
  });

  Future<ConversionResult> convert({
    required String hymnId,
    required Uint8List pdfBytes,
    int bpm = 84,
    int? instrumentProgram,
    int repeatCount = 1,
  }) async {
    final log = <String>[];
    final tempDir = await getTemporaryDirectory();
    final workDir = Directory(p.join(tempDir.path, 'hymn-omr-$hymnId'));
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    workDir.createSync(recursive: true);
    final pdfFile = File(p.join(workDir.path, 'input.pdf'));
    await pdfFile.writeAsBytes(pdfBytes);

    try {
      log.add('Step 1/3: Running Audiveris (PDF -> MusicXML)...');
      final audiverisResult = await Process.run(
        audiverisPath,
        ['-batch', '-export', '-output', workDir.path, pdfFile.path],
      );
      log.add('Audiveris exit code: ${audiverisResult.exitCode}');
      if (audiverisResult.exitCode != 0) {
        log.add('stderr: ${audiverisResult.stderr}');
        return ConversionResult(success: false, error: 'Audiveris failed - see log.', log: log);
      }

      // Searched recursively: depending on version, Audiveris writes
      // its export into a per-book subfolder of -output (e.g.
      // <workDir>/input/input.mxl) rather than directly into it. A
      // score it splits into several movements comes out as
      // input.mvt1.mxl, input.mvt2.mxl, ... - sorted so the first
      // movement is picked deterministically.
      final mxlFiles = workDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.mxl'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (mxlFiles.isEmpty) {
        log.add('stdout: ${audiverisResult.stdout}');
        return ConversionResult(success: false, error: 'Audiveris ran without error but produced no .mxl file.', log: log);
      }
      final mxlFile = mxlFiles.first;
      log.add('Found ${mxlFile.path}');
      if (mxlFiles.length > 1) {
        log.add('Audiveris produced ${mxlFiles.length} .mxl files (it split the score into several movements): ${mxlFiles.map((f) => p.basename(f.path)).join(', ')}. Merging all of them in order so the full piece plays, not just the first movement.');
      }

      log.add('Step 2/3: Converting MusicXML -> MIDI...');
      // Real, confirmed cause of hymns cutting off early: when
      // Audiveris can't merge every page/system into one book, each
      // one above becomes its own separate .mxl - converting only
      // mxlFiles.first (the old behaviour) played just that first
      // movement and then stopped. convertAll reads every .mxl found
      // and appends them in order, each one starting right where the
      // last one ended.
      // repeatCount lets the admin loop the recognized tune several
      // times (e.g. once per verse) - a technically-complete,
      // accurate render of a short hymn tune will still sound "too
      // short" next to the real multi-verse hymn it's compared
      // against, since nothing here knows how many verses there are.
      // Reusing convertAll's movement-merge logic for this is free:
      // repeating the same bytes N times IS just N "movements" that
      // happen to be identical.
      final singlePassMxlBytes = [for (final f in mxlFiles) await f.readAsBytes()];
      final repeatedMxlBytes = [for (var i = 0; i < repeatCount.clamp(1, 20); i++) ...singlePassMxlBytes];
      final midiBytes = MusicXmlToMidiConverter.convertAll(
        repeatedMxlBytes,
        bpm: bpm,
        instrumentProgram: instrumentProgram,
      );
      final midiFile = File(p.join(workDir.path, 'output.mid'));
      await midiFile.writeAsBytes(midiBytes);
      log.add('MIDI written (${midiBytes.length} bytes) at $bpm BPM'
          '${instrumentProgram != null ? ', instrument program $instrumentProgram' : ''}'
          '${repeatCount > 1 ? ', repeated $repeatCount times' : ''}.');

      log.add('Step 3/3: Synthesizing MIDI -> WAV via FluidSynth...');
      final wavFile = File(p.join(workDir.path, 'output.wav'));
      // Real, confirmed bug: fluidsynth's own CLI synopsis is
      // "fluidsynth [options] [SoundFonts] [midifiles]" - every option
      // (-ni, -F, -r) has to come before the soundfont/midi file
      // positional arguments, not after. With them after, fluidsynth
      // stops parsing options once the positional soundfont argument
      // starts, so "-F" and the wav path were being swallowed as
      // extra (invalid) positional file arguments instead of being
      // read as the -F flag's value - confirmed against a real run:
      // "'-F' is an illegal option at this place, only -b option is
      // allowed here" / "<output.wav> not a SoundFont or MIDI file".
      final fluidResult = await Process.run(
        fluidsynthPath,
        ['-ni', '-F', wavFile.path, '-r', '44100', soundfontPath, midiFile.path],
      );
      log.add('FluidSynth exit code: ${fluidResult.exitCode}');
      if (fluidResult.exitCode != 0 || !wavFile.existsSync()) {
        log.add('stderr: ${fluidResult.stderr}');
        return ConversionResult(success: false, error: 'FluidSynth failed - see log.', log: log);
      }
      log.add('WAV synthesized.');

      // Saved to a permanent, predictable spot on this PC (not the
      // temp workDir, which is wiped in `finally` below no matter what
      // happens next) so the admin can play it back from the app at
      // any time afterwards - including if the Storage upload below
      // fails, or on a future run without reconverting at all.
      final localPath = await localWavPathFor(hymnId);
      await wavFile.copy(localPath);
      log.add('Saved a local copy to $localPath.');

      // Also kept locally, purely for diagnosing what Audiveris
      // actually recognized when a converted hymn sounds wrong or cuts
      // off early - this is the real MusicXML, so its measure/note
      // count tells you directly whether that's an OMR recognition
      // problem (too few notes/measures than the real score) rather
      // than a bug in this converter.
      final localMxlPath = p.join(p.dirname(localPath), '$hymnId.mxl');
      await mxlFile.copy(localMxlPath);
      log.add('Saved the recognized MusicXML to $localMxlPath for inspection.');

      log.add('Uploading results to Firebase Storage...');
      final bucket = FirebaseStorage.instance;
      final wavRef = bucket.ref('hymns/$hymnId.wav');
      await wavRef.putFile(wavFile);
      final audioUrl = await wavRef.getDownloadURL();

      final mxlRef = bucket.ref('hymns/$hymnId.mxl');
      await mxlRef.putFile(mxlFile);
      final musicXmlUrl = await mxlRef.getDownloadURL();

      log.add('Updating Firestore...');
      await FirebaseFirestore.instance.collection('hymns').doc(hymnId).update({
        'audioUrl': audioUrl,
        'musicXmlUrl': musicXmlUrl,
        'hasAudio': true,
        'omrConvertedAt': FieldValue.serverTimestamp(),
      });

      log.add('Done.');
      return ConversionResult(
        success: true,
        audioUrl: audioUrl,
        musicXmlUrl: musicXmlUrl,
        localWavPath: localPath,
        log: log,
      );
    } catch (e) {
      log.add('FAILED: $e');
      return ConversionResult(success: false, error: e.toString(), log: log);
    } finally {
      if (workDir.existsSync()) {
        try {
          workDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  static Future<Uint8List> downloadPdf(String pdfUrl, String hymnId) async {
    final response = await http.get(Uri.parse(pdfUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download PDF: HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  /// Where a converted hymn's WAV lives permanently on this PC, inside
  /// the same `Documents\CatholicSA\...` family the user already keeps
  /// the repo and Bible texts in - deliberately not path_provider's
  /// app-id-nested application-documents folder, which would be much
  /// harder for the user to find on disk than a plain, predictable
  /// path under their own Documents folder.
  static Future<String> _hymnAudioDir() async {
    final userProfile = Platform.environment['USERPROFILE'];
    final docsDir = userProfile != null && userProfile.isNotEmpty
        ? p.join(userProfile, 'Documents')
        : (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(p.join(docsDir, 'CatholicSA', 'HymnAudio'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  static Future<String> localWavPathFor(String hymnId) async {
    final dir = await _hymnAudioDir();
    return p.join(dir, '$hymnId.wav');
  }

  /// Used by the admin screen to decide whether to show a Play button
  /// for a hymn without re-running the conversion - e.g. after an app
  /// restart, when a previous session's local copy is still on disk.
  static Future<String?> localAudioPathIfExists(String hymnId) async {
    final path = await localWavPathFor(hymnId);
    return File(path).existsSync() ? path : null;
  }
}