import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';


class PhotoTile extends StatelessWidget {
  final List<Map<String, String>> items;
  final int index;
  const PhotoTile({super.key, required this.items, required this.index});

  @override
  Widget build(BuildContext context) {
    final item = items[index];
    final isVideo = item['kind'] == 'video';
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => GalleryViewer(items: items, initialIndex: index),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(item['url']!, fit: BoxFit.cover),
          // Dim overlay so caption text stays readable over any photo.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.55)],
              ),
            ),
          ),
          if (isVideo)
            const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 28)),
          Positioned(
            left: 4, right: 4, bottom: 4,
            child: Text(item['caption']!,
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class GalleryViewer extends StatefulWidget {
  final List<Map<String, String>> items;
  final int initialIndex;
  const GalleryViewer({super.key, required this.items, required this.initialIndex});

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late final PageController _controller;
  late int _current;
  final Set<int> _liked = {};
  final Map<int, int> _likeCounts = {};
  final Map<int, List<String>> _comments = {
    0: ['Beautiful, God bless!', 'Wish I could have been there.'],
    1: ['Such a joyful day for the parish.'],
    2: ['Congratulations to all the children!'],
  };
  final _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
    for (var i = 0; i < widget.items.length; i++) {
      final isSample = widget.items[i]['isSample'] == 'true';
      // Only the clearly-labelled sample photos get demo like counts and
      // pre-written comments - a real uploaded photo has no backend for
      // this yet, so it honestly starts at zero rather than showing fake
      // engagement numbers on someone's genuine photo.
      _likeCounts[i] = isSample ? 4 + i * 3 : 0;
      if (!isSample) _comments[i] = [];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_current + delta).clamp(0, widget.items.length - 1);
    _controller.animateToPage(next, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _toggleLike(int i) {
    setState(() {
      if (_liked.contains(i)) {
        _liked.remove(i);
        _likeCounts[i] = (_likeCounts[i] ?? 1) - 1;
      } else {
        _liked.add(i);
        _likeCounts[i] = (_likeCounts[i] ?? 0) + 1;
      }
    });
  }

  void _addComment(int i) {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      (_comments[i] ??= []).add(text);
      _commentCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 640, maxWidth: 500),
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) {
                final item = widget.items[i];
                final isVideo = item['kind'] == 'video';
                final isSample = item['isSample'] == 'true';
                return Column(
                  children: [
                    Expanded(
                      child: isVideo
                          ? Container(
                              color: Colors.black87,
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.play_circle_outline, color: Colors.white70, size: 64),
                                  const SizedBox(height: 12),
                                  if (isSample)
                                    const Text('Sample video placeholder — real video playback needs actual uploaded footage.',
                                        style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)
                                  else ...[
                                    const Text('In-app video playback isn\'t built yet — open it in a new tab instead.',
                                        style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                                      onPressed: () => launchUrl(Uri.parse(item['url']!), mode: LaunchMode.externalApplication),
                                      icon: const Icon(Icons.open_in_new, size: 16),
                                      label: const Text('Open Video'),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : Image.network(item['url']!, fit: BoxFit.contain),
                    ),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 220),
                      color: const Color(0xFF1a1a1a),
                      padding: const EdgeInsets.all(14),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['caption']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text('${item['date']} · Uploaded by ${item['uploadedBy']}',
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: Icon(_liked.contains(i) ? Icons.favorite : Icons.favorite_border,
                                      color: _liked.contains(i) ? Colors.redAccent : Colors.white70, size: 20),
                                  onPressed: () => _toggleLike(i),
                                ),
                                const SizedBox(width: 4),
                                Text('${_likeCounts[i] ?? 0}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(width: 16),
                                const Icon(Icons.mode_comment_outlined, color: Colors.white54, size: 16),
                                const SizedBox(width: 4),
                                Text('${(_comments[i] ?? []).length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ...(_comments[i] ?? []).map((c) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(c, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                )),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: i == _current ? _commentCtrl : null,
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                    decoration: const InputDecoration(
                                      hintText: 'Add a comment...',
                                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                                      isDense: true,
                                      border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.send, color: AppColors.brass, size: 18),
                                  onPressed: () => _addComment(i),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(
              top: 4, right: 4,
              child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ),
            if (_current > 0)
              Positioned(
                left: 4, top: 0, bottom: 60,
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
                    onPressed: () => _go(-1),
                  ),
                ),
              ),
            if (_current < widget.items.length - 1)
              Positioned(
                right: 4, top: 0, bottom: 60,
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.white, size: 32),
                    onPressed: () => _go(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

