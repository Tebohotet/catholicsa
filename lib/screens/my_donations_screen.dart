import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';

/// Same reasoning as My Orders - a donor previously got one push
/// notification on status change and then had nowhere in the app to
/// ever see their donation history or read an admin's note again.
class MyDonationsScreen extends StatefulWidget {
  const MyDonationsScreen({super.key});

  @override
  State<MyDonationsScreen> createState() => _MyDonationsScreenState();
}

class _MyDonationsScreenState extends State<MyDonationsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getMyDonations(AuthService().currentUser?.uid ?? '');
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'proof_submitted':
        return 'Proof submitted — awaiting review';
      case 'approved':
        return 'Approved — thank you';
      case 'wrong_bank':
        return 'Wrong bank details used';
      case 'rejected':
        return 'Not approved';
      default:
        return 'Awaiting payment';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'approved':
        return AppColors.sage;
      case 'wrong_bank':
      case 'rejected':
        return Colors.redAccent;
      default:
        return AppColors.stone;
    }
  }

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
                  const Text('My Donations', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AsyncSection<List<Map<String, dynamic>>>(
                  future: _future,
                  isEmpty: (l) => l.isEmpty,
                  emptyMessage: 'No donations yet.',
                  builder: (context, donations) => ListView.builder(
                    itemCount: donations.length,
                    itemBuilder: (context, i) {
                      final d = donations[i];
                      final status = d['status'] as String?;
                      final adminNote = d['adminNote'] as String?;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        color: AppColors.paperDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(child: Text(d['associationName'] ?? 'Donation', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                              Text('R${(d['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}', style: const TextStyle(fontSize: 13, color: AppColors.brass, fontWeight: FontWeight.w600)),
                            ]),
                            const SizedBox(height: 4),
                            Text(_statusLabel(status), style: TextStyle(fontSize: 12, color: _statusColor(status), fontWeight: FontWeight.w600)),
                            if ((status == 'wrong_bank' || status == 'rejected') && adminNote != null && adminNote.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Note: $adminNote', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}