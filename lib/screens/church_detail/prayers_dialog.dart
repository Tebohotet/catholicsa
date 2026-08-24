import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_section.dart';


class PrayersDialog extends StatelessWidget {
  final String parishId;
  final String churchId;
  const PrayersDialog({super.key, required this.parishId, required this.churchId});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.paper,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Prayers', style: TextStyle(fontFamily: appSerif, fontSize: 18))),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: AsyncSection<List<Map<String, dynamic>>>(
                  future: FirestoreService().getPrayers(parishId, churchId),
                  isEmpty: (l) => l.isEmpty,
                  emptyMessage: 'No prayers added for this church yet.',
                  builder: (context, prayers) => ListView.builder(
                    shrinkWrap: true,
                    itemCount: prayers.length,
                    itemBuilder: (context, i) {
                      final p = prayers[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(p['title'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 16))),
                                Pill(p['language'] ?? 'EN', tone: 'outline'),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(p['text'] ?? '', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
