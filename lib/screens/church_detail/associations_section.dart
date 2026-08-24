import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';


class AssociationsSection extends StatelessWidget {
  final String parishId;
  final String churchId;
  const AssociationsSection({super.key, required this.parishId, required this.churchId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: FirestoreService().getAssociations(parishId, churchId),
      builder: (context, snap) {
        if (snap.hasError) return Text('Error: ${snap.error}');
        if (!snap.hasData) return const LinearProgressIndicator();
        final associations = snap.data!;
        if (associations.isEmpty) {
          return const Text('No associations listed yet.', style: TextStyle(fontSize: 12, color: Colors.black45));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: associations.map((a) {
            final hasMeeting = a['meetingDay'] != null && a['meetingTime'] != null;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(border: Border.all(color: AppColors.ink.withValues(alpha: 0.15))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(a['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                      if (a['purpose'] != null)
                        InkWell(
                          onTap: () => _showDonateDialog(context, parishId, churchId, a['name'] as String),
                          child: const Pill('Donate'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasMeeting ? 'Meets ${a['meetingDay']}, ${a['meetingTime']}' : 'Meeting time: contact the parish office',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  Text(
                    a['contactPerson'] != null ? 'Contact: ${a['contactPerson']}' : 'To join: contact the parish office',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

void _showDonateDialog(BuildContext context, String parishId, String churchId, String associationName) {
  showDialog(context: context, builder: (_) => _DonateDialog(parishId: parishId, churchId: churchId, associationName: associationName));
}

Widget _bankRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
      ],
    ),
  );
}

/// Two steps, same shape as the marketplace Buy flow: enter the donation
/// details, then - since bank deposit is the only method until real
/// checkout is connected - show where to pay and let them attach proof.
/// No coupon/quantity here since a donation isn't tied to a specific item.
class _DonateDialog extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String associationName;
  const _DonateDialog({required this.parishId, required this.churchId, required this.associationName});

  @override
  State<_DonateDialog> createState() => _DonateDialogState();
}

class _DonateDialogState extends State<_DonateDialog> {
  final _amountCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _placing = false;
  bool _uploadingProof = false;

  String? _donationId;
  Map<String, dynamic>? _bankDetails;

  @override
  void initState() {
    super.initState();
    final user = AuthService().currentUser;
    if (user != null) _nameCtrl.text = user.displayName ?? '';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _placeDonation() async {
    if (AuthService().currentUser == null) {
      try {
        await AuthService().signInWithGoogle();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
        return;
      }
    }
    if (!mounted) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0 || _nameCtrl.text.trim().isEmpty || _contactCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount, your name, and a contact number.')));
      return;
    }
    setState(() => _placing = true);
    try {
      final id = await FirestoreService().createDonation(
        parishId: widget.parishId, churchId: widget.churchId,
        associationName: widget.associationName, amount: amount,
        donorName: _nameCtrl.text.trim(), donorContact: _contactCtrl.text.trim(),
      );
      final bank = await FirestoreService().getBankDetails(widget.parishId);
      if (mounted) setState(() { _donationId = id; _bankDetails = bank; _placing = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _placing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not record donation: $e')));
      }
    }
  }

  Future<void> _uploadProof() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'], withData: true);
    if (result == null || result.files.isEmpty || _donationId == null) return;
    final file = result.files.single;
    if (file.bytes == null) return;
    setState(() => _uploadingProof = true);
    try {
      await FirestoreService().uploadDonationProof(
        parishId: widget.parishId, churchId: widget.churchId,
        donationId: _donationId!, bytes: file.bytes!, fileName: file.name,
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(content: Text('Proof of payment uploaded — thank you, the parish will confirm it shortly.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _uploadingProof = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_donationId != null) {
      return AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Complete Your Donation', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_bankDetails == null)
                const Text('This parish hasn\'t set up bank deposit details yet — contact the parish office to arrange your donation.', style: TextStyle(fontSize: 13, color: Colors.black54))
              else ...[
                const Text('Bank Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                _bankRow('Account Name', _bankDetails!['accountName'] ?? ''),
                _bankRow('Bank', _bankDetails!['bank'] ?? ''),
                _bankRow('Account Number', _bankDetails!['accountNumber'] ?? ''),
                _bankRow('Branch Code', _bankDetails!['branchCode'] ?? ''),
                _bankRow('Reference', widget.associationName.replaceAll(' ', '').toUpperCase()),
              ],
              const SizedBox(height: 16),
              const Text('Once you\'ve made the deposit, upload a screenshot or photo of the proof below.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _uploadingProof ? null : _uploadProof,
            icon: _uploadingProof
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_outlined, size: 16),
            label: const Text('Upload Proof of Payment'),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text('Donate to ${widget.associationName}', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _amountCtrl, decoration: const InputDecoration(labelText: 'Amount (ZAR)', prefixText: 'R '), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 10),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Your name')),
            const SizedBox(height: 10),
            TextField(controller: _contactCtrl, decoration: const InputDecoration(labelText: 'Contact number'), keyboardType: TextInputType.phone),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _placing ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _placing ? null : _placeDonation,
          child: _placing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Continue'),
        ),
      ],
    );
  }
}

