import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../services/engagement_service.dart';
import '../../theme/app_theme.dart';

import 'package:firebase_auth/firebase_auth.dart';

class CommentsSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const CommentsSection({super.key, required this.parishId, required this.churchId});

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getComments(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getComments(widget.parishId, widget.churchId); });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return Text('Error: ${snap.error}');
            if (!snap.hasData) return const LinearProgressIndicator();
            final comments = snap.data!;
            if (comments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('No comments yet — be the first to share your experience.', style: TextStyle(fontSize: 12, color: Colors.black45)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: comments.map((c) => _CommentTile(
                comment: c,
                parishId: widget.parishId,
                churchId: widget.churchId,
                onChanged: _refresh,
              )).toList(),
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () async {
            final posted = await showDialog<bool>(
              context: context,
              builder: (_) => _AddCommentDialog(parishId: widget.parishId, churchId: widget.churchId),
            );
            if (posted == true) _refresh();
          },
          icon: const Icon(Icons.rate_review_outlined, size: 16),
          label: const Text('Write a comment'),
        ),
      ],
    );
  }
}

class _CommentTile extends StatefulWidget {
  final Map<String, dynamic> comment;
  final String parishId;
  final String churchId;
  final VoidCallback onChanged;
  const _CommentTile({required this.comment, required this.parishId, required this.churchId, required this.onChanged});

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool? _liked;
  bool _busy = false;

  String get _commentId => widget.comment['id'];
  bool get _isMine => widget.comment['userId'] != null && widget.comment['userId'] == AuthService().currentUser?.uid;

  @override
  void initState() {
    super.initState();
    FirestoreService().isCommentLikedByMe(widget.parishId, widget.churchId, _commentId)
        .then((v) { if (mounted) setState(() { _liked = v; }); });
  }

  Future<void> _toggleLike() async {
    if (AuthService().currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in to like a comment.')));
      return;
    }
    setState(() { _liked = !(_liked ?? false); _busy = true; });
    try {
      await FirestoreService().toggleCommentLike(widget.parishId, widget.churchId, _commentId);
      if (_liked == true) EngagementService().recordActivity('like');
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  Future<void> _report() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Report Comment', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'What\'s wrong with it?'), maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirestoreService().reportComment(
        parishId: widget.parishId, churchId: widget.churchId, commentId: _commentId,
        reason: reasonCtrl.text.trim().isEmpty ? 'No reason given' : reasonCtrl.text.trim(),
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reported - the parish office will review it.')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Delete Comment?', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: const Text('This can\'t be undone.', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirestoreService().deleteComment(widget.parishId, widget.churchId, _commentId);
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final rating = (comment['rating'] as num?)?.toInt() ?? 0;
    final reply = comment['reply'] as Map<String, dynamic>?;
    final likeCount = (comment['likeCount'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle, size: 18, color: AppColors.stone),
              const SizedBox(width: 6),
              Text(comment['userDisplayName'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 8),
              Row(children: List.generate(5, (i) => Icon(i < rating ? Icons.star : Icons.star_border, size: 13, color: AppColors.brass))),
            ],
          ),
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.only(left: 24), child: Text(comment['text'] ?? '', style: const TextStyle(fontSize: 13))),
          if (reply != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 8),
              child: Container(
                padding: const EdgeInsets.only(left: 10),
                decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.sage, width: 2))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(reply['from'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 12, color: AppColors.sage),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(reply['text'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(_liked == true ? Icons.favorite : Icons.favorite_border, size: 16, color: _liked == true ? Colors.redAccent : Colors.black45),
                  onPressed: _busy ? null : _toggleLike,
                ),
                if (likeCount > 0) Text('$likeCount', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.flag_outlined, size: 15, color: Colors.black45),
                  tooltip: 'Report',
                  onPressed: _report,
                ),
                if (_isMine)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(Icons.delete_outline, size: 15, color: Colors.black45),
                    tooltip: 'Delete',
                    onPressed: _delete,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCommentDialog extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _AddCommentDialog({required this.parishId, required this.churchId});

  @override
  State<_AddCommentDialog> createState() => _AddCommentDialogState();
}

class _AddCommentDialogState extends State<_AddCommentDialog> {
  User? _user;
  int _rating = 5;
  final _textCtrl = TextEditingController();
  bool _submitting = false;
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _user = AuthService().currentUser;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() { _signingIn = true; });
    try {
      final user = await AuthService().signInWithGoogle();
      if (user != null && mounted) setState(() { _user = user; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() { _signingIn = false; });
    }
  }

  Future<void> _submit() async {
    if (_textCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please write something first.')));
      return;
    }
    setState(() { _submitting = true; });
    try {
      await FirestoreService().addComment(
        parishId: widget.parishId, churchId: widget.churchId,
        rating: _rating, text: _textCtrl.text.trim(),
      );
      EngagementService().recordActivity('comment');
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not post: $e')));
      }
    } finally {
      if (mounted) setState(() { _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Write a Comment', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: const Text('Sign in first so your comment is tied to your account.', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _signingIn ? null : _signIn,
            icon: _signingIn
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.login, size: 16),
            label: const Text('Sign in with Google'),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('Write a Comment', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(5, (i) => IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(i < _rating ? Icons.star : Icons.star_border, color: AppColors.brass),
              onPressed: () => setState(() => _rating = i + 1),
            )),
          ),
          const SizedBox(height: 8),
          TextField(controller: _textCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Share your experience...')),
        ],
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Post'),
        ),
      ],
    );
  }
}