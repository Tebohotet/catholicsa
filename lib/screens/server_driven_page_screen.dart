import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/block_registry.dart';

/// The generic renderer - one screen class handles every custom page ever
/// created, since the actual content comes entirely from the block list
/// in Firestore. Adding a new page never touches this file.
class ServerDrivenPageScreen extends StatelessWidget {
  final String pageId;
  const ServerDrivenPageScreen({super.key, required this.pageId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: FutureBuilder<Map<String, dynamic>?>(
        future: FirestoreService().getCustomPage(pageId),
        builder: (context, snap) {
          // Same bug class fixed in Readings and Bible screens - hasData
          // is false whenever getCustomPage legitimately resolves to null
          // (a deleted or never-existing page), indistinguishable from
          // still loading if checked that way.
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final page = snap.data;
          if (page == null) {
            return const Center(child: Text('This page no longer exists.'));
          }
          final blocks = (page['blocks'] as List?) ?? [];
          return SafeArea(
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
                      Text(page['title'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                    ],
                  ),
                ),
                Expanded(
                  child: blocks.isEmpty
                      ? const Center(child: Text('This page has no content yet.', style: TextStyle(color: Colors.black45)))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: blocks.map((b) => BlockRegistry.build(context, (b as Map).cast<String, dynamic>())).toList(),
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