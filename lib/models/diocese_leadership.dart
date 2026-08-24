/// Extends the basic Diocese record with leadership/curia info.
/// This data is sourced from public diocesan directories and known to
/// need periodic correction — superAdmin (or a delegated diocese admin,
/// if that role is added later) can edit it same as any other document.
class DioceseLeadership {
  final String dioceseId;
  final String? bishopTitle; // "Archbishop" | "Bishop"
  final String? bishopName;
  final String? auxiliaryBishop;
  final String? vicarGeneral;
  final String? chancellor;
  final String? cathedralName;
  final String? address;
  final String? phone;
  final String? email;
  final String? website;
  final List<Deanery> deaneries;
  final List<String> religiousCommunities; // e.g. "Oblates of Mary Immaculate (OMI)"
  final bool verified; // false = pulled from an external list, not yet confirmed

  DioceseLeadership({
    required this.dioceseId,
    this.bishopTitle,
    this.bishopName,
    this.auxiliaryBishop,
    this.vicarGeneral,
    this.chancellor,
    this.cathedralName,
    this.address,
    this.phone,
    this.email,
    this.website,
    this.deaneries = const [],
    this.religiousCommunities = const [],
    this.verified = false,
  });

  factory DioceseLeadership.fromFirestore(String dioceseId, Map<String, dynamic> data) {
    return DioceseLeadership(
      dioceseId: dioceseId,
      bishopTitle: data['bishopTitle'] as String?,
      bishopName: data['bishopName'] as String?,
      auxiliaryBishop: data['auxiliaryBishop'] as String?,
      vicarGeneral: data['vicarGeneral'] as String?,
      chancellor: data['chancellor'] as String?,
      cathedralName: data['cathedralName'] as String?,
      address: data['address'] as String?,
      phone: data['phone'] as String?,
      email: data['email'] as String?,
      website: data['website'] as String?,
      deaneries: (data['deaneries'] as List<dynamic>? ?? [])
          .map((d) => Deanery.fromMap(Map<String, dynamic>.from(d)))
          .toList(),
      religiousCommunities: List<String>.from(data['religiousCommunities'] ?? []),
      verified: data['verified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'bishopTitle': bishopTitle,
        'bishopName': bishopName,
        'auxiliaryBishop': auxiliaryBishop,
        'vicarGeneral': vicarGeneral,
        'chancellor': chancellor,
        'cathedralName': cathedralName,
        'address': address,
        'phone': phone,
        'email': email,
        'website': website,
        'deaneries': deaneries.map((d) => d.toMap()).toList(),
        'religiousCommunities': religiousCommunities,
        'verified': verified,
      };
}

class Deanery {
  final String name; // "Central Deanery"
  final String deanName; // "Fr Joe Pich"

  Deanery({required this.name, required this.deanName});

  factory Deanery.fromMap(Map<String, dynamic> data) =>
      Deanery(name: data['name'] as String, deanName: data['deanName'] as String);

  Map<String, dynamic> toMap() => {'name': name, 'deanName': deanName};
}
