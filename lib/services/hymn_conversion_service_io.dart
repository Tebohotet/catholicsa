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
  final String? error;
  final List<String> log;
  const ConversionResult({required this.success, this.audioUrl, this.musicXmlUrl, this.error, required this.log});
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

      final mxlFiles = workDir.listSync().whereType<File>().where((f) => f.path.endsWith('.mxl')).toList();
      if (mxlFiles.isEmpty) {
        return ConversionResult(success: false, error: 'Audiveris ran without error but produced no .mxl file.', log: log);
      }
      final mxlFile = mxlFiles.first;
      log.add('Found ${mxlFile.path}');

      log.add('Step 2/3: Converting MusicXML -> MIDI...');
      final mxlBytes = await mxlFile.readAsBytes();
      final midiBytes = MusicXmlToMidiConverter.convert(mxlBytes);
      final midiFile = File(p.join(workDir.path, 'output.mid'));
      await midiFile.writeAsBytes(midiBytes);
      log.add('MIDI written (${midiBytes.length} bytes).');

      log.add('Step 3/3: Synthesizing MIDI -> WAV via FluidSynth...');
      final wavFile = File(p.join(workDir.path, 'output.wav'));
      final fluidResult = await Process.run(
        fluidsynthPath,
        ['-ni', soundfontPath, midiFile.path, '-F', wavFile.path, '-r', '44100'],
      );
      log.add('FluidSynth exit code: ${fluidResult.exitCode}');
      if (fluidResult.exitCode != 0 || !wavFile.existsSync()) {
        log.add('stderr: ${fluidResult.stderr}');
        return ConversionResult(success: false, error: 'FluidSynth failed - see log.', log: log);
      }
      log.add('WAV synthesized.');

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
      return ConversionResult(success: true, audioUrl: audioUrl, musicXmlUrl: musicXmlUrl, log: log);
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
}