import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';
import '../models/church.dart';
import 'church_detail_screen.dart';
import 'bible_screen.dart';
import '../theme/app_theme.dart';
import '../models/liturgical_day.dart';
import '../providers/page_diagnostics_provider.dart';

const _brass = Color(0xFFA9822F);
const _stone = Color(0xFF324054);
const _paperDark = Color(0xFFDDD3BA);
const _cathedralPurple = Color(0xFF6B4C9A);
const _basilicaGold = Color(0xFFB8860B);

IconData _iconForBuildingType(String type) {
  switch (type) {
    case 'Cathedral':
    case 'Basilica':
      return Icons.account_balance; // grand civic-style building, fits a mother church
    case 'Convent':
    case 'Chapel':
      return Icons.home_work; // smaller religious house, distinct from a parish church
    default:
      return Icons.church;
  }
}

Color _colorForBuildingType(String type) {
  switch (type) {
    case 'Cathedral':
      return _cathedralPurple;
    case 'Basilica':
      return _basilicaGold;
    case 'Convent':
    case 'Chapel':
      return _stone;
    default:
      return _brass;
  }
}

class _TimelineItem {
  final DateTime date;
  final String time;
  final String label; // "Mass" | "Communion" | "Sacrament of Reconciliation"
  final String? note;
  final bool isReconciliation;
  final bool isCommunion;
  _TimelineItem({required this.date, required this.time, required this.label, this.note, this.isReconciliation = false, this.isCommunion = false});
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  List<Church>? _churches;
  Map<String, List<ServiceEntry>> _upcoming = {};
  Map<String, List<ConfessionTime>> _confessions = {};
  Object? _error;
  Position? _userPosition;
  String? _selectedChurchId;
  String _statusMessage = '';
  bool _mapVisible = true;

  @override
  void initState() {
    super.initState();
    _load();
    registerPageDiagnostics('Map', [
      TestCase('getAllChurches', () => FirestoreService().getAllChurches()),
      TestCase('getLiturgicalDay (for daily verse card)', () => FirestoreService().getLiturgicalDay(DateTime.now())),
    ]);
  }

  Future<void> _load() async {
    try {
      final service = FirestoreService();
      final allChurches = await service.getAllChurches();
      // (0,0) is the explicit "GPS not set yet" sentinel - filtered here,
      // once, at the source, rather than needing every downstream usage
      // (pin plotting, directions links, distance sorting) to each
      // separately guard against it.
      final gpsFiltered = allChurches.where((c) => !(c.geopoint.latitude == 0 && c.geopoint.longitude == 0)).toList();
      final upcomingResults = await Future.wait(
        gpsFiltered.map((c) async {
          final upcoming = await service.getUpcomingServices(c.parishId, c.id, daysAhead: 7);
          return MapEntry(c.id, upcoming);
        }),
      );
      final upcomingByChurch = Map.fromEntries(upcomingResults);
      // A venue (school hall, community hall) only belongs on the main
      // map while it actually has a Mass coming up - a permanent church
      // always shows regardless. Reuses the upcoming-services fetch just
      // above rather than querying again to check the same thing twice.
      final churches = gpsFiltered.where((c) => c.venueType != 'venue' || (upcomingByChurch[c.id]?.isNotEmpty ?? false)).toList();
      final confessionResults = await Future.wait(
        churches.map((c) async {
          final times = await service.getConfessionTimes(c.parishId, c.id);
          return MapEntry(c.id, times);
        }),
      );
      setState(() {
        _churches = churches;
        _upcoming = {for (final c in churches) c.id: upcomingByChurch[c.id] ?? []};
        _confessions = Map.fromEntries(confessionResults);
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Church? get _selectedChurch =>
      _selectedChurchId == null ? null : _churches?.firstWhere((c) => c.id == _selectedChurchId);

  ServiceEntry? _nextFor(String churchId) {
    final list = _upcoming[churchId];
    return (list != null && list.isNotEmpty) ? list.first : null;
  }

  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final serviceDay = DateTime(date.year, date.month, date.day);
    final diff = serviceDay.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1];
  }

  String _formatNext(ServiceEntry s) {
    final typeLabel = s.type == 'CommunionService' ? 'Communion Service' : 'Mass';
    return '${_dayLabel(s.date)} ${s.time} — $typeLabel';
  }

  int _weekdayIndex(String name) {
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return names.indexOf(name) + 1; // matches DateTime.weekday (Mon=1..Sun=7)
  }

  /// One merged, chronologically sorted list of everything happening this
  /// week at a church - Mass, Communion Service, and Reconciliation all
  /// together, tagged distinctly, since that's how someone actually plans
  /// their week around it rather than checking two separate lists.
  List<_TimelineItem> _timelineFor(String churchId) {
    final items = <_TimelineItem>[];

    for (final s in _upcoming[churchId] ?? []) {
      final isCommunion = s.type == 'CommunionService';
      items.add(_TimelineItem(
        date: s.date, time: s.time,
        label: isCommunion ? 'Communion' : 'Mass',
        note: s.notes, isCommunion: isCommunion,
      ));
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final c in _confessions[churchId] ?? []) {
      final targetWeekday = _weekdayIndex(c.dayOfWeek);
      for (int offset = 0; offset < 7; offset++) {
        final d = today.add(Duration(days: offset));
        if (d.weekday == targetWeekday) {
          items.add(_TimelineItem(
            date: d, time: c.startTime,
            label: 'Sacrament of Reconciliation',
            note: c.endTime != null ? 'Until ${c.endTime}' : c.notes,
            isReconciliation: true,
          ));
          break;
        }
      }
    }

    items.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      return dateCompare != 0 ? dateCompare : a.time.compareTo(b.time);
    });
    return items;
  }

  void _zoomIn() {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom + 1);
  }

  void _zoomOut() {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom - 1);
  }

  double? _distanceKm(Church c) {
    if (_userPosition == null) return null;
    return Geolocator.distanceBetween(
          _userPosition!.latitude, _userPosition!.longitude,
          c.geopoint.latitude, c.geopoint.longitude,
        ) /
        1000;
  }

  List<Church> get _sortedChurches {
    if (_churches == null) return [];
    final list = [..._churches!];
    if (_userPosition != null) {
      list.sort((a, b) => _distanceKm(a)!.compareTo(_distanceKm(b)!));
    }
    return list;
  }

  List<LatLng>? _routePoints;
  List<Map<String, dynamic>>? _feasibleMasses; // null = not checked yet
  List<Map<String, dynamic>>? _tomorrowFallback; // only populated if today has nothing feasible
  bool _checkingFeasibility = false;
  Timer? _feasibilityHideTimer;

  bool _showMapHiddenMessage = false;
  Timer? _mapMessageHideTimer;

  @override
  void dispose() {
    _feasibilityHideTimer?.cancel();
    _mapMessageHideTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkCanIStillMakeIt() async {
    if (_userPosition == null) {
      await _useMyLocation();
      if (_userPosition == null) return; // permission denied or location unavailable
    }
    setState(() { _checkingFeasibility = true; _feasibleMasses = null; _tomorrowFallback = null; });

    final service = FirestoreService();
    final now = DateTime.now();
    final userPoint = LatLng(_userPosition!.latitude, _userPosition!.longitude);
    final candidates = <Map<String, dynamic>>[];

    await Future.wait((_churches ?? []).map((c) async {
      final services = await service.getUpcomingServices(c.parishId, c.id, daysAhead: 1, hidePast: true);
      if (services.isEmpty) return;
      final next = services.first;
      // Only consider it if it's genuinely today, not spilling into tomorrow.
      if (!DateUtils.isSameDay(next.date, now)) return;

      final churchPoint = LatLng(c.geopoint.latitude, c.geopoint.longitude);
      final route = await service.getRouteWithDuration(userPoint, churchPoint);
      final bool isEstimate = route == null;
      final travelMinutes = route != null
          ? route['durationMinutes']!
          : (Geolocator.distanceBetween(userPoint.latitude, userPoint.longitude, churchPoint.latitude, churchPoint.longitude) / 1000) / 40 * 60; // rough fallback: ~40km/h average

      final bufferMinutes = next.dateTime.difference(now).inMinutes - travelMinutes.round();
      if (bufferMinutes >= 5) { // need at least 5 minutes to spare, not a photo finish
        candidates.add({
          'church': c,
          'service': next,
          'travelMinutes': travelMinutes.round(),
          'isEstimate': isEstimate,
        });
      }
    }));

    candidates.sort((a, b) => (a['service'] as ServiceEntry).dateTime.compareTo((b['service'] as ServiceEntry).dateTime));

    // Nothing left to reach today - rather than a dead-end "no", show
    // tomorrow's earliest options too, purely informational (no travel-time
    // feasibility check needed since there's no urgency yet).
    List<Map<String, dynamic>>? tomorrow;
    if (candidates.isEmpty) {
      final tomorrowCandidates = <Map<String, dynamic>>[];
      final tomorrowDate = now.add(const Duration(days: 1));
      await Future.wait((_churches ?? []).map((c) async {
        final services = await service.getUpcomingServices(c.parishId, c.id, daysAhead: 2, hidePast: true);
        final tomorrowService = services.where((s) => DateUtils.isSameDay(s.date, tomorrowDate)).toList();
        if (tomorrowService.isNotEmpty) {
          tomorrowCandidates.add({'church': c, 'service': tomorrowService.first});
        }
      }));
      tomorrowCandidates.sort((a, b) => (a['service'] as ServiceEntry).dateTime.compareTo((b['service'] as ServiceEntry).dateTime));
      tomorrow = tomorrowCandidates;
    }

    if (mounted) {
      setState(() { _feasibleMasses = candidates; _tomorrowFallback = tomorrow; _checkingFeasibility = false; });
      _feasibilityHideTimer?.cancel();
      _feasibilityHideTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() { _feasibleMasses = null; _tomorrowFallback = null; });
      });
    }
  }

  Future<void> _refreshRoute() async {
    if (_userPosition == null || _selectedChurchId == null) {
      if (_routePoints != null) setState(() => _routePoints = null);
      return;
    }
    final church = _churches?.firstWhere((c) => c.id == _selectedChurchId);
    if (church == null) return;
    final route = await FirestoreService().getRoute(
      LatLng(_userPosition!.latitude, _userPosition!.longitude),
      LatLng(church.geopoint.latitude, church.geopoint.longitude),
    );
    if (mounted) setState(() => _routePoints = route);
  }

  Future<void> _useMyLocation() async {
    setState(() => _statusMessage = 'Locating…');
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _statusMessage = 'Location services are off on this device.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => _statusMessage = 'Location permission denied — showing all churches without distance.');
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _userPosition = pos;
      _statusMessage = 'Showing distance from your location.';
    });
    _mapController.move(LatLng(pos.latitude, pos.longitude), 10);
    await _refreshRoute();
  }

  void _showAll() {
    if (_churches == null || _churches!.isEmpty) return;
    final points = _churches!.map((c) => LatLng(c.geopoint.latitude, c.geopoint.longitude)).toList();
    if (_userPosition != null) points.add(LatLng(_userPosition!.latitude, _userPosition!.longitude));
    setState(() { _selectedChurchId = null; _routePoints = null; });
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.all(48),
    ));
  }

  void _selectChurch(Church c) {
    setState(() => _selectedChurchId = _selectedChurchId == c.id ? null : c.id);
    if (_selectedChurchId == c.id) {
      _mapController.move(LatLng(c.geopoint.latitude, c.geopoint.longitude), 12);
      _refreshRoute();
    } else {
      setState(() => _routePoints = null);
    }
  }

  Future<void> _openDirections(Church c) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${c.geopoint.latitude},${c.geopoint.longitude}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: _stone,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Find a Church', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  const Text('Real coordinates, live distance from wherever you are.',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _brass, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact),
                        onPressed: _useMyLocation,
                        icon: const Icon(Icons.my_location, size: 15),
                        label: const Text('Use my location', style: TextStyle(fontSize: 12)),
                      ),
                      if (_mapVisible && _selectedChurchId != null)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact),
                          onPressed: _showAll,
                          icon: const Icon(Icons.zoom_out_map, size: 15),
                          label: const Text('Show all', style: TextStyle(fontSize: 12)),
                        ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact),
                        onPressed: () {
                          setState(() => _mapVisible = !_mapVisible);
                          _mapMessageHideTimer?.cancel();
                          if (!_mapVisible) {
                            setState(() => _showMapHiddenMessage = true);
                            _mapMessageHideTimer = Timer(const Duration(seconds: 10), () {
                              if (mounted) setState(() => _showMapHiddenMessage = false);
                            });
                          }
                        },
                        icon: Icon(_mapVisible ? Icons.map_outlined : Icons.map, size: 15),
                        label: Text(_mapVisible ? 'Hide map' : 'Show map', style: const TextStyle(fontSize: 12)),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: _brass, side: const BorderSide(color: _brass, width: 1.5), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact),
                        onPressed: _checkingFeasibility ? null : _checkCanIStillMakeIt,
                        icon: _checkingFeasibility
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _brass))
                            : const Icon(Icons.access_time_filled, size: 15),
                        label: const Text('Can I make it?', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const _DailyVerseCard(),

            if (_feasibleMasses != null)
              Container(
                width: double.infinity,
                color: _feasibleMasses!.isEmpty
                    ? ((_tomorrowFallback?.isNotEmpty ?? false) ? Colors.amber.shade50 : Colors.red.shade50)
                    : Colors.green.shade50,
                padding: const EdgeInsets.all(14),
                child: _feasibleMasses!.isEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Nothing left you can reach today.",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          if (_tomorrowFallback != null && _tomorrowFallback!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text("Tomorrow's earliest:", style: TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 6),
                            ..._tomorrowFallback!.take(3).map((f) {
                              final c = f['church'] as Church;
                              final s = f['service'] as ServiceEntry;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                                    children: [
                                      TextSpan(text: '${c.name} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      TextSpan(text: '— ${s.time} ${s.type == 'CommunionService' ? 'Communion Service' : 'Mass'}'),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ] else
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text("Nothing published for tomorrow yet either — check back closer to the day.",
                                  style: TextStyle(fontSize: 12, color: Colors.black54)),
                            ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('You can still make it to ${_feasibleMasses!.length} church${_feasibleMasses!.length > 1 ? 'es' : ''} today:',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 8),
                          ..._feasibleMasses!.take(3).map((f) {
                            final c = f['church'] as Church;
                            final s = f['service'] as ServiceEntry;
                            final travelMin = f['travelMinutes'] as int;
                            final isEstimate = f['isEstimate'] as bool;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                                        children: [
                                          TextSpan(text: '${c.name} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          TextSpan(text: '— ${s.time} ${s.type == 'CommunionService' ? 'Communion Service' : 'Mass'}, '
                                              '~$travelMin min away${isEstimate ? ' (estimated)' : ''}'),
                                        ],
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.directions, size: 18, color: _brass),
                                    onPressed: () => launchUrl(
                                      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${c.geopoint.latitude},${c.geopoint.longitude}'),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
              ),

            if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load churches:\n$_error', textAlign: TextAlign.center),
                  ),
                ),
              )
            else if (_churches == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              if (_mapVisible)
                SizedBox(
                  height: 320,
                  child: Stack(
                    children: [
                      FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _churches!.isNotEmpty
                            ? LatLng(_churches!.first.geopoint.latitude, _churches!.first.geopoint.longitude)
                            : const LatLng(-30.5595, 22.9375),
                        initialZoom: 10,
                        onTap: (_, __) => setState(() { _selectedChurchId = null; _routePoints = null; }),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'co.za.catholicsa',
                        ),
                        if (_routePoints != null)
                          PolylineLayer(polylines: [
                            Polyline(points: _routePoints!, strokeWidth: 4, color: _stone),
                          ]),
                        MarkerLayer(
                          markers: [
                            if (_userPosition != null)
                              Marker(
                                point: LatLng(_userPosition!.latitude, _userPosition!.longitude),
                                width: 20, height: 20,
                                child: Container(
                                  decoration: BoxDecoration(color: _stone, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                                ),
                              ),
                            ..._churches!.map((c) => Marker(
                                  point: LatLng(c.geopoint.latitude, c.geopoint.longitude),
                                  width: 40, height: 40,
                                  child: GestureDetector(
                                    onTap: () => _selectChurch(c),
                                    child: Icon(_iconForBuildingType(c.buildingType),
                                        color: _selectedChurchId == c.id ? _stone : _colorForBuildingType(c.buildingType),
                                        size: 34),
                                  ),
                                )),
                          ],
                        ),
                      ],
                    ),

                    Positioned(
                      top: 12, left: 12,
                      child: Column(
                        children: [
                          Material(
                            elevation: 3,
                            borderRadius: BorderRadius.circular(4),
                            child: InkWell(
                              onTap: _zoomIn,
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                width: 34, height: 34,
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                                child: const Icon(Icons.add, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Material(
                            elevation: 3,
                            borderRadius: BorderRadius.circular(4),
                            child: InkWell(
                              onTap: _zoomOut,
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                width: 34, height: 34,
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                                child: const Icon(Icons.remove, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_selectedChurch != null)
                      Positioned(
                        top: 12, left: 12, right: 12,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(_iconForBuildingType(_selectedChurch!.buildingType),
                                        color: _colorForBuildingType(_selectedChurch!.buildingType), size: 18),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(_selectedChurch!.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => setState(() { _selectedChurchId = null; _routePoints = null; }),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on, size: 13, color: Colors.black54),
                                    const SizedBox(width: 4),
                                    Expanded(child: Text(_selectedChurch!.address, style: const TextStyle(fontSize: 11, color: Colors.black54))),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time, size: 13, color: Colors.black87),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _nextFor(_selectedChurch!.id) != null
                                            ? _formatNext(_nextFor(_selectedChurch!.id)!)
                                            : 'No upcoming service listed',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(backgroundColor: _brass, padding: const EdgeInsets.symmetric(vertical: 8)),
                                    onPressed: () => _openDirections(_selectedChurch!),
                                    icon: const Icon(Icons.directions, size: 15),
                                    label: const Text('Get Directions', style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
              else if (_showMapHiddenMessage)
                Container(
                  width: double.infinity,
                  color: _paperDark,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  child: const Row(
                    children: [
                      Icon(Icons.map_outlined, color: Colors.black38, size: 14),
                      SizedBox(width: 6),
                      Text('Map hidden to save data', style: TextStyle(color: Colors.black45, fontSize: 11)),
                    ],
                  ),
                ),

              if (_statusMessage.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: _paperDark,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(_statusMessage, style: const TextStyle(fontSize: 12)),
                ),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _sortedChurches.length,
                  itemBuilder: (context, i) {
                    final c = _sortedChurches[i];
                    final dist = _distanceKm(c);
                    final isOpen = _selectedChurchId == c.id;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(_iconForBuildingType(c.buildingType), color: _colorForBuildingType(c.buildingType)),
                            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Row(
                              children: [
                                const Icon(Icons.location_on, size: 12, color: Colors.black45),
                                const SizedBox(width: 3),
                                Expanded(child: Text(c.address, maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (dist != null)
                                  Text('${dist.toStringAsFixed(1)} km',
                                      style: const TextStyle(color: _brass, fontWeight: FontWeight.bold, fontSize: 12)),
                                if (_nextFor(c.id) != null) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _nextFor(c.id)!.type == 'CommunionService' ? null : Colors.green.shade100,
                                      border: _nextFor(c.id)!.type == 'CommunionService' ? Border.all(color: Colors.black26) : null,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(_formatNext(_nextFor(c.id)!), style: const TextStyle(fontSize: 10)),
                                  ),
                                ] else
                                  const Text('No upcoming service', style: TextStyle(fontSize: 10, color: Colors.black45)),
                              ],
                            ),
                            onTap: () => _selectChurch(c),
                          ),

                          if (isOpen)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.event_note, size: 13, color: _stone),
                                      SizedBox(width: 4),
                                      Text('This week', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (_timelineFor(c.id).isEmpty)
                                    const Text('Nothing listed yet', style: TextStyle(fontSize: 11, color: Colors.black45))
                                  else
                                    ..._timelineFor(c.id).map((item) {
                                      final tagColor = item.isReconciliation
                                          ? Colors.blue.shade50
                                          : (item.isCommunion ? null : Colors.green.shade100);
                                      final hasBorder = item.isReconciliation || item.isCommunion;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 3),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(width: 46, child: Text(item.time, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                                            SizedBox(width: 46, child: Text(_dayLabel(item.date), style: const TextStyle(fontSize: 11, color: Colors.black54))),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: tagColor,
                                                border: hasBorder ? Border.all(color: Colors.black26) : null,
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(item.label, style: const TextStyle(fontSize: 10)),
                                            ),
                                            if (item.note != null) ...[
                                              const SizedBox(width: 6),
                                              Expanded(child: Text(item.note!, style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.black54))),
                                            ],
                                          ],
                                        ),
                                      );
                                    }),

                                  // Only shown as its own header+icon section when there's
                                  // genuinely nothing to merge into the week list above.
                                  if ((_confessions[c.id] ?? []).isEmpty) ...[
                                    const SizedBox(height: 12),
                                    const Row(
                                      children: [
                                        Icon(Icons.watch_later_outlined, size: 13, color: _stone),
                                        SizedBox(width: 4),
                                        Text('Sacrament of Reconciliation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    const Text('Contact the parish office', style: TextStyle(fontSize: 11, color: Colors.black45)),
                                  ],
                                ],
                              ),
                            ),

                          if (isOpen)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _openDirections(c),
                                      icon: const Icon(Icons.directions, size: 16),
                                      label: const Text('Get Directions'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: _stone),
                                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => ChurchDetailScreen(parishId: c.parishId, churchId: c.id),
                                      )),
                                      child: const Text('More Info'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reuses the verseForTheDay field already on today's LiturgicalDay -
/// no new content pipeline needed, just surfacing what an admin already
/// fills in as part of the daily reading, somewhere more visible than
/// only inside the full Readings screen. Shows nothing at all if today
/// has no verse set, rather than an empty or placeholder card.
class _DailyVerseCard extends StatelessWidget {
  const _DailyVerseCard();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LiturgicalDay?>(
      future: FirestoreService().getLiturgicalDay(DateTime.now()),
      builder: (context, snap) {
        final verse = snap.data?.readingsByLanguage['en']?.verseForTheDay;
        if (verse == null || verse.isEmpty) return const SizedBox.shrink();
        final citation = snap.data?.readingsByLanguage['en']?.verseForTheDayCitation;
        return InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BibleScreen())),
          child: Container(
            width: double.infinity,
            color: AppColors.paperDark,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.menu_book_outlined, size: 16, color: AppColors.brass),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12, color: Colors.black87, fontStyle: FontStyle.italic),
                      children: [
                        TextSpan(text: '"$verse"'),
                        if (citation != null && citation.isNotEmpty) TextSpan(text: '  — $citation', style: const TextStyle(fontStyle: FontStyle.normal, color: Colors.black54)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}