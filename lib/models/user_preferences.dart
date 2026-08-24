/// Backs the Settings screen: Language, Favourites, Notifications,
/// Location, Churches Attended, Privacy, Delete Account.
class UserPreferences {
  final String language;
  final NotificationSettings notifications;
  final bool autoDetectNearestChurch; // app preference, distinct from the
  // actual OS-level location permission (that's handled by geolocator,
  // not stored here - this just controls whether Home tries automatically)
  final PrivacySettings privacy;

  UserPreferences({
    this.language = 'en',
    NotificationSettings? notifications,
    this.autoDetectNearestChurch = true,
    PrivacySettings? privacy,
  })  : notifications = notifications ?? NotificationSettings(),
        privacy = privacy ?? PrivacySettings();

  factory UserPreferences.fromFirestore(Map<String, dynamic> data) {
    return UserPreferences(
      language: data['language'] as String? ?? 'en',
      notifications: NotificationSettings.fromMap(
          Map<String, dynamic>.from(data['notifications'] ?? {})),
      autoDetectNearestChurch: data['autoDetectNearestChurch'] as bool? ?? true,
      privacy: PrivacySettings.fromMap(
          Map<String, dynamic>.from(data['privacy'] ?? {})),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'language': language,
        'notifications': notifications.toMap(),
        'autoDetectNearestChurch': autoDetectNearestChurch,
        'privacy': privacy.toMap(),
      };
}

class NotificationSettings {
  final bool massReminders;
  final bool eventReminders;
  final bool newsletterEmail;
  final bool pushEnabled;

  NotificationSettings({
    this.massReminders = true,
    this.eventReminders = true,
    this.newsletterEmail = false,
    this.pushEnabled = true,
  });

  factory NotificationSettings.fromMap(Map<String, dynamic> m) => NotificationSettings(
        massReminders: m['massReminders'] as bool? ?? true,
        eventReminders: m['eventReminders'] as bool? ?? true,
        newsletterEmail: m['newsletterEmail'] as bool? ?? false,
        pushEnabled: m['pushEnabled'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'massReminders': massReminders,
        'eventReminders': eventReminders,
        'newsletterEmail': newsletterEmail,
        'pushEnabled': pushEnabled,
      };
}

class PrivacySettings {
  final bool profileVisible; // show display name/photo on comments
  final bool showAttendanceHistory; // let this be visible to parish admins

  PrivacySettings({this.profileVisible = true, this.showAttendanceHistory = false});

  factory PrivacySettings.fromMap(Map<String, dynamic> m) => PrivacySettings(
        profileVisible: m['profileVisible'] as bool? ?? true,
        showAttendanceHistory: m['showAttendanceHistory'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'profileVisible': profileVisible,
        'showAttendanceHistory': showAttendanceHistory,
      };
}

class FavouriteChurch {
  final String churchId;
  final DateTime addedAt;
  FavouriteChurch({required this.churchId, required this.addedAt});
}

class AttendanceRecord {
  final String id;
  final String churchId;
  final DateTime date;
  final String? note;
  AttendanceRecord({required this.id, required this.churchId, required this.date, this.note});
}

class ShopAddress {
  final String id;
  final String label; // "Home", "Work"
  final String line1;
  final String? line2;
  final String city;
  final String postalCode;
  final String province;
  final bool isDefault;

  ShopAddress({
    required this.id,
    required this.label,
    required this.line1,
    this.line2,
    required this.city,
    required this.postalCode,
    required this.province,
    this.isDefault = false,
  });
}
