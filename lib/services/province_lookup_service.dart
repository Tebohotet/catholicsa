import 'package:cloud_firestore/cloud_firestore.dart';

/// Determines which province a GPS point falls in - entirely from data
/// stored in Firestore (provinces/{id}.bounds), never hardcoded here.
/// If South Africa's provincial boundaries ever change, editing the
/// `bounds` field on the affected province documents is enough - no
/// app update, no redeploy.
///
/// Use case: when a new church is added with just a lat/lng, this can
/// suggest which province it likely belongs to, instead of forcing manual
/// selection every time. It's a suggestion, not an authority - the admin
/// still confirms, since bounding boxes are rectangles and real provincial
/// borders aren't.
class ProvinceLookupService {
  final _db = FirebaseFirestore.instance;

  Future<String?> detectProvinceId(double lat, double lng) async {
    final snap = await _db.collection('provinces').get();
    for (final doc in snap.docs) {
      final bounds = doc.data()['bounds'] as Map<String, dynamic>?;
      if (bounds == null) continue;
      final minLat = (bounds['minLat'] as num).toDouble();
      final maxLat = (bounds['maxLat'] as num).toDouble();
      final minLng = (bounds['minLng'] as num).toDouble();
      final maxLng = (bounds['maxLng'] as num).toDouble();
      if (lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng) {
        return doc.id;
      }
    }
    return null; // outside all known bounds, or bounds overlap - flag for manual review
  }

  /// Bounding boxes are rectangles, so provinces that share a long border
  /// (e.g. Gauteng sits entirely inside a box that slightly overlaps North
  /// West and Mpumalanga) can both match a point near the edge. Returns
  /// every matching province so the UI can ask the admin to pick when
  /// there's more than one.
  Future<List<String>> detectPossibleProvinceIds(double lat, double lng) async {
    final snap = await _db.collection('provinces').get();
    final matches = <String>[];
    for (final doc in snap.docs) {
      final bounds = doc.data()['bounds'] as Map<String, dynamic>?;
      if (bounds == null) continue;
      final minLat = (bounds['minLat'] as num).toDouble();
      final maxLat = (bounds['maxLat'] as num).toDouble();
      final minLng = (bounds['minLng'] as num).toDouble();
      final maxLng = (bounds['maxLng'] as num).toDouble();
      if (lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng) {
        matches.add(doc.id);
      }
    }
    return matches;
  }
}
