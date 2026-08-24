import 'package:cloud_firestore/cloud_firestore.dart';

/// A single physical church building — what shows as a pin on the map,
/// and what someone actually walks into on a Sunday. Nested under a Parish.
class Church {
  final String id;
  final String parishId;
  final String name; // "St Jude Catholic Church"
  final String slug; // "vredenburg"
  final String address;
  final GeoPoint geopoint;
  final String? geohash; // for nearby-radius queries
  final String contactPhone;
  final String contactEmail;
  final Map<String, String> socialLinks;
  final List<String> supportedLanguages; // e.g. ["en", "af"]
  final String buildingType; // "Church" | "Cathedral" | "Basilica" | "Convent" | "Chapel"
  final String verificationStatus; // "unverified" | "verified"
  final int? seatingCapacity;
  final String venueType; // "church" | "venue" - a venue is a school hall, community hall, or similar - Mass held there occasionally, sometimes only once. Same underlying model and features (services, accessibility, capacity, RSVP), deliberately without the weight of full church history/verification, which doesn't apply to a one-off space.

  Church({
    required this.id,
    required this.parishId,
    required this.name,
    required this.slug,
    required this.address,
    required this.geopoint,
    this.geohash,
    this.contactPhone = '',
    this.contactEmail = '',
    this.socialLinks = const {},
    this.supportedLanguages = const ['en'],
    this.buildingType = 'Church',
    this.verificationStatus = 'unverified',
    this.seatingCapacity,
    this.venueType = 'church',
  });

  factory Church.fromFirestore(String id, Map<String, dynamic> data) {
    return Church(
      id: id,
      parishId: data['parishId'] as String,
      name: data['name'] as String,
      slug: data['slug'] as String? ?? id,
      address: data['address'] as String,
      geopoint: data['geopoint'] as GeoPoint,
      geohash: data['geohash'] as String?,
      contactPhone: data['contactPhone'] as String? ?? '',
      contactEmail: data['contactEmail'] as String? ?? '',
      socialLinks: Map<String, String>.from(data['socialLinks'] ?? {}),
      supportedLanguages:
          List<String>.from(data['supportedLanguages'] ?? ['en']),
      buildingType: data['buildingType'] as String? ?? 'Church',
      verificationStatus: data['verificationStatus'] as String? ?? 'unverified',
      seatingCapacity: (data['seatingCapacity'] as num?)?.toInt(),
      venueType: data['venueType'] as String? ?? 'church',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'parishId': parishId,
        'name': name,
        'slug': slug,
        'address': address,
        'geopoint': geopoint,
        'geohash': geohash,
        'contactPhone': contactPhone,
        'contactEmail': contactEmail,
        'socialLinks': socialLinks,
        'supportedLanguages': supportedLanguages,
        'buildingType': buildingType,
        'verificationStatus': verificationStatus,
        'seatingCapacity': seatingCapacity,
        'venueType': venueType,
      };
}

/// A single physical church building's confession/reconciliation time.
class ConfessionTime {
  final String id;
  final String dayOfWeek;
  final String startTime;
  final String? endTime;
  final String? notes;

  ConfessionTime({required this.id, required this.dayOfWeek, required this.startTime, this.endTime, this.notes});

  factory ConfessionTime.fromFirestore(String id, Map<String, dynamic> data) => ConfessionTime(
        id: id,
        dayOfWeek: data['dayOfWeek'] as String,
        startTime: data['startTime'] as String,
        endTime: data['endTime'] as String?,
        notes: data['notes'] as String?,
      );
}

/// A single dated Mass or Communion Service. Re-entered weekly by the
/// parish admin (copying their printed bulletin) rather than a fixed
/// recurring template - because in multi-church parishes the priest
/// rotation genuinely changes which church gets what, week to week.
class ServiceEntry {
  final String id; // "{date}_{time}", e.g. "2026-07-25_17:00"
  final String churchId;
  final DateTime date;
  final String time; // "17:00"
  final String type; // "Mass" | "CommunionService" | "Cancelled"
  final String language; // "EN" | "AF" | ...
  final String? notes;

  ServiceEntry({
    required this.id,
    required this.churchId,
    required this.date,
    required this.time,
    required this.type,
    this.language = 'EN',
    this.notes,
  });

  /// Combines date + time into a real DateTime for comparison against "now".
  DateTime get dateTime {
    final parts = time.split(':');
    return DateTime(date.year, date.month, date.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  bool get isPast => dateTime.isBefore(DateTime.now());

  factory ServiceEntry.fromFirestore(String id, String churchId, Map<String, dynamic> data) {
    return ServiceEntry(
      id: id,
      churchId: churchId,
      date: (data['date'] as Timestamp).toDate(),
      time: data['time'] as String,
      type: data['type'] as String,
      language: data['language'] as String? ?? 'EN',
      notes: data['notes'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'date': Timestamp.fromDate(date),
        'time': time,
        'type': type,
        'language': language,
        'notes': notes,
      };
}