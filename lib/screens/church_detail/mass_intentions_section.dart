import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// A Mass Intention is a request for a specific Mass to be offered for
/// someone (living or deceased) or a special purpose. This lets a
/// parishioner submit that request - the actual scheduling of which Mass
/// it gets attached to is still done by the parish office, this just
/// replaces a phone call or a note dropped at the office.
class MassIntentionsSection extends StatelessWidget {
  final String parishId;
  final String churchId;
  final String churchName;
  const MassIntentionsSection({super.key, required this.parishId, required this.churchId, required this.churchName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Request a Mass to be offered for a loved one, an intention, or a special occasion. '
          'The parish office will confirm the date once scheduled.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => _MassIntentionDialog(parishId: parishId, churchId: churchId, churchName: churchName),
          ),
          icon: const Icon(Icons.local_florist_outlined, size: 16),
          label: const Text('Request a Mass Intention'),
        ),
      ],
    );
  }
}

class _MassIntentionDialog extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String churchName;
  const _MassIntentionDialog({required this.parishId, required this.churchId, required this.churchName});

  @override
  State<_MassIntentionDialog> createState() => _MassIntentionDialogState();
}

class _MassIntentionDialogState extends State<_MassIntentionDialog> {
  final _nameCtrl = TextEditingController();
  final _intentionCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _intentionCtrl.dispose();
    _dateCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _intentionCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in your name, the intention, and a contact number.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await FirestoreService().submitMassIntentionRequest(
        parishId: widget.parishId,
        churchId: widget.churchId,
        requesterName: _nameCtrl.text.trim(),
        intentionFor: _intentionCtrl.text.trim(),
        preferredDate: _dateCtrl.text.trim().isEmpty ? null : _dateCtrl.text.trim(),
        contactPhone: _phoneCtrl.text.trim(),
        contactEmail: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('Request sent — the parish office will confirm which Mass it will be offered at.')),
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
      return AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text('Mass Intention — ${widget.churchName}', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
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
      title: Text('Mass Intention — ${widget.churchName}', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your name and email are filled in from your account.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Your name')),
            const SizedBox(height: 10),
            TextField(
              controller: _intentionCtrl, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Intention', hintText: 'e.g. "+John Smith" or "Thanksgiving for..."'),
            ),
            const SizedBox(height: 10),
            TextField(controller: _dateCtrl, decoration: const InputDecoration(labelText: 'Preferred date (optional)', hintText: 'e.g. Sunday 9am, or a specific date')),
            const SizedBox(height: 10),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Contact number'), keyboardType: TextInputType.phone),
            const SizedBox(height: 10),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
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
