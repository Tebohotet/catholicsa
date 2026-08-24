import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class PriestProfileScreen extends StatelessWidget {
  final String parishId;
  final String priestId;
  const PriestProfileScreen({super.key, required this.parishId, required this.priestId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: FutureBuilder<Map<String, dynamic>>(
        future: FirestoreService().getPriest(parishId, priestId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snap.error}')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final p = snap.data!;
          final name = p['name'] as String? ?? '';
          final role = p['role'] as String? ?? '';
          final bio = p['bio'] as String?;
          final isPrivate = p['isPrivate'] as bool? ?? false;
          final initials = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join();

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.stone, AppColors.stoneDark]),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 64, height: 64,
                              decoration: const BoxDecoration(color: AppColors.paperDark, shape: BoxShape.circle),
                              child: Center(child: Text(initials, style: const TextStyle(fontFamily: appSerif, fontSize: 22, color: AppColors.stone))),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                                  Text(role, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                  const SizedBox(height: 6),
                                  Pill(isPrivate ? 'Private Account' : 'Public Profile', tone: 'outline'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionLabel(numeral: 'I', title: 'Background'),
                          Text(
                            bio ?? 'No background added yet — the parish admin can add this from their profile settings.',
                            style: TextStyle(fontSize: 13, color: bio == null ? Colors.black45 : Colors.black87, fontStyle: bio == null ? FontStyle.italic : FontStyle.normal),
                          ),
                          const SizedBox(height: 28),

                          const SectionLabel(numeral: 'II', title: 'Posts'),
                          Container(
                            padding: const EdgeInsets.all(16),
                            color: AppColors.paperDark,
                            child: const Text(
                              'A real post feed (with likes and video uploads) needs its own content '
                              'system — a posts collection, moderation, and storage for media. Worth '
                              'building as its own feature once the core app is stable, not bolted on here.',
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ),
                          const SizedBox(height: 28),

                          const SectionLabel(numeral: 'III', title: 'Message'),
                          Container(
                            padding: const EdgeInsets.all(16),
                            color: AppColors.paperDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'In-app chat needs a real messaging system — its own data model, '
                                  'security rules so only the two people in a conversation can read it, '
                                  'and a notifications setup. That is a bigger, separate build.',
                                  style: TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: null,
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.black38, side: const BorderSide(color: Colors.black26)),
                                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                                  label: const Text('Chat (coming later)'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
