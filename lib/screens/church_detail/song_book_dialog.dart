import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';


class SongBookDialog extends StatefulWidget {
  final String parishId;
  final String churchId;
  const SongBookDialog({super.key, required this.parishId, required this.churchId});

  @override
  State<SongBookDialog> createState() => _SongBookDialogState();
}

class _SongBookDialogState extends State<SongBookDialog> {
  final _numberCtrl = TextEditingController();
  Map<String, dynamic>? _result;
  bool _searched = false;
  bool _searching = false;

  Future<void> _search() async {
    final number = int.tryParse(_numberCtrl.text.trim());
    if (number == null) return;
    setState(() { _searching = true; _searched = true; });
    final result = await FirestoreService().getSongByNumber(widget.parishId, widget.churchId, number);
    if (mounted) setState(() { _result = result; _searching = false; });
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('Song Book', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _numberCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Song number', hintText: 'e.g. 245'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                  onPressed: _searching ? null : _search,
                  child: const Text('Find'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_searching) const Center(child: CircularProgressIndicator())
            else if (_searched && _result == null)
              const Text('No song found with that number for this church.', style: TextStyle(fontSize: 13, color: Colors.black54))
            else if (_result != null) ...[
              Text('#${_result!['number']}', style: const TextStyle(color: AppColors.brass, fontWeight: FontWeight.bold, fontSize: 12)),
              Text(_result!['title'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 20)),
              if (_result!['hymnal'] != null)
                Text(_result!['hymnal'], style: const TextStyle(fontSize: 12, color: Colors.black54)),
              Pill(_result!['language'] ?? 'EN', tone: 'outline'),
              if (_result!['lyrics'] != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  child: Text(_result!['lyrics'], style: const TextStyle(fontSize: 13)),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

/// Common prayers are short enough to just list in full - unlike Songs
/// (usually needs a number lookup, may have full pages of lyrics) this
/// works better as a simple browsable list.
