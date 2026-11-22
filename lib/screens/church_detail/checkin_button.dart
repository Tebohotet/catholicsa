import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// "I'm here" - a one-tap, honest-system check-in (no GPS proof, same
/// trust level as the rest of this app's gamification - see
/// church_checkin_service.dart's own notes). Shows which church, if any,
/// this device last checked into this week, so tapping again doesn't
/// look like nothing happened.
class CheckInButton extends StatefulWidget {
  final String parishId;
  final String parishName;
  final String churchId;
  final String churchName;
  const CheckInButton({
    super.key,
    required this.parishId,
    required this.parishName,
    required this.churchId,
    required this.churchName,
  });

  @override
  State<CheckInButton> createState() => _CheckInButtonState();
}

class _CheckInButtonState extends State<CheckInButton> {
  bool _loading = false;
  bool _checkedInThisWeek = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final uid = AuthService().currentUser?.uid;
    if (uid == null) return;
    final week = await FirestoreService().getLastCheckInWeek(uid);
    if (mounted && week != null) {
      setState(() => _checkedInThisWeek = FirestoreService().isCurrentWeek(week));
    }
  }

  Future<void> _checkIn() async {
    if (AuthService().currentUser == null) {
      final user = await AuthService().signInWithGoogle();
      if (user == null) return;
    }
    setState(() => _loading = true);
    try {
      await FirestoreService().checkInAtChurch(
        parishId: widget.parishId,
        parishName: widget.parishName,
        churchId: widget.churchId,
        churchName: widget.churchName,
      );
      if (mounted) {
        setState(() { _checkedInThisWeek = true; _loading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Checked in at ${widget.churchName}.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: _checkedInThisWeek ? AppColors.brass : AppColors.ink,
        side: BorderSide(color: _checkedInThisWeek ? AppColors.brass : AppColors.ink.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      ),
      onPressed: _loading ? null : _checkIn,
      icon: _loading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(_checkedInThisWeek ? Icons.check_circle : Icons.check_circle_outline, size: 17),
      label: Text(_checkedInThisWeek ? "I'm here (again)" : "I'm here"),
    );
  }
}
