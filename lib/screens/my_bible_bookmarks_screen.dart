import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'bible_screen.dart';

class MyBibleBookmarksScreen extends StatefulWidget {
  const MyBibleBookmarksScreen({super.key});

  @override
  State<MyBibleBookmarksScreen> createState() => _MyBibleBookmarksScreenState();
}

class _MyBibleBookmarksScreenState extends State<MyBibleBookmarksScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getMyBibleBookmarks();
  }

  void _refresh() => setState(() { _future = FirestoreService().getMyBibleBookmarks(); });

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
                  const Text('My Bible Bookmarks', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  final bookmarks = snap.data ?? [];
                  if (bookmarks.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No bookmarks yet - tap the bookmark icon while reading to save a chapter here.', style: TextStyle(color: Colors.black45)),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: bookmarks.length,
                    itemBuilder: (context, i) {
                      final b = bookmarks[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        color: AppColors.paperDark,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.bookmark, color: AppColors.brass),
                          title: Text('${b['bookName'] ?? ''} ${b['chapter']}'),
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => BibleScreen(citation: '${b['bookName']} ${b['chapter']}:1', label: 'Bookmarked'),
                            ));
                            _refresh();
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                            onPressed: () async {
                              await FirestoreService().removeBibleBookmark(b['translationCode'], b['bookCode'], b['chapter']);
                              _refresh();
                            },
                          ),
                        ),
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