import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'share_button.dart';
import 'async_section.dart';

typedef BlockBuilder = Widget Function(BuildContext context, Map<String, dynamic> config);

/// Every block type the server-driven page renderer knows how to build.
/// A page definition in Firestore is just an ordered list of
/// {type, config} - assembling EXISTING types into a NEW page is pure
/// data entry from here on, no code. A genuinely new kind of interaction
/// (nothing like it exists yet) still needs one entry added here, once -
/// after that it's reusable by any future page for free.
class BlockRegistry {
  static final Map<String, BlockBuilder> _blocks = {
    'textBlock': (context, config) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            config['text'] ?? '',
            style: TextStyle(
              fontSize: (config['size'] as num?)?.toDouble() ?? 14,
              fontFamily: config['heading'] == true ? appSerif : null,
            ),
          ),
        ),
    'spacer': (context, config) => SizedBox(height: (config['height'] as num?)?.toDouble() ?? 16),
    'shareButton': (context, config) => Align(
          alignment: Alignment.centerLeft,
          child: ShareButton(
            title: config['title'] ?? '',
            body: config['body'],
            url: config['url'],
          ),
        ),
    'notesList': (context, config) => const NotesListBlock(),
  };

  /// Unknown block types degrade gracefully to a visible placeholder
  /// instead of crashing the page.
  static Widget build(BuildContext context, Map<String, dynamic> blockData) {
    final type = blockData['type'] as String?;
    final config = (blockData['config'] as Map?)?.cast<String, dynamic>() ?? {};
    final builder = _blocks[type];
    if (builder == null) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: Colors.red.withValues(alpha: 0.08),
        child: Text('Unknown block type: "$type"', style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
      );
    }
    return builder(context, config);
  }

  static List<String> get availableTypes => _blocks.keys.toList();
}

/// Personal, private notes - the concrete example this system was
/// designed around. Real functionality, not a stub.
class NotesListBlock extends StatefulWidget {
  const NotesListBlock({super.key});

  @override
  State<NotesListBlock> createState() => _NotesListBlockState();
}

class _NotesListBlockState extends State<NotesListBlock> {
  final _controller = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getMyNotes();
  }

  void _refresh() => setState(() { _future = FirestoreService().getMyNotes(); });

  Future<void> _add() async {
    if (_controller.text.trim().isEmpty) return;
    await FirestoreService().addNote(_controller.text.trim());
    _controller.clear();
    _refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(hintText: 'Write a note...'),
                onSubmitted: (_) => _add(),
              ),
            ),
            IconButton(icon: const Icon(Icons.add_circle, color: AppColors.brass), onPressed: _add),
          ],
        ),
        const SizedBox(height: 12),
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No notes yet.',
          builder: (context, notes) => Column(
            children: notes.map((n) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: AppColors.paperDark,
              elevation: 0,
              child: ListTile(
                dense: true,
                title: Text(n['text'] ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  onPressed: () async {
                    await FirestoreService().deleteNote(n['id']);
                    _refresh();
                  },
                ),
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }
}