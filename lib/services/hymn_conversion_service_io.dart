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
    List<int>? instrumentPrograms,
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
        instrumentPrograms: instrumentPrograms,
      );
      final midiFile = File(p.join(workDir.path, 'output.mid'));
      await midiFile.writeAsBytes(midiBytes);
      log.add('MIDI written (${midiBytes.length} bytes) at $bpm BPM'
          '${instrumentPrograms != null && instrumentPrograms.isNotEmpty ? ', instrument programs by part: ${instrumentPrograms.join(', ')}' : ''}'
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
      final localMxlPath = await localMxlPathFor(hymnId);
      await mxlFile.copy(localMxlPath);
      log.add('Saved the recognized MusicXML to $localMxlPath for inspection.');

      log.add('Uploading results to Firebase Storage...');
      final bucket = FirebaseStorage.instance;
      // Without an explicit contentType, Storage falls back to a generic
      // binary type - native platforms don't care and play it anyway,
      // but a web browser's own <audio> element refuses to play a file
      // the server didn't label as audio at all ("Format error, Code 4"
      // - the Hymns web page's exact complaint). Setting it here is what
      // actually fixes playback on web.
      final wavRef = bucket.ref('hymns/$hymnId.wav');
      await wavRef.putFile(wavFile, SettableMetadata(contentType: 'audio/wav'));
      final audioUrl = await wavRef.getDownloadURL();

      final mxlRef = bucket.ref('hymns/$hymnId.mxl');
      await mxlRef.putFile(mxlFile, SettableMetadata(contentType: 'application/vnd.recordare.musicxml'));
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

  /// Where the MusicXML recognized by the last full Convert/Re-convert
  /// is saved locally - same folder as the WAV, same naming pattern.
  /// `convert()` above writes this file; `rerenderFromSavedMxl` below
  /// reads it back.
  static Future<String> localMxlPathFor(String hymnId) async {
    final dir = await _hymnAudioDir();
    return p.join(dir, '$hymnId.mxl');
  }

  /// Used by the admin screen to decide whether to show a Play button
  /// for a hymn without re-running the conversion - e.g. after an app
  /// restart, when a previous session's local copy is still on disk.
  static Future<String?> localAudioPathIfExists(String hymnId) async {
    final path = await localWavPathFor(hymnId);
    return File(path).existsSync() ? path : null;
  }

  /// Used by the admin screen to decide whether "Re-render audio" (as
  /// opposed to Convert/Re-convert) is even possible yet for a hymn -
  /// it needs a `.mxl` already sitting on disk from a previous full
  /// conversion.
  static Future<bool> hasSavedMxl(String hymnId) async {
    return File(await localMxlPathFor(hymnId)).existsSync();
  }

  /// Re-renders a hymn's audio from the MusicXML already saved locally
  /// by a previous Convert/Re-convert, instead of running the whole
  /// pipeline from the PDF again. Real, confirmed need: Audiveris (the
  /// slow step - it's the actual page-recognition scan) never needs to
  /// re-run just because the admin wants to try a different tempo,
  /// instrument, or repeat count on notes that were already correctly
  /// recognized - only MusicXML -> MIDI -> FluidSynth do.
  ///
  /// Same real limitation as `convert()` above: only the first
  /// movement's `.mxl` is ever saved locally, so a hymn Audiveris split
  /// into several movements only re-renders that first one here, same
  /// as it's only ever saved that one locally in the first place.
  Future<ConversionResult> rerenderFromSavedMxl({
    required String hymnId,
    int bpm = 84,
    int? instrumentProgram,
    int repeatCount = 1,
  }) async {
    final log = <String>[];
    final localMxlPath = await localMxlPathFor(hymnId);
    final mxlFile = File(localMxlPath);
    if (!mxlFile.existsSync()) {
      return ConversionResult(
        success: false,
        error: 'No saved MusicXML found for this hymn yet - run Convert (or Re-convert) at least once first.',
        log: ['Expected a file at $localMxlPath - nothing there.'],
      );
    }

    final tempDir = await getTemporaryDirectory();
    final workDir = Directory(p.join(tempDir.path, 'hymn-rerender-$hymnId'));
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    workDir.createSync(recursive: true);

    try {
      log.add('Re-rendering from the MusicXML saved by the last full conversion - skipping Audiveris.');
      log.add('Step 1/2: Converting MusicXML -> MIDI...');
      final mxlBytes = await mxlFile.readAsBytes();
      final repeatedMxlBytes = [for (var i = 0; i < repeatCount.clamp(1, 20); i++) mxlBytes];
      final midiBytes = MusicXmlToMidiConverter.convertAll(
        repeatedMxlBytes,
        bpm: bpm,
        instrumentPrograms: instrumentProgram != null ? [instrumentProgram] : null,
      );
      final midiFile = File(p.join(workDir.path, 'output.mid'));
      await midiFile.writeAsBytes(midiBytes);
      log.add('MIDI written (${midiBytes.length} bytes) at $bpm BPM'
          '${instrumentProgram != null ? ', instrument program $instrumentProgram' : ''}'
          '${repeatCount > 1 ? ', repeated $repeatCount times' : ''}.');

      log.add('Step 2/2: Synthesizing MIDI -> WAV via FluidSynth...');
      final wavFile = File(p.join(workDir.path, 'output.wav'));
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

      final localPath = await localWavPathFor(hymnId);
      await wavFile.copy(localPath);
      log.add('Saved a local copy to $localPath.');

      log.add('Uploading to Firebase Storage...');
      final bucket = FirebaseStorage.instance;
      final wavRef = bucket.ref('hymns/$hymnId.wav');
      await wavRef.putFile(wavFile, SettableMetadata(contentType: 'audio/wav'));
      final audioUrl = await wavRef.getDownloadURL();

      log.add('Updating Firestore...');
      await FirebaseFirestore.instance.collection('hymns').doc(hymnId).update({
        'audioUrl': audioUrl,
        'hasAudio': true,
        'omrConvertedAt': FieldValue.serverTimestamp(),
      });

      log.add('Done.');
      return ConversionResult(success: true, audioUrl: audioUrl, localWavPath: localPath, log: log);
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

  /// Adds a real sung-vocal line on top of a hymn's already-rendered
  /// instrumental audio, using OddVoices (a free, offline singing
  /// synthesizer - https://gitlab.com/oddvoices/oddvoices). Needs two
  /// things that must already exist: the MusicXML saved by a previous
  /// Convert/Re-convert (for the melody notes) and lyrics text typed
  /// in by an admin - confirmed directly against real hymn PDFs that
  /// Audiveris's OMR produces zero <lyric> tags, so the actual words
  /// can't come from the score itself and have to be typed in.
  ///
  /// The vocal line and the existing instrumental WAV are mixed into
  /// one combined WAV (so the hymn still has just one Play button and
  /// one audio file, same as every other hymn), and that combined WAV
  /// replaces the instrumental-only one both locally and in Storage -
  /// running this again (e.g. after fixing a typo in the lyrics) always
  /// mixes the voice back onto the plain instrumental re-rendered
  /// fresh from the saved MusicXML, not onto a previous mix, so the
  /// voice is never doubled up.
  Future<ConversionResult> addSingingVoice({
    required String hymnId,
    required String lyricsText,
    required String singExePath,
    required String cmudictPath,
    required String voiceFilePath,
    int bpm = 84,
    int? instrumentProgram,
    int repeatCount = 1,
  }) async {
    final log = <String>[];
    if (lyricsText.trim().isEmpty) {
      return ConversionResult(success: false, error: 'Add this hymn\'s lyrics first - OddVoices needs the actual words to sing.', log: log);
    }
    final localMxlPath = await localMxlPathFor(hymnId);
    final mxlFile = File(localMxlPath);
    if (!mxlFile.existsSync()) {
      return ConversionResult(
        success: false,
        error: 'No saved MusicXML found for this hymn yet - run Convert (or Re-convert) at least once first.',
        log: ['Expected a file at $localMxlPath - nothing there.'],
      );
    }

    final tempDir = await getTemporaryDirectory();
    final workDir = Directory(p.join(tempDir.path, 'hymn-voice-$hymnId'));
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    workDir.createSync(recursive: true);

    try {
      log.add('Step 1/4: Re-rendering the plain instrumental from the saved MusicXML, so the voice mixes onto a fresh copy rather than a previous mix...');
      final mxlBytes = await mxlFile.readAsBytes();
      final repeatedMxlBytes = [for (var i = 0; i < repeatCount.clamp(1, 20); i++) mxlBytes];
      final instrumentalMidiBytes = MusicXmlToMidiConverter.convertAll(
        repeatedMxlBytes,
        bpm: bpm,
        instrumentPrograms: instrumentProgram != null ? [instrumentProgram] : null,
      );
      final instrumentalMidiFile = File(p.join(workDir.path, 'instrumental.mid'));
      await instrumentalMidiFile.writeAsBytes(instrumentalMidiBytes);
      final instrumentalWavFile = File(p.join(workDir.path, 'instrumental.wav'));
      final fluidResult = await Process.run(
        fluidsynthPath,
        ['-ni', '-F', instrumentalWavFile.path, '-r', '44100', soundfontPath, instrumentalMidiFile.path],
      );
      log.add('FluidSynth exit code: ${fluidResult.exitCode}');
      if (fluidResult.exitCode != 0 || !instrumentalWavFile.existsSync()) {
        log.add('stderr: ${fluidResult.stderr}');
        return ConversionResult(success: false, error: 'FluidSynth failed re-rendering the instrumental - see log.', log: log);
      }

      log.add('Step 2/4: Pulling just the melody line out of the saved MusicXML...');
      final melodyMidiBytes = MusicXmlToMidiConverter.convertAllMelodyOnly(repeatedMxlBytes, bpm: bpm);
      final melodyMidiFile = File(p.join(workDir.path, 'melody.mid'));
      await melodyMidiFile.writeAsBytes(melodyMidiBytes);
      log.add('Melody MIDI written (${melodyMidiBytes.length} bytes).');

      final lyricsFile = File(p.join(workDir.path, 'lyrics.txt'));
      await lyricsFile.writeAsString(lyricsText.trim());

      log.add('Step 3/4: Singing the melody with OddVoices...');
      final vocalWavFile = File(p.join(workDir.path, 'vocal.wav'));
      final singResult = await Process.run(
        singExePath,
        [voiceFilePath, cmudictPath, '-m', melodyMidiFile.path, '-l', lyricsFile.path, vocalWavFile.path],
      );
      // Logged every time, not just on failure - an "exit code 0" that
      // quietly sang almost nothing (wrong path resolved to something
      // that didn't error, a voice file it barely used, etc.) needs to
      // be told apart from a genuinely good vocal.wav that the mixing
      // step then lost, and the only way to do that without re-running
      // this by hand is to see what sing.exe itself said, every time.
      log.add('sing exit code: ${singResult.exitCode}');
      if ((singResult.stdout as String).trim().isNotEmpty) log.add('sing stdout: ${singResult.stdout}');
      if ((singResult.stderr as String).trim().isNotEmpty) log.add('sing stderr: ${singResult.stderr}');
      if (singResult.exitCode != 0 || !vocalWavFile.existsSync()) {
        return ConversionResult(success: false, error: 'OddVoices failed to render the vocal line - see log.', log: log);
      }
      final vocalBytesForLog = await vocalWavFile.readAsBytes();
      log.add('Vocal line synthesized (${vocalBytesForLog.length} bytes).');

      log.add('Step 4/4: Mixing the vocal line into the instrumental...');
      final combinedBytes = _mixWavFiles(await instrumentalWavFile.readAsBytes(), vocalBytesForLog, log);
      final combinedFile = File(p.join(workDir.path, 'combined.wav'));
      await combinedFile.writeAsBytes(combinedBytes);
      log.add('Mixed.');

      final localPath = await localWavPathFor(hymnId);
      await combinedFile.copy(localPath);
      log.add('Saved a local copy to $localPath.');

      log.add('Uploading to Firebase Storage...');
      final bucket = FirebaseStorage.instance;
      final wavRef = bucket.ref('hymns/$hymnId.wav');
      await wavRef.putFile(combinedFile, SettableMetadata(contentType: 'audio/wav'));
      final audioUrl = await wavRef.getDownloadURL();

      log.add('Updating Firestore...');
      await FirebaseFirestore.instance.collection('hymns').doc(hymnId).update({
        'audioUrl': audioUrl,
        'hasAudio': true,
        'hasVoice': true,
        'omrConvertedAt': FieldValue.serverTimestamp(),
      });

      log.add('Done.');
      return ConversionResult(success: true, audioUrl: audioUrl, localWavPath: localPath, log: log);
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

  /// Mixes two WAV files (an instrumental track and a sung vocal line)
  /// sample-by-sample into one combined WAV. The two tools that
  /// produce them aren't guaranteed to agree on sample rate or channel
  /// count, so the vocal line is resampled/re-channeled to match the
  /// instrumental rather than assumed identical, and whichever one is
  /// shorter is padded with silence rather than cutting the longer one
  /// off early.
  ///
  /// Real, confirmed bug from the first real test: OddVoices' own
  /// output runs much quieter than FluidSynth's (checked directly in
  /// OddVoices' own source - its WAV writer just writes whatever
  /// sample values its synthesis produced, with no loudness
  /// normalization of its own, and the two tools were never going to
  /// happen to agree). Simply adding the two tracks as-is meant the
  /// vocal was almost inaudible under the instrumental - "I only hear
  /// the organ" is exactly what that bug sounds like. Each track is
  /// now independently normalized to the same peak level before
  /// summing, so the voice is always actually audible regardless of
  /// either tool's own internal volume, and the final sum is scaled
  /// back down if it would otherwise clip.
  static Uint8List _mixWavFiles(Uint8List instrumentalBytes, Uint8List vocalBytes, [List<String>? log]) {
    final instrumental = _WavAudio.parse(instrumentalBytes);
    final vocal = _WavAudio.parse(vocalBytes);
    final rate = instrumental.sampleRate;
    final channels = instrumental.channels;

    int peakOf(List<int> s) {
      var p = 0;
      for (final x in s) {
        final abs = x < 0 ? -x : x;
        if (abs > p) p = abs;
      }
      return p;
    }

    final rawInstrumental = instrumental.resampledTo(rate, channels);
    final rawVocal = vocal.resampledTo(rate, channels);
    // Logged unconditionally - a genuinely silent/near-silent vocal.wav
    // (OddVoices "succeeded" but produced little or nothing: a wrong
    // path it didn't complain about, melody notes that didn't extract
    // right, etc.) needs to be visible directly, instead of looking
    // identical in the log to the "too quiet to notice" volume-balance
    // bug this normalization already fixed.
    log?.add('Instrumental: ${instrumental.sampleRate} Hz, ${instrumental.channels} ch, '
        '${rawInstrumental.length} samples (~${(rawInstrumental.length / (rate * channels)).toStringAsFixed(1)}s), '
        'peak ${peakOf(rawInstrumental)}/32767.');
    log?.add('Vocal: ${vocal.sampleRate} Hz, ${vocal.channels} ch, '
        '${rawVocal.length} samples (~${(rawVocal.length / (vocal.sampleRate * vocal.channels)).toStringAsFixed(1)}s), '
        'peak ${peakOf(rawVocal)}/32767.');
    if (peakOf(rawVocal) < 50) {
      log?.add('WARNING: the vocal track is essentially silent before mixing even starts - normalizing volume '
          "can't fix that. The problem is upstream (the melody MIDI, the lyrics, or the sing.exe call itself), not the mix.");
    }

    final a = _normalizePeak(rawInstrumental);
    final b = _normalizePeak(rawVocal);
    final length = a.length > b.length ? a.length : b.length;

    final mixed = List<int>.filled(length, 0);
    for (var i = 0; i < length; i++) {
      final sa = i < a.length ? a[i] : 0;
      final sb = i < b.length ? b[i] : 0;
      mixed[i] = sa + sb;
    }

    var peak = 0;
    for (final s in mixed) {
      final abs = s < 0 ? -s : s;
      if (abs > peak) peak = abs;
    }
    if (peak > 32767) {
      final scale = 32767 / peak;
      for (var i = 0; i < mixed.length; i++) {
        mixed[i] = (mixed[i] * scale).round();
      }
    }
    log?.add('Both tracks normalized to the same peak level and summed - combined length '
        '${(length / (rate * channels)).toStringAsFixed(1)}s.');

    return _writeWav16(mixed, sampleRate: rate, channels: channels);
  }

  /// Scales [samples] so its loudest single sample sits at [targetPeak]
  /// (leaving headroom below 16-bit full scale for the other track
  /// added on top), leaving silence as silence rather than amplifying
  /// noise out of nothing.
  static List<int> _normalizePeak(List<int> samples, {int targetPeak = 24000}) {
    var peak = 0;
    for (final s in samples) {
      final abs = s < 0 ? -s : s;
      if (abs > peak) peak = abs;
    }
    if (peak == 0) return samples;
    final gain = targetPeak / peak;
    return [for (final s in samples) (s * gain).round()];
  }

  static Uint8List _writeWav16(List<int> samples, {required int sampleRate, required int channels}) {
    final dataSize = samples.length * 2;
    final byteRate = sampleRate * channels * 2;
    final blockAlign = channels * 2;
    final builder = BytesBuilder();

    void u32(int v) => builder.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    void u16(int v) => builder.add([v & 0xFF, (v >> 8) & 0xFF]);

    builder.add('RIFF'.codeUnits);
    u32(36 + dataSize);
    builder.add('WAVE'.codeUnits);
    builder.add('fmt '.codeUnits);
    u32(16); // fmt chunk size
    u16(1); // PCM
    u16(channels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(16); // bits per sample
    builder.add('data'.codeUnits);
    u32(dataSize);
    for (final s in samples) {
      final v = s.clamp(-32768, 32767);
      builder.add([v & 0xFF, (v >> 8) & 0xFF]);
    }
    return builder.toBytes();
  }

  /// The parts (by name, in order) Audiveris recognized the last time
  /// this hymn was converted on this PC, read from the locally saved
  /// .mxl - lets the admin screen offer one instrument per part before
  /// re-converting. Null when there's no saved .mxl or it can't be
  /// read. Only the first movement's .mxl is saved, so a hymn that
  /// Audiveris split into movements is assumed to keep the same parts
  /// in each (parts past this list fall back to the last instrument).
  static Future<List<String>?> localPartNamesIfExists(String hymnId) async {
    final wavPath = await localWavPathFor(hymnId);
    final mxl = File(p.join(p.dirname(wavPath), '$hymnId.mxl'));
    if (!mxl.existsSync()) return null;
    try {
      final xml = MusicXmlToMidiConverter.extractMusicXmlFromMxlBytes(await mxl.readAsBytes());
      final names = MusicXmlToMidiConverter.partNames(xml);
      return names.isEmpty ? null : names;
    } catch (_) {
      return null;
    }
  }
}

/// Minimal, pure-Dart WAV reader - just enough to read the handful of
/// uncompressed-PCM formats FluidSynth and OddVoices actually produce,
/// so two WAV files can be mixed without pulling in a third-party
/// audio package. Anything else (compressed audio, an unsupported bit
/// depth) throws a clear error rather than silently mixing garbage.
class _WavAudio {
  final int sampleRate;
  final int channels;
  final List<int> samples; // interleaved, one signed 16-bit-range int per sample per channel

  _WavAudio({required this.sampleRate, required this.channels, required this.samples});

  static _WavAudio parse(Uint8List bytes) {
    if (bytes.length < 12 || _tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') {
      throw Exception('Not a WAV file (missing RIFF/WAVE header).');
    }
    final data = ByteData.sublistView(bytes);
    int? sampleRate, channels, bitsPerSample, audioFormat;
    List<int>? samples;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = _tag(bytes, offset);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final bodyStart = offset + 8;
      if (chunkId == 'fmt ') {
        audioFormat = data.getUint16(bodyStart, Endian.little);
        channels = data.getUint16(bodyStart + 2, Endian.little);
        sampleRate = data.getUint32(bodyStart + 4, Endian.little);
        bitsPerSample = data.getUint16(bodyStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        samples = _readSamples(bytes, bodyStart, chunkSize, bitsPerSample ?? 16);
      }
      // Chunks are word-aligned: an odd-sized chunk has one pad byte after it.
      offset = bodyStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    if (sampleRate == null || channels == null || samples == null) {
      throw Exception('WAV file is missing its fmt or data chunk.');
    }
    if (audioFormat != 1 && audioFormat != 3) {
      // 1 = integer PCM, 3 = IEEE float - anything else (ADPCM etc.) isn't handled.
      throw Exception('Unsupported WAV audio format code $audioFormat - expected plain PCM.');
    }
    return _WavAudio(sampleRate: sampleRate, channels: channels, samples: samples);
  }

  static String _tag(Uint8List bytes, int offset) => String.fromCharCodes(bytes.sublist(offset, offset + 4));

  static List<int> _readSamples(Uint8List bytes, int start, int length, int bits) {
    final data = ByteData.sublistView(bytes);
    final bytesPerSample = (bits / 8).ceil().clamp(1, 4);
    final count = bytesPerSample == 0 ? 0 : length ~/ bytesPerSample;
    final out = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final o = start + i * bytesPerSample;
      switch (bits) {
        case 8:
          out[i] = (bytes[o] - 128) * 256; // unsigned 8-bit -> signed 16-bit range
        case 16:
          out[i] = data.getInt16(o, Endian.little);
        case 24:
          var v = bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16);
          if (v & 0x800000 != 0) v -= 0x1000000;
          out[i] = v >> 8; // scale down to 16-bit range
        case 32:
          out[i] = data.getInt32(o, Endian.little) >> 16; // scale down to 16-bit range
        default:
          throw Exception('Unsupported WAV bit depth: $bits');
      }
    }
    return out;
  }

  /// Resampled (simple linear interpolation - good enough for mixing
  /// two already-synthesized tracks, neither of which has content near
  /// the Nyquist frequency that interpolation would alias) to
  /// [targetRate] and converted to [targetChannels] (mono averaged
  /// down from stereo, or duplicated up to stereo).
  List<int> resampledTo(int targetRate, int targetChannels) {
    final frameCount = channels == 0 ? 0 : samples.length ~/ channels;
    final perFrame = List<List<int>>.generate(frameCount, (i) {
      final frame = [for (var c = 0; c < channels; c++) samples[i * channels + c]];
      if (targetChannels == channels) return frame;
      if (targetChannels == 1) {
        final sum = frame.fold<int>(0, (s, v) => s + v);
        return [sum ~/ channels];
      }
      return List.filled(targetChannels, frame.first);
    });
    if (perFrame.isEmpty) return const [];

    if (sampleRate == targetRate) {
      return perFrame.expand((f) => f).toList();
    }

    final ratio = targetRate / sampleRate;
    final outFrames = (perFrame.length * ratio).round();
    final out = <int>[];
    for (var i = 0; i < outFrames; i++) {
      final srcPos = i / ratio;
      final srcIndex = srcPos.floor().clamp(0, perFrame.length - 1);
      final frac = srcPos - srcIndex;
      final a = perFrame[srcIndex];
      final b = perFrame[(srcIndex + 1).clamp(0, perFrame.length - 1)];
      for (var c = 0; c < targetChannels; c++) {
        out.add((a[c] + (b[c] - a[c]) * frac).round());
      }
    }
    return out;
  }

}
