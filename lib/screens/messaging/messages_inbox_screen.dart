import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'chat_screen.dart';

/// The inbox - every conversation this signed-in user is part of, most
/// recently active first. Reached from the Account screen; a specific
/// conversation can also be opened directly from a user's profile
/// without going through here first.
class MessagesInboxScreen extends StatelessWidget {
  const MessagesInboxScreen({super.key});

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
                  const Text('Messages', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: FirestoreService().streamMyConversations(),
                builder: (context, snap) {
                  // Without this, any real error (a missing index still
                  // building, a transient permission hiccup, being
                  // signed out) left this spinning forever instead of
                  // showing anything - snap.hasData never becomes true
                  // after a stream errors, so the old code had no way
                  // to ever leave the loading state.
                  if (snap.hasError) {
                    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snap.error}', textAlign: TextAlign.center)));
                  }
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final conversations = snap.data!;
                  if (conversations.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No conversations yet — message someone from their profile to start one.', style: TextStyle(color: Colors.black45), textAlign: TextAlign.center),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: conversations.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = conversations[i];
                      final at = c['lastMessageAt'] as Timestamp?;
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person, size: 18)),
                        title: Text(c['otherName'] ?? 'Someone', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(
                          c['lastMessage'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: at != null ? Text(DateFormat('d MMM').format(at.toDate()), style: const TextStyle(fontSize: 11, color: Colors.black45)) : null,
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ChatScreen(otherUid: c['otherUid'], otherName: c['otherName'] ?? 'this user'),
                        )),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
