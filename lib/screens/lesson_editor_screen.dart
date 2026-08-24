import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

/// Real structured content now - heading/text/image blocks, reorderable
/// by drag, instead of one flat textarea. Existing lessons written
/// before this change still work: if a lesson has no blocks yet, this
/// starts with a single text block pre-filled from its old content
/// field, so editing an old lesson doesn't lose anything or require a
/// separate migration step.
class LessonEditorScreen extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String courseId;
  final Map<String, dynamic>? existing;
  final int nextOrder;
  const LessonEditorScreen({super.key, required this.parishId, required this.churchId, required this.courseId, this.existing, required this.nextOrder});

  @override
  State<LessonEditorScreen> createState() => _LessonEditorScreenState();
}

class _ContentBlock {
  String type; // 'heading' | 'text' | 'image'
  final TextEditingController textCtrl = TextEditingController();
  final TextEditingController captionCtrl = TextEditingController();
  String? imageUrl;
  XFile? pickedImage;
  bool uploading = false;

  _ContentBlock({required this.type, this.imageUrl});
}

class _LessonEditorScreenState extends State<LessonEditorScreen> {
  final _titleCtrl = TextEditingController();
  final List<_ContentBlock> _blocks = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e['title'] ?? '';
      final rawBlocks = List<Map<String, dynamic>>.from(e['blocks'] ?? []);
      if (rawBlocks.isNotEmpty) {
        for (final b in rawBlocks) {
          final block = _ContentBlock(type: b['type'] ?? 'text', imageUrl: b['imageUrl']);
          block.textCtrl.text = b['text'] ?? '';
          block.captionCtrl.text = b['caption'] ?? '';
          _blocks.add(block);
        }
      } else if ((e['content'] as String?)?.isNotEmpty ?? false) {
        // Backward compat - an old lesson with only the flat content
        // field becomes a single pre-filled text block here.
        final block = _ContentBlock(type: 'text');
        block.textCtrl.text = e['content'];
        _blocks.add(block);
      }
    }
    if (_blocks.isEmpty) _blocks.add(_ContentBlock(type: 'text'));
  }

  Future<void> _pickImageFor(_ContentBlock block) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (picked != null) setState(() => block.pickedImage = picked);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final blockMaps = <Map<String, dynamic>>[];
      for (final b in _blocks) {
        if (b.type == 'image') {
          String? url = b.imageUrl;
          if (b.pickedImage != null) {
            url = await FirestoreService().uploadLessonImage(b.pickedImage!);
          }
          if (url == null) continue; // an image block with nothing chosen yet - skip rather than save a broken block
          blockMaps.add({'type': 'image', 'imageUrl': url, 'caption': b.captionCtrl.text.trim()});
        } else {
          if (b.textCtrl.text.trim().isEmpty) continue; // skip genuinely empty text/heading blocks
          blockMaps.add({'type': b.type, 'text': b.textCtrl.text.trim()});
        }
      }
      if (blockMaps.isEmpty) {
        setState(() => _saving = false);
        return;
      }

      if (widget.existing != null) {
        await FirestoreService().updateLesson(
          parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId,
          lessonId: widget.existing!['id'], title: _titleCtrl.text.trim(), blocks: blockMaps,
          order: (widget.existing!['order'] as num?)?.toInt() ?? widget.nextOrder,
        );
      } else {
        await FirestoreService().addLesson(
          parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId,
          title: _titleCtrl.text.trim(), blocks: blockMaps, order: widget.nextOrder,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _blockEditor(_ContentBlock block, int index) {
    return Container(
      key: ValueKey(block),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      color: AppColors.paperDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.drag_handle, size: 18, color: Colors.black38),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: block.type,
              items: const [
                DropdownMenuItem(value: 'heading', child: Text('Heading', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'text', child: Text('Text', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(value: 'image', child: Text('Image', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (v) => setState(() => block.type = v!),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              onPressed: _blocks.length == 1 ? null : () => setState(() => _blocks.removeAt(index)),
            ),
          ]),
          if (block.type == 'image') ...[
            if (block.pickedImage != null)
              FutureBuilder<List<int>>(
                future: block.pickedImage!.readAsBytes(),
                builder: (context, snap) => snap.hasData
                    ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(Uint8List.fromList(snap.data!), height: 140, fit: BoxFit.cover))
                    : const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
              )
            else if (block.imageUrl != null)
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(block.imageUrl!, height: 140, fit: BoxFit.cover)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
              onPressed: () => _pickImageFor(block),
              icon: const Icon(Icons.image_outlined, size: 14),
              label: Text(block.imageUrl != null || block.pickedImage != null ? 'Replace Image' : 'Choose Image', style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 6),
            TextField(controller: block.captionCtrl, decoration: const InputDecoration(labelText: 'Caption (optional)'), style: const TextStyle(fontSize: 13)),
          ] else
            TextField(
              controller: block.textCtrl,
              maxLines: block.type == 'heading' ? 1 : 6,
              style: block.type == 'heading' ? const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, fontFamily: appSerif) : const TextStyle(fontSize: 14),
              decoration: InputDecoration(labelText: block.type == 'heading' ? 'Heading text' : 'Paragraph text', border: InputBorder.none),
            ),
        ],
      ),
    );
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
                  Text(widget.existing != null ? 'Edit Lesson' : 'Add Lesson', style: const TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Lesson title')),
                  const SizedBox(height: 16),
                  const Text('Content Blocks', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _blocks.removeAt(oldIndex);
                        _blocks.insert(newIndex, item);
                      });
                    },
                    children: [for (var i = 0; i < _blocks.length; i++) _blockEditor(_blocks[i], i)],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                    onPressed: () => setState(() => _blocks.add(_ContentBlock(type: 'text'))),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Block'),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Lesson'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}