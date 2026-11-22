import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// "I'm here" - only actually checks in if this device's real GPS
/// location is near the church (the project owner's explicit
/// correction: "should appear only if your location is at the place" -
/// an earlier version of this let anyone tap it from anywhere). Same
/// Geolocator flow already used for admin "mark church GPS" (see
/// admin_panel_screen.dart's _useCurrentLocation) - enable/permission
/// check, then compare distance.
///
/// A church whose own GPS was never set for real (still the (0, 0)
/// placeholder every church starts with - see FirestoreService.addChurch)
/// has nothing real to compare against, so check-in there stays an
/// honest tap rather than silently always failing the distance check.
class CheckInButton extends StatefulWidget {
  final String parishId;
  final String parishName;
  final String churchId;
  final String churchName;
  final GeoPoint churchGeopoint;
  const CheckInButton({
    super.key,
    required this.parishId,
    required this.parishName,
    required this.churchId,
    required this.churchName,
    required this.churchGeopoint,
  });

  @override
  State<CheckInButton> createState() => _CheckInButtonState();
}

class _CheckInButtonState extends State<CheckInButton> {
  // Generous enough to cover real GPS drift plus a church's own grounds
  // and parking area, tight enough that "I'm here" from home doesn't work.
  static const _maxDistanceMeters = 200;

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

  bool get _churchHasRealGps => widget.churchGeopoint.latitude != 0 || widget.churchGeopoint.longitude != 0;

  Future<void> _checkIn() async {
    if (AuthService().currentUser == null) {
      final user = await AuthService().signInWithGoogle();
      if (user == null) return;
    }
    setState(() => _loading = true);
    try {
      if (_churchHasRealGps) {
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw 'Turn on Location Services to check in.';
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          throw 'Location permission was denied.';
        }
        final pos = await Geolocator.getCurrentPosition();
        final distance = Geolocator.distanceBetween(
          pos.latitude, pos.longitude,
          widget.churchGeopoint.latitude, widget.churchGeopoint.longitude,
        );
        if (distance > _maxDistanceMeters) {
          final km = (distance / 1000).toStringAsFixed(distance > 1000 ? 1 : 2);
          throw "You're about ${distance > 1000 ? '$km km' : '${distance.round()} m'} from ${widget.churchName} - get closer to check in.";
        }
      }
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
