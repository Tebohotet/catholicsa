import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_menu_button.dart';

/// Reusable in-app PDF viewer - replaces the old pattern of handing every
/// PDF link off to url_launcher (which opened the browser's/device's own
/// native PDF viewer, taking the person fully out of the app). Used for
/// hymn source PDFs, the Hymns admin "View original PDF" button, and the
/// donation/marketplace "View Proof (PDF)" buttons - see hymns_screen.dart,
/// hymns_admin_section.dart and admin_panel_screen.dart.
///
/// Still has one url_launcher fallback: if Syncfusion's own renderer fails
/// to load the document (a genuinely corrupt file, an expired/misconfigured
/// Storage URL, or a format quirk it can't parse), [_error] offers a
/// "Open externally instead" button rather than leaving the person stuck
/// looking at a dead screen with no way to see the PDF at all.
class PdfViewerScreen extends StatefulWidget {
  final String url;
  final String title;
  const PdfViewerScreen({super.key, required this.url, required this.title});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final _controller = PdfViewerController();
  String? _error;
  bool _ready = false;
  Uint8List? _bytes;

  // Some content (the bulk-imported hymn source PDFs in particular)
  // stores a direct public GCS object URL
  // (https://storage.googleapis.com/<bucket>/<path>) instead of a
  // proper Firebase Storage download URL. Confirmed live, 2026-11-28,
  // after the project owner's own CORS fix still left every PDF
  // showing "Couldn't display this PDF here": a plain or positive-range
  // fetch of that raw GCS URL works fine, but a suffix byte-range
  // request ("bytes=-1024", i.e. "the last 1024 bytes") fails CORS
  // preflight outright - and that's exactly the kind of request a PDF
  // reader makes first, to read the file's trailer/xref table from the
  // end before it knows how to fetch the rest. Firebase Storage's own
  // `/v0/b/<bucket>/o/<path>?alt=media` endpoint was tested the same
  // way and handles that same suffix range correctly. Rewriting to that
  // form here, right before handing the URL to the PDF viewer, fixes
  // every link already stored this way with no Firestore data
  // migration needed - and costs nothing for a URL that's already in
  // the normal form.
  static final _rawGcsUrl = RegExp(r'^https://storage\.googleapis\.com/([^/]+)/(.+)$');

  String _playableUrl(String url) {
    final match = _rawGcsUrl.firstMatch(url);
    if (match == null) return url;
    final bucket = match.group(1)!;
    final path = match.group(2)!;
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(path)}?alt=media';
  }

  Future<void> _openExternally() async {
    final uri = Uri.parse(_playableUrl(widget.url));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open "${widget.title}".')));
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  // Confirmed live, 2026-11-28, after the two URL/CORS fixes above still
  // left every PDF showing "Couldn't display this PDF here" with no
  // console error at all: the browser's own network requests to the
  // (by then correctly rewritten) URL were succeeding - no CORS error,
  // right headers, right status codes - yet `SfPdfViewer.network()`
  // still failed to render, silently. That matches Syncfusion's own
  // published guidance for exactly this combination (Flutter Web + a
  // Firebase Storage URL): their own "How to load a PDF from Firebase
  // Storage" KB article doesn't use `.network()` at all for web - it
  // fetches the bytes itself and renders with `SfPdfViewer.memory()`
  // instead. Doing the same thing here: a plain `http.get` (no range
  // requests at all, sidestepping whatever `.network()`'s own internal
  // streaming does differently) followed by `.memory()`. These are small
  // files (hymn sheet music, donation/marketplace proof-of-payment
  // scans) so holding the whole thing in memory costs nothing.
  Future<void> _loadBytes() async {
    try {
      final res = await http.get(Uri.parse(_playableUrl(widget.url)));
      if (res.statusCode != 200) {
        throw Exception('Server returned HTTP ${res.statusCode}');
      }
      if (mounted) setState(() => _bytes = res.bodyBytes);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
              padding: const EdgeInsets.fromLTRB(4, 12, 16, 20),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(fontFamily: appSerif, fontSize: 20, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open externally',
                    icon: const Icon(Icons.open_in_new, color: Colors.white, size: 20),
                    onPressed: _openExternally,
                  ),
                  // Was missing from this screen specifically - confirmed
                  // from the project owner's own screenshot, same overlap-
                  // class fix already applied to every other screen
                  // sharing this header shape (see PROJECT_STATUS.md).
                  const ProfileMenuButton(embedded: true),
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? _buildError()
                  : _bytes == null
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(
                          children: [
                            SfPdfViewer.memory(
                              _bytes!,
                              controller: _controller,
                              onDocumentLoaded: (_) {
                                if (mounted) setState(() => _ready = true);
                              },
                              onDocumentLoadFailed: (details) {
                                if (mounted) setState(() => _error = details.description);
                              },
                            ),
                            if (!_ready) const Center(child: CircularProgressIndicator()),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.black45),
            const SizedBox(height: 12),
            const Text("Couldn't display this PDF here.", style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
              onPressed: _openExternally,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open externally instead'),
            ),
          ],
        ),
      ),
    );
  }
}
