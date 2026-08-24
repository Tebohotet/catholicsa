import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../models/church.dart';

import 'package:firebase_auth/firebase_auth.dart';

class ConfessionsSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String churchName;
  const ConfessionsSection({super.key, required this.parishId, required this.churchId, required this.churchName});

  @override
  State<ConfessionsSection> createState() => _ConfessionsSectionState();
}

class _ConfessionsSectionState extends State<ConfessionsSection> {
  late Future<List<ConfessionTime>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getConfessionTimes(widget.parishId, widget.churchId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ConfessionTime>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Text('Error: ${snap.error}');
        if (!snap.hasData) return const LinearProgressIndicator();
        final times = snap.data!;
        if (times.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('No fixed confession times listed for this church yet.', style: TextStyle(fontSize: 12, color: Colors.black45)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                onPressed: () => _showBookingForm(context),
                icon: const Icon(Icons.calendar_month, size: 16),
                label: const Text('Book a Confession'),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: times.map((t) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                const Icon(Icons.watch_later_outlined, size: 14, color: AppColors.brass),
                const SizedBox(width: 8),
                Text(t.dayOfWeek, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 8),
                Text(t.endTime != null ? '${t.startTime} – ${t.endTime}' : 'From ${t.startTime}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                if (t.notes != null) ...[
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.notes!, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black45))),
                ],
              ],
            ),
          )).toList(),
        );
      },
    );
  }

  void _showBookingForm(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _ConfessionBookingDialog(
        parishId: widget.parishId, churchId: widget.churchId, churchName: widget.churchName,
      ),
    );
  }
}

class _ConfessionBookingDialog extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String churchName;
  const _ConfessionBookingDialog({required this.parishId, required this.churchId, required this.churchName});

  @override
  State<_ConfessionBookingDialog> createState() => _ConfessionBookingDialogState();
}

class _ConfessionBookingDialogState extends State<_ConfessionBookingDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _availabilityCtrl = TextEditingController();
  bool _submitting = false;
  bool _signingIn = false;
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = AuthService().currentUser;
    if (_user != null) {
      _nameCtrl.text = _user!.displayName ?? '';
      _emailCtrl.text = _user!.email ?? '';
    }
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    try {
      final user = await AuthService().signInWithGoogle();
      if (user != null && mounted) {
        setState(() {
          _user = user;
          _nameCtrl.text = user.displayName ?? '';
          _emailCtrl.text = user.email ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _availabilityCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty || _availabilityCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in your name, contact number, and availability.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await FirestoreService().submitConfessionBooking(
        parishId: widget.parishId,
        churchId: widget.churchId,
        name: _nameCtrl.text.trim(),
        contactPhone: _phoneCtrl.text.trim(),
        contactEmail: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        availability: _availabilityCtrl.text.trim(),
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('Request sent — the parish office will contact you to confirm a time.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send request: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      // Signing in first means the request is tied to a real account rather
      // than an anonymous form anyone could spam or fake.
      return AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text('Book a Confession — ${widget.churchName}', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: const Text(
          'Sign in first so this request is tied to your account — the parish office needs to know who\'s asking.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _signingIn ? null : _signIn,
            icon: _signingIn
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.login, size: 16),
            label: const Text('Sign in with Google'),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text('Book a Confession — ${widget.churchName}', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your name and email are filled in from your account — just add a contact number and when you\'re available.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Your name')),
            const SizedBox(height: 10),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Contact number'), keyboardType: TextInputType.phone),
            const SizedBox(height: 10),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 10),
            TextField(controller: _availabilityCtrl, decoration: const InputDecoration(labelText: 'When are you available?', hintText: 'e.g. Weekday afternoons'), maxLines: 2),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Send Request'),
        ),
      ],
    );
  }
}

