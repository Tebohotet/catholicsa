import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

import '../priest_profile_screen.dart';

class ClergySection extends StatelessWidget {
  final String parishId;
  const ClergySection({super.key, required this.parishId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: FirestoreService().getPriests(parishId),
      builder: (context, snap) {
        if (snap.hasError) return Text('Error: ${snap.error}');
        if (!snap.hasData) return const LinearProgressIndicator();
        final priests = snap.data!;
        if (priests.isEmpty) {
          return const Text('No clergy listed yet.', style: TextStyle(fontSize: 12, color: Colors.black45));
        }
        return Wrap(
          spacing: 12, runSpacing: 12,
          children: priests.map((p) {
            final name = p['name'] as String? ?? '';
            final initials = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join();
            return InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PriestProfileScreen(parishId: parishId, priestId: p['id'] as String),
              )),
              child: Container(
              width: 240,
              padding: const EdgeInsets.all(10),
              color: AppColors.paperDark,
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(color: AppColors.stone, shape: BoxShape.circle),
                    child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(p['role'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        if (p['notes'] != null)
                          Text(p['notes'], style: const TextStyle(fontSize: 10, color: Colors.black45, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

