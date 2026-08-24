import 'dart:typed_data';

/// Web-safe stub - this file is what gets compiled in for web (and any
/// platform without dart:io), selected automatically at compile time
/// by the conditional export in hymn_conversion_service.dart. Never
/// imports dart:io, so the web build never even sees Process/File and
/// can't fail to compile because of them.
class ConversionResult {
  final bool success;
  final String? audioUrl;
  final String? musicXmlUrl;
  final String? error;
  final List<String> log;
  const ConversionResult({required this.success, this.audioUrl, this.musicXmlUrl, this.error, required this.log});
}

class HymnConversionService {
  final String audiverisPath;
  final String fluidsynthPath;
  final String soundfontPath;

  HymnConversionService({
    required this.audiverisPath,
    required this.fluidsynthPath,
    required this.soundfontPath,
  });

  Future<ConversionResult> convert({required String hymnId, required Uint8List pdfBytes}) async {
    throw UnsupportedError('Hymn conversion only runs on Windows desktop - this platform can\'t shell out to local tools.');
  }

  static Future<Uint8List> downloadPdf(String pdfUrl, String hymnId) async {
    throw UnsupportedError('Hymn conversion only runs on Windows desktop.');
  }
}