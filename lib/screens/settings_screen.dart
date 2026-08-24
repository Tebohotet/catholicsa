import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../models/user_preferences.dart';
import '../theme/app_theme.dart';
import 'privacy_policy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UserPreferences? _prefs;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final uid = AuthService().currentUser?.uid;
    if (uid != null) {
      FirestoreService().getUserPreferences(uid).then((p) {
        if (mounted) setState(() => _prefs = p);
      });
    }
  }

  Future<void> _save(UserPreferences updated) async {
    final uid = AuthService().currentUser?.uid;
    if (uid == null) return;
    setState(() { _prefs = updated; _saving = true; });
    try {
      await FirestoreService().saveUserPreferences(uid, updated);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Delete Account', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: const Text(
          'This permanently deletes your account. Your comments will be kept but shown as "[deleted user]" '
          'rather than removed, so discussions stay intact. This cannot be undone.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete My Account', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await FirebaseFunctions.instance.httpsCallable('deleteUserAccount').call();
      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete account: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: AppColors.stone,
              padding: const EdgeInsets.fromLTRB(4, 12, 16, 20),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  const Text('Settings', style: TextStyle(fontFamily: appSerif, fontSize: 24, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: _prefs == null
                  ? const Center(child: CircularProgressIndicator())
                  : CenteredContent(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const SectionLabel(numeral: 'I', title: 'Language'),
                        _LanguagePicker(
                          value: _prefs!.language,
                          onChanged: (lang) => _save(UserPreferences(
                            language: lang, notifications: _prefs!.notifications,
                            autoDetectNearestChurch: _prefs!.autoDetectNearestChurch, privacy: _prefs!.privacy,
                          )),
                        ),
                        const SizedBox(height: 28),

                        const SizedBox(height: 28),
                        const SectionLabel(numeral: 'II', title: 'Birthday'),
                        const Text('Optional - lets the app show you which saint shares your birthday.', style: TextStyle(fontSize: 11, color: Colors.black54)),
                        const SizedBox(height: 6),
                        const _BirthdayPicker(),
                        const SizedBox(height: 28),

                        const SectionLabel(numeral: 'III', title: 'Location'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: AppColors.brass,
                          title: const Text('Auto-detect nearest church on Home', style: TextStyle(fontSize: 13)),
                          value: _prefs!.autoDetectNearestChurch,
                          onChanged: (v) => _save(UserPreferences(
                            language: _prefs!.language, notifications: _prefs!.notifications,
                            autoDetectNearestChurch: v, privacy: _prefs!.privacy,
                          )),
                        ),
                        const SizedBox(height: 28),

                        const SectionLabel(numeral: 'IV', title: 'Notifications'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero, activeThumbColor: AppColors.brass,
                          title: const Text('Mass reminders', style: TextStyle(fontSize: 13)),
                          value: _prefs!.notifications.massReminders,
                          onChanged: (v) => _save(_withNotif((n) => NotificationSettings(
                            massReminders: v, eventReminders: n.eventReminders, newsletterEmail: n.newsletterEmail, pushEnabled: n.pushEnabled))),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero, activeThumbColor: AppColors.brass,
                          title: const Text('Event reminders', style: TextStyle(fontSize: 13)),
                          value: _prefs!.notifications.eventReminders,
                          onChanged: (v) => _save(_withNotif((n) => NotificationSettings(
                            massReminders: n.massReminders, eventReminders: v, newsletterEmail: n.newsletterEmail, pushEnabled: n.pushEnabled))),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero, activeThumbColor: AppColors.brass,
                          title: const Text('Newsletter emails', style: TextStyle(fontSize: 13)),
                          value: _prefs!.notifications.newsletterEmail,
                          onChanged: (v) => _save(_withNotif((n) => NotificationSettings(
                            massReminders: n.massReminders, eventReminders: n.eventReminders, newsletterEmail: v, pushEnabled: n.pushEnabled))),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero, activeThumbColor: AppColors.brass,
                          title: const Text('Push notifications', style: TextStyle(fontSize: 13)),
                          value: _prefs!.notifications.pushEnabled,
                          onChanged: (v) {
                            _save(_withNotif((n) => NotificationSettings(
                                massReminders: n.massReminders, eventReminders: n.eventReminders, newsletterEmail: n.newsletterEmail, pushEnabled: v)));
                            // The Cloud Function already checks this preference
                            // before sending, so this isn't strictly required
                            // for correctness - but removing the token when
                            // switched off means this device stops being sent
                            // to immediately, not just filtered server-side.
                            if (v) {
                              NotificationService().requestPermissionAndSaveToken();
                            } else {
                              final uid = FirebaseAuth.instance.currentUser?.uid;
                              if (uid != null) NotificationService().removeTokenOnSignOut(uid);
                            }
                          },
                        ),
                        const SizedBox(height: 28),

                        const SectionLabel(numeral: 'V', title: 'Privacy'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero, activeThumbColor: AppColors.brass,
                          title: const Text('Show my name on comments', style: TextStyle(fontSize: 13)),
                          value: _prefs!.privacy.profileVisible,
                          onChanged: (v) => _save(_withPrivacy((p) => PrivacySettings(profileVisible: v, showAttendanceHistory: p.showAttendanceHistory))),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero, activeThumbColor: AppColors.brass,
                          title: const Text('Let parish admins see my attendance history', style: TextStyle(fontSize: 13)),
                          value: _prefs!.privacy.showAttendanceHistory,
                          onChanged: (v) => _save(_withPrivacy((p) => PrivacySettings(profileVisible: p.profileVisible, showAttendanceHistory: v))),
                        ),
                        const SizedBox(height: 28),
                        TextButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                          icon: const Icon(Icons.privacy_tip_outlined, size: 16, color: AppColors.stone),
                          label: const Text('Privacy Policy', style: TextStyle(color: AppColors.stone)),
                        ),
                        const SizedBox(height: 28),

                        const SectionLabel(numeral: 'VI', title: 'Danger Zone'),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                          onPressed: _confirmDelete,
                          icon: const Icon(Icons.delete_forever, size: 16),
                          label: const Text('Delete Account'),
                        ),
                        if (_saving) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                      ],
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  UserPreferences _withNotif(NotificationSettings Function(NotificationSettings) update) {
    return UserPreferences(
      language: _prefs!.language,
      notifications: update(_prefs!.notifications),
      autoDetectNearestChurch: _prefs!.autoDetectNearestChurch,
      privacy: _prefs!.privacy,
    );
  }

  UserPreferences _withPrivacy(PrivacySettings Function(PrivacySettings) update) {
    return UserPreferences(
      language: _prefs!.language,
      notifications: _prefs!.notifications,
      autoDetectNearestChurch: _prefs!.autoDetectNearestChurch,
      privacy: update(_prefs!.privacy),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _LanguagePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = {'en': 'English', 'af': 'Afrikaans'};
    return Wrap(
      spacing: 8,
      children: options.entries.map((e) => ChoiceChip(
        label: Text(e.value),
        selected: value == e.key,
        selectedColor: AppColors.brass,
        labelStyle: TextStyle(color: value == e.key ? Colors.white : AppColors.ink, fontSize: 13),
        onSelected: (_) => onChanged(e.key),
      )).toList(),
    );
  }
}

/// Writes directly to users/{uid}.birthMonthDay - separate from the
/// UserPreferences save flow above, since this isn't part of that model.
/// Only month and day are stored, deliberately - no year, no need for
/// one, and one less piece of personal data held than necessary.
class _BirthdayPicker extends StatefulWidget {
  const _BirthdayPicker();

  @override
  State<_BirthdayPicker> createState() => _BirthdayPickerState();
}

class _BirthdayPickerState extends State<_BirthdayPicker> {
  DateTime? _selected;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final doc = await FirestoreService().getUserDoc(uid);
    final monthDay = doc?['birthMonthDay'] as String?;
    if (monthDay != null) {
      final parts = monthDay.split('-');
      if (parts.length == 2) _selected = DateTime(2000, int.parse(parts[0]), int.parse(parts[1]));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pick() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final picked = await showDatePicker(
      context: context, initialDate: _selected ?? DateTime(2000, 1, 1),
      firstDate: DateTime(2000, 1, 1), lastDate: DateTime(2000, 12, 31),
      helpText: 'Pick your birthday (year isn\'t stored)',
    );
    if (picked == null) return;
    setState(() => _saving = true);
    final monthDay = '${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    await FirestoreService().updateUserBirthday(uid, monthDay);
    if (mounted) setState(() { _selected = DateTime(2000, picked.month, picked.day); _saving = false; });
  }

  Future<void> _clear() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirestoreService().updateUserBirthday(uid, null);
    if (mounted) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 20);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _saving ? null : _pick,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                const Icon(Icons.cake_outlined, size: 16, color: Colors.black45),
                const SizedBox(width: 8),
                Text(_selected != null ? DateFormat('MMMM d').format(_selected!) : 'Not set', style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ),
        ),
        if (_selected != null)
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _clear),
      ],
    );
  }
}