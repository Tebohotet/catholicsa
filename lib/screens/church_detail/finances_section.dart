import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../models/parish.dart';


class FinancesSection extends StatelessWidget {
  final Parish parish;
  final String churchId;
  const FinancesSection({super.key, required this.parish, required this.churchId});

  @override
  Widget build(BuildContext context) {
    final financesOn = parish.featureFlags['finances'] ?? false;
    if (!financesOn) {
      return const Text('This parish has not made finances public.', style: TextStyle(fontSize: 13, color: Colors.black54));
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: FirestoreService().getFundraisers(parish.id, churchId),
      builder: (context, snap) {
        if (snap.hasError) return Text('Error: ${snap.error}');
        if (!snap.hasData) return const LinearProgressIndicator();
        final list = snap.data!;
        if (list.isEmpty) {
          return const Text('No fundraisers listed right now.', style: TextStyle(fontSize: 12, color: Colors.black45));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: list.map((f) {
            final goal = (f['goalAmount'] as num?)?.toDouble() ?? 0;
            final raised = (f['raisedAmount'] as num?)?.toDouble() ?? 0;
            final pct = goal > 0 ? (raised / goal).clamp(0.0, 1.0) : 0.0;
            final currency = f['currency'] ?? 'ZAR';
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.volunteer_activism, size: 16, color: AppColors.brass),
                      const SizedBox(width: 8),
                      Text(f['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: AppColors.paperDark, color: AppColors.brass),
                  ),
                  const SizedBox(height: 4),
                  Text('$currency ${raised.toStringAsFixed(0)} raised of $currency ${goal.toStringAsFixed(0)} goal',
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

