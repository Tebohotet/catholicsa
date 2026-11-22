/// The administrative unit — e.g. "St Jude Parish". Holds the priests and
/// admin assignments shared across every church building it serves.
/// A parish can have one church (most common) or several (e.g. St Jude
/// Parish serves Vredenburg, Laaiplek, Laingville, Langebaan, Saldanha).
class Parish {
  final String id;
  final String dioceseId;
  final String name; // "St Jude Parish"
  final String slug; // "st-jude-parish"
  final Map<String, bool> featureFlags; // finances, shop, comments, associations
  final String contactPhone; // parish-wide fallback if a church has none of its own
  final String contactEmail;
  final Map<String, String> socialLinks; // e.g. {"facebook": "...", "whatsapp": "https://wa.me/27..."}
  // Defaults to true so nothing already public vanishes just from this
  // field being added - same reasoning as Church.isActive. Turned off by
  // hand (Super Admin's parish list) for a parish that doesn't have real
  // data entered yet, so it doesn't show to the public - e.g. every
  // seeded/placeholder parish except the one(s) actually being worked on.
  final bool isActive;

  Parish({
    required this.id,
    required this.dioceseId,
    required this.name,
    required this.slug,
    this.featureFlags = const {
      'finances': false,
      'shop': false,
      'comments': true,
      'associations': true,
    },
    this.contactPhone = '',
    this.contactEmail = '',
    this.socialLinks = const {},
    this.isActive = true,
  });

  factory Parish.fromFirestore(String id, Map<String, dynamic> data) {
    return Parish(
      id: id,
      dioceseId: data['dioceseId'] as String,
      name: data['name'] as String,
      slug: data['slug'] as String? ?? id,
      featureFlags: Map<String, bool>.from(
        data['featureFlags'] ??
            {
              'finances': false,
              'shop': false,
              'comments': true,
              'associations': true,
            },
      ),
      contactPhone: data['contactPhone'] as String? ?? '',
      contactEmail: data['contactEmail'] as String? ?? '',
      socialLinks: Map<String, String>.from(data['socialLinks'] ?? {}),
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'dioceseId': dioceseId,
        'name': name,
        'slug': slug,
        'featureFlags': featureFlags,
        'contactPhone': contactPhone,
        'contactEmail': contactEmail,
        'socialLinks': socialLinks,
        'isActive': isActive,
      };
}

/// A priest belongs to a Parish (not a single Church) since one priest
/// commonly serves several church buildings under the same parish.
class Priest {
  final String id;
  final String name;
  final String role; // "Parish Priest" | "Assistant Priest"
  final String? phone;
  final String? photoUrl;
  final String? notes; // e.g. "Resident at Langebaan"
  final DateTime activeFrom;
  final DateTime? activeTo; // null = currently serving

  Priest({
    required this.id,
    required this.name,
    required this.role,
    this.phone,
    this.photoUrl,
    this.notes,
    required this.activeFrom,
    this.activeTo,
  });

  bool get isCurrent => activeTo == null;
}
