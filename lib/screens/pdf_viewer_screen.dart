import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

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

  Future<void> _openExternally() async {
    final uri = Uri.parse(widget.url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open "${widget.title}".')));
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
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? _buildError()
                  : Stack(
                      children: [
                        SfPdfViewer.network(
                          widget.url,
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
