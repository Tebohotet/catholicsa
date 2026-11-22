import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// A real back-and-forth conversation with one other user - the project
/// owner's explicit ask ("message the person with the app"), not just a
/// one-off note. Finds or creates the conversation on open, then listens
/// live via streamMessages.
class ChatScreen extends StatefulWidget {
  final String otherUid;
  final String otherName;
  const ChatScreen({super.key, required this.otherUid, required this.otherName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String? _conversationId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (AuthService().currentUser == null) {
      final user = await AuthService().signInWithGoogle();
      if (user == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
    }
    try {
      final id = await FirestoreService().getOrCreateConversation(widget.otherUid);
      if (mounted) setState(() => _conversationId = id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _send() async {
    final text = _textCtrl.text;
    final conversationId = _conversationId;
    if (text.trim().isEmpty || conversationId == null) return;
    setState(() => _sending = true);
    _textCtrl.clear();
    try {
      await FirestoreService().sendMessage(conversationId: conversationId, text: text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = AuthService().currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.stone,
        foregroundColor: Colors.white,
        title: Text(widget.otherName, style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _conversationId == null
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<List<Map<String, dynamic>>>(
                      stream: FirestoreService().streamMessages(_conversationId!),
                      builder: (context, snap) {
                        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                        final messages = snap.data!;
                        if (messages.isEmpty) {
                          return const Center(child: Text('Say hello.', style: TextStyle(color: Colors.black45)));
                        }
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                        });
                        return ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(12),
                          itemCount: messages.length,
                          itemBuilder: (context, i) {
                            final m = messages[i];
                            final mine = m['senderId'] == myUid;
                            final at = m['createdAt'] as Timestamp?;
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                constraints: const BoxConstraints(maxWidth: 280),
                                decoration: BoxDecoration(
                                  color: mine ? AppColors.brass : AppColors.paperDark,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m['text'] ?? '', style: TextStyle(fontSize: 14, color: mine ? Colors.white : AppColors.ink)),
                                    if (at != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          DateFormat('d MMM, HH:mm').format(at.toDate()),
                                          style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : Colors.black45),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        decoration: const InputDecoration(hintText: 'Message...'),
                        onSubmitted: (_) => _send(),
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: AppColors.brass),
                      onPressed: (_sending || _conversationId == null) ? null : _send,
                      icon: const Icon(Icons.send, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
