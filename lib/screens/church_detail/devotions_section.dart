import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';


class DevotionsSection extends StatelessWidget {
  final String parishId;
  final String churchId;
  const DevotionsSection({super.key, required this.parishId, required this.churchId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: FirestoreService().getDevotions(parishId, churchId),
      builder: (context, snap) {
        if (snap.hasError) return Text('Error: ${snap.error}');
        if (!snap.hasData) return const LinearProgressIndicator();
        final devotions = snap.data!;
        if (devotions.isEmpty) {
          return const Text('No devotions listed yet.', style: TextStyle(fontSize: 12, color: Colors.black45));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: devotions.map((d) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                const Icon(Icons.watch_later_outlined, size: 14, color: AppColors.brass),
                const SizedBox(width: 8),
                Text('${d['dayOfWeek']} ${d['time']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(child: Text('— ${d['name']}', style: const TextStyle(fontSize: 13, color: Colors.black87))),
              ],
            ),
          )).toList(),
        );
      },
    );
  }
}

