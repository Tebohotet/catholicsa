import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/church.dart';

class MapPopupDialog extends StatefulWidget {
  final Church church;
  const MapPopupDialog({super.key, required this.church});

  @override
  State<MapPopupDialog> createState() => _MapPopupDialogState();
}

class _MapPopupDialogState extends State<MapPopupDialog> {
  final _mapController = MapController();
  Position? _userPosition;
  List<LatLng>? _routePoints;
  bool _locating = false;
  bool _routeUnavailable = false;

  double? get _distanceKm {
    if (_userPosition == null) return null;
    return Geolocator.distanceBetween(
          _userPosition!.latitude, _userPosition!.longitude,
          widget.church.geopoint.latitude, widget.church.geopoint.longitude,
        ) /
        1000;
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _userPosition = pos);
        final churchPoint = LatLng(widget.church.geopoint.latitude, widget.church.geopoint.longitude);
        final userPoint = LatLng(pos.latitude, pos.longitude);
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([churchPoint, userPoint]),
          padding: const EdgeInsets.all(40),
        ));
        // Fetch the actual road-following route, not just a straight line.
        final route = await FirestoreService().getRoute(userPoint, churchPoint);
        if (mounted) setState(() => route == null ? _routeUnavailable = true : _routePoints = route);
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _zoomIn() {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom + 1);
  }

  void _zoomOut() {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom - 1);
  }

  Future<void> _openDirections() async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${widget.church.geopoint.latitude},${widget.church.geopoint.longitude}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final churchPoint = LatLng(widget.church.geopoint.latitude, widget.church.geopoint.longitude);
    return Dialog(
      backgroundColor: AppColors.paper,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text(widget.church.name, style: const TextStyle(fontFamily: appSerif, fontSize: 16))),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            if (_distanceKm != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 6),
                child: Text(
                  _routePoints != null
                      ? '${_distanceKm!.toStringAsFixed(1)} km straight-line — route shown on map'
                      : _routeUnavailable
                          ? '${_distanceKm!.toStringAsFixed(1)} km from your location (straight-line — route unavailable right now)'
                          : '${_distanceKm!.toStringAsFixed(1)} km from your location',
                  style: const TextStyle(fontSize: 12, color: AppColors.brass, fontWeight: FontWeight.w600),
                ),
              ),
            SizedBox(
              height: 240,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(initialCenter: churchPoint, initialZoom: 14),
                    children: [
                      TileLayer(urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'co.za.catholicsa'),
                      if (_routePoints != null)
                        PolylineLayer(polylines: [
                          Polyline(points: _routePoints!, strokeWidth: 4, color: AppColors.stone),
                        ]),
                      MarkerLayer(markers: [
                        Marker(point: churchPoint, width: 36, height: 36, child: const Icon(Icons.location_on, color: AppColors.brass, size: 36)),
                        if (_userPosition != null)
                          Marker(
                            point: LatLng(_userPosition!.latitude, _userPosition!.longitude),
                            width: 18, height: 18,
                            child: Container(decoration: BoxDecoration(color: AppColors.stone, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                          ),
                      ]),
                    ],
                  ),
                  Positioned(
                    top: 8, left: 8,
                    child: Column(
                      children: [
                        _zoomButton(Icons.add, _zoomIn),
                        const SizedBox(height: 4),
                        _zoomButton(Icons.remove, _zoomOut),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                      onPressed: _locating ? null : _useMyLocation,
                      icon: _locating
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location, size: 17),
                      label: Text(_userPosition != null ? 'Location on' : 'Use my location'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                      onPressed: _openDirections,
                      icon: const Icon(Icons.directions, size: 17),
                      label: const Text('Get Directions'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}

