import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/church.dart';
import '../models/parish.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import 'payment_gateway_settings_screen.dart';
import 'lesson_editor_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  final String parishId;
  const AdminPanelScreen({super.key, required this.parishId});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  List<Church>? _churches;
  String? _selectedChurchId;
  String? _role;
  Key _servicesKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    FirestoreService().getChurches(widget.parishId).then((list) {
      if (mounted) setState(() { _churches = list; _selectedChurchId = list.isNotEmpty ? list.first.id : null; });
    });
    AuthService().getAdminProfile(widget.parishId).then((profile) {
      if (mounted) setState(() { _role = profile?['role'] as String?; });
    });
  }

  Future<void> _reloadChurches({String? selectId}) async {
    final list = await FirestoreService().getChurches(widget.parishId);
    if (mounted) setState(() { _churches = list; _selectedChurchId = selectId ?? _selectedChurchId; });
  }

  Future<void> _showChurchForm(BuildContext context, {Church? existing}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final phoneCtrl = TextEditingController(text: existing?.contactPhone ?? '');
    final emailCtrl = TextEditingController(text: existing?.contactEmail ?? '');
    final capacityCtrl = TextEditingController(text: existing?.seatingCapacity?.toString() ?? '');
    String buildingType = existing?.buildingType ?? 'Church';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: Text(isEdit ? 'Edit Church' : 'Add Church', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Church name', hintText: 'e.g. St Jude Catholic Church')),
                TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Address')),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Contact phone (optional)')),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Contact email (optional)')),
                TextField(controller: capacityCtrl, decoration: const InputDecoration(labelText: 'Seating capacity (optional)', hintText: 'e.g. 250'), keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                const Text('Building type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                DropdownButton<String>(
                  value: buildingType, isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'Church', child: Text('Church')),
                    DropdownMenuItem(value: 'Cathedral', child: Text('Cathedral')),
                    DropdownMenuItem(value: 'Basilica', child: Text('Basilica')),
                    DropdownMenuItem(value: 'Convent', child: Text('Convent')),
                    DropdownMenuItem(value: 'Chapel', child: Text('Chapel')),
                  ],
                  onChanged: (v) => setDialogState(() => buildingType = v!),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('GPS location, accessibility details, and amenities can be added afterward - this gets the church listed so you can start adding Mass times right away.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || addressCtrl.text.trim().isEmpty) return;
                final capacity = int.tryParse(capacityCtrl.text.trim());
                if (isEdit) {
                  await FirestoreService().updateChurch(
                    parishId: widget.parishId, churchId: existing.id,
                    name: nameCtrl.text.trim(), address: addressCtrl.text.trim(),
                    contactPhone: phoneCtrl.text.trim(), contactEmail: emailCtrl.text.trim(),
                    buildingType: buildingType, seatingCapacity: capacity,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _reloadChurches();
                } else {
                  final newId = await FirestoreService().addChurch(
                    parishId: widget.parishId,
                    name: nameCtrl.text.trim(), address: addressCtrl.text.trim(),
                    contactPhone: phoneCtrl.text.trim(), contactEmail: emailCtrl.text.trim(),
                    buildingType: buildingType, seatingCapacity: capacity,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _reloadChurches(selectId: newId);
                }
              },
              child: Text(isEdit ? 'Save' : 'Add Church'),
            ),
          ],
        ),
      ),
    );
  }

  /// Deliberately minimal - a school hall or community hall used for Mass
  /// occasionally, sometimes only once. Name, address, capacity, and
  /// basic accessibility notes are the only real questions; everything
  /// heavier (building type, verification, church history) genuinely
  /// doesn't apply here and isn't asked.
  Future<void> _showVenueForm(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final capacityCtrl = TextEditingController();
    final accessibilityNotesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Add Mass Venue', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('For a school hall, community hall, or similar - not a full parish church.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Venue name', hintText: 'e.g. Vredenburg Primary School Hall')),
              TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Address')),
              TextField(controller: capacityCtrl, decoration: const InputDecoration(labelText: 'How many people can it seat?', hintText: 'e.g. 80'), keyboardType: TextInputType.number),
              TextField(controller: accessibilityNotesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Accessibility notes (optional)', hintText: 'e.g. Ramp at side entrance, no steps')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || addressCtrl.text.trim().isEmpty) return;
              final newId = await FirestoreService().addChurch(
                parishId: widget.parishId,
                name: nameCtrl.text.trim(), address: addressCtrl.text.trim(),
                seatingCapacity: int.tryParse(capacityCtrl.text.trim()),
                venueType: 'venue',
              );
              if (accessibilityNotesCtrl.text.trim().isNotEmpty) {
                await FirestoreService().updateChurchAccessibility(widget.parishId, newId, {
                  'wheelchairAccessible': 'unknown',
                  'steps': 'unknown',
                  'hasRamp': false,
                  'accessibleParking': false,
                  'hasAccessibleToilet': false,
                  'notes': accessibilityNotesCtrl.text.trim(),
                  'assistanceContactPhone': null,
                });
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              await _reloadChurches(selectId: newId);
            },
            child: const Text('Add Venue'),
          ),
        ],
      ),
    );
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Admin Panel', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                        if (_role != null) Text('Signed in as ${_role == 'priest' ? 'Priest' : 'Secretary'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _churches == null
                  ? const Center(child: CircularProgressIndicator())
                  : CenteredContent(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const SectionLabel(numeral: 'I', title: 'Mass Times'),
                        if (_churches!.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text('No churches yet for this parish - add the first one to get started.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          )
                        else
                          DropdownButton<String>(
                            value: _selectedChurchId,
                            isExpanded: true,
                            items: _churches!.map((c) => DropdownMenuItem(value: c.id, child: Text(c.venueType == 'venue' ? '${c.name} (Venue)' : c.name))).toList(),
                            onChanged: (id) => setState(() => _selectedChurchId = id),
                          ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                            onPressed: () => _showChurchForm(context),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Church'),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                            onPressed: () => _showVenueForm(context),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Mass Venue'),
                          ),
                          if (_selectedChurchId != null)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                              onPressed: () => _showChurchForm(context, existing: _churches!.firstWhere((c) => c.id == _selectedChurchId)),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Edit This Church'),
                            ),
                        ]),
                        const SizedBox(height: 12),
                        // Verification doesn't apply to a one-off venue -
                        // history, admin training, and associations are
                        // real questions for a permanent church, not a
                        // school hall used once for a special Mass.
                        if (_selectedChurchId != null &&
                            _churches!.firstWhere((c) => c.id == _selectedChurchId).venueType != 'venue')
                          _ChurchVerificationSection(
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                            isPriest: _role == 'priest',
                          ),
                        const SizedBox(height: 12),
                        if (_selectedChurchId != null)
                          _ServiceEditor(
                            key: _servicesKey,
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                            onChanged: () => setState(() => _servicesKey = UniqueKey()),
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'II', title: 'Finances'),
                        _FinanceToggle(parishId: widget.parishId, canEdit: _role == 'priest'),
                        if (_role == 'priest') ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => PaymentGatewaySettingsScreen(parishId: widget.parishId),
                            )),
                            icon: const Icon(Icons.payments_outlined, size: 16),
                            label: const Text('Payment Settings'),
                          ),
                        ],

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'III', title: 'Reply to Comments'),
                        _CommentsAdminList(parishId: widget.parishId),
                        const SizedBox(height: 16),
                        const Text('Comment Reports', style: TextStyle(fontFamily: appSerif, fontSize: 15)),
                        const SizedBox(height: 8),
                        _CommentReportsSection(parishId: widget.parishId),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'IV', title: 'Photos & Videos'),
                        if (_selectedChurchId != null)
                          _MediaAdminSection(
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                            canApprove: _role == 'priest',
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'V', title: 'Song Book'),
                        if (_selectedChurchId != null)
                          _SongBookAdminSection(
                            key: ValueKey('songs-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'VI', title: 'Prayers'),
                        if (_selectedChurchId != null)
                          _PrayersAdminSection(
                            key: ValueKey('prayers-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'VII', title: 'Courses'),
                        if (_selectedChurchId != null)
                          _CoursesAdminSection(
                            key: ValueKey('courses-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                            isPriest: _role == 'priest',
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'VIII', title: 'Confession Bookings'),
                        if (_selectedChurchId != null)
                          _BookingsAdminSection(
                            key: ValueKey('bookings-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'IX', title: 'Mass Intention Requests'),
                        if (_selectedChurchId != null)
                          _MassIntentionsAdminSection(
                            key: ValueKey('massintentions-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'X', title: 'Reported Issues'),
                        if (_selectedChurchId != null)
                          _ReportsAdminSection(
                            key: ValueKey('reports-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'XI', title: 'Devotions'),
                        if (_selectedChurchId != null)
                          _DevotionsAdminSection(
                            key: ValueKey('devotions-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'XII', title: 'Associations & Societies'),
                        const Text('Parish-Wide (CWL, SVP, etc. - seen across every church in the parish)', style: TextStyle(fontFamily: appSerif, fontSize: 14)),
                        const SizedBox(height: 8),
                        _ParishAssociationsAdminSection(parishId: widget.parishId),
                        const SizedBox(height: 16),
                        const Text('Church-Specific (like one choir - only shown on this church\'s page)', style: TextStyle(fontFamily: appSerif, fontSize: 14)),
                        const SizedBox(height: 8),
                        if (_selectedChurchId != null)
                          _AssociationsAdminSection(
                            key: ValueKey('assoc-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'XIII', title: 'Parochial Notices'),
                        if (_selectedChurchId != null)
                          _NoticesAdminSection(
                            key: ValueKey('notices-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'XIV', title: 'Events'),
                        if (_selectedChurchId != null)
                          _EventsAdminSection(
                            key: ValueKey('events-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'XV', title: 'Marketplace Listings'),
                        if (_selectedChurchId != null)
                          _MarketplaceAdminSection(
                            key: ValueKey('marketplace-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'XVI', title: 'Marketplace Orders'),
                        if (_selectedChurchId != null)
                          _MarketplaceOrdersAdminSection(
                            key: ValueKey('orders-$_selectedChurchId'),
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'XVII', title: 'Donations'),
                        if (_selectedChurchId != null)
                          _DonationsAdminSection(
                            key: ValueKey('donations-$_selectedChurchId'),
                            parishId: widget.parishId,
                            churchId: _selectedChurchId!,
                          ),

                        const SizedBox(height: 32),
                        const SectionLabel(numeral: 'XVIII', title: 'Catechist Applications'),
                        const Text(
                          'Applications to teach at this specific parish - a national application (usable at any parish) is reviewed by a Super Admin instead, not here.',
                          style: TextStyle(fontSize: 11, color: Colors.black45),
                        ),
                        const SizedBox(height: 10),
                        _CatechistApplicationsAdminSection(parishId: widget.parishId),
                      ],
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChurchVerificationSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  final bool isPriest;
  const _ChurchVerificationSection({required this.parishId, required this.churchId, required this.isPriest});

  @override
  State<_ChurchVerificationSection> createState() => _ChurchVerificationSectionState();
}

class _ChurchVerificationSectionState extends State<_ChurchVerificationSection> {
  late Future<Map<String, bool>> _eligibilityFuture;
  late Future<Church> _churchFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _eligibilityFuture = FirestoreService().checkVerificationEligibility(widget.parishId, widget.churchId);
    _churchFuture = FirestoreService().getChurch(widget.parishId, widget.churchId);
  }

  String _conditionLabel(String key) {
    switch (key) {
      case 'hasConfirmedMassTime': return 'At least one Mass time confirmed';
      case 'hasAtLeastOneAdmin': return 'At least one admin assigned';
      case 'adminCompletedTraining': return 'An admin has completed training';
      case 'gpsLocationSet': return 'GPS set, or explicitly marked "add later"';
      case 'associationsReviewed': return 'Associations reviewed (or marked "none yet")';
      default: return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Church>(
      future: _churchFuture,
      builder: (context, churchSnap) {
        if (churchSnap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final church = churchSnap.data;

        return Container(
          padding: const EdgeInsets.all(12),
          color: AppColors.paperDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Church Verification', style: TextStyle(fontFamily: appSerif, fontSize: 15)),
                const SizedBox(width: 8),
                if (church != null)
                  Pill(church.verificationStatus == 'verified' ? 'Verified' : 'Unverified',
                      tone: church.verificationStatus == 'verified' ? 'sage' : 'outline'),
              ]),
              const SizedBox(height: 8),
              FutureBuilder<Map<String, bool>>(
                future: _eligibilityFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                  final conditions = snap.data ?? {};
                  final allMet = conditions.values.every((v) => v);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...conditions.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Icon(e.value ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: e.value ? AppColors.sage : Colors.black38),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_conditionLabel(e.key), style: const TextStyle(fontSize: 12))),
                        ]),
                      )),
                      const SizedBox(height: 8),
                      if (conditions['gpsLocationSet'] == false)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone), minimumSize: const Size(0, 32)),
                          onPressed: () async {
                            await FirestoreService().setGpsExplicitlyDeferred(widget.parishId, widget.churchId, true);
                            setState(_load);
                          },
                          child: const Text('Mark GPS "add later"', style: TextStyle(fontSize: 12)),
                        ),
                      if (conditions['associationsReviewed'] == false)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone), minimumSize: const Size(0, 32)),
                            onPressed: () async {
                              await FirestoreService().setAssociationsReviewed(widget.parishId, widget.churchId, true);
                              setState(_load);
                            },
                            child: const Text('Mark associations reviewed', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (church?.verificationStatus != 'verified')
                        if (!widget.isPriest)
                          const Text('Only a priest can verify a church.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic))
                        else
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: allMet ? AppColors.sage : Colors.grey),
                            onPressed: allMet ? () async {
                              await FirestoreService().verifyChurch(widget.parishId, widget.churchId);
                              setState(_load);
                            } : null,
                            child: const Text('Mark Church Verified'),
                          ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ServiceEditor extends StatelessWidget {
  final String parishId;
  final String churchId;
  final VoidCallback onChanged;
  const _ServiceEditor({super.key, required this.parishId, required this.churchId, required this.onChanged});

  Future<void> _addService(BuildContext context) async {
    DateTime? date = DateTime.now();
    final timeCtrl = TextEditingController(text: '09:00');
    String type = 'Mass';
    String language = 'EN';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('Add Service', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(date != null ? DateFormat('EEEE, d MMM yyyy').format(date!) : 'Pick a date'),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context, initialDate: date ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) setDialogState(() => date = picked);
                },
              ),
              TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'Time (24h, e.g. 09:00)')),
              const SizedBox(height: 10),
              DropdownButton<String>(
                value: type, isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'Mass', child: Text('Mass')),
                  DropdownMenuItem(value: 'CommunionService', child: Text('Communion Service')),
                ],
                onChanged: (v) => setDialogState(() => type = v!),
              ),
              DropdownButton<String>(
                value: language, isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'EN', child: Text('English')),
                  DropdownMenuItem(value: 'AF', child: Text('Afrikaans')),
                ],
                onChanged: (v) => setDialogState(() => language = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                if (date == null || timeCtrl.text.trim().isEmpty) return;
                await FirestoreService().addService(
                  parishId: parishId, churchId: churchId,
                  date: date!, time: timeCtrl.text.trim(), type: type, language: language,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                onChanged();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<ServiceEntry>>(
          future: FirestoreService().getUpcomingServices(parishId, churchId, daysAhead: 14, hidePast: false),
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No services scheduled for this church yet.',
          builder: (context, services) => Column(
            children: services.map((s) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(s.time, style: const TextStyle(fontFamily: appSerif, fontSize: 15)),
              title: Text(DateFormat('EEEE, d MMM').format(s.date)),
              subtitle: Text('${s.type == 'CommunionService' ? 'Communion Service' : 'Mass'} · ${s.language}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: () async {
                  await FirestoreService().deleteService(parishId, churchId, s.id);
                  onChanged();
                },
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => _addService(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Service'),
        ),
      ],
    );
  }
}

class _FinanceToggle extends StatefulWidget {
  final String parishId;
  final bool canEdit;
  const _FinanceToggle({required this.parishId, required this.canEdit});

  @override
  State<_FinanceToggle> createState() => _FinanceToggleState();
}

class _FinanceToggleState extends State<_FinanceToggle> {
  Parish? _parish;

  @override
  void initState() {
    super.initState();
    FirestoreService().getParish(widget.parishId).then((p) {
      if (mounted) setState(() { _parish = p; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_parish == null) return const LinearProgressIndicator();
    final enabled = _parish!.featureFlags['finances'] ?? false;
    return Container(
      padding: const EdgeInsets.all(14),
      color: AppColors.paperDark,
      child: Row(
        children: [
          Icon(enabled ? Icons.visibility : Icons.visibility_off, size: 18),
          const SizedBox(width: 10),
          const Expanded(child: Text('Show finances publicly (applies to every church in this parish)', style: TextStyle(fontSize: 13))),
          Switch(
            value: enabled,
            activeThumbColor: AppColors.brass,
            onChanged: !widget.canEdit ? null : (v) async {
              await FirestoreService().updateFinanceFlag(widget.parishId, v);
              final updated = await FirestoreService().getParish(widget.parishId);
              if (mounted) setState(() { _parish = updated; });
            },
          ),
        ],
      ),
    );
  }
}

class _CommentsAdminList extends StatefulWidget {
  final String parishId;
  const _CommentsAdminList({required this.parishId});

  @override
  State<_CommentsAdminList> createState() => _CommentsAdminListState();
}

class _CommentsAdminListState extends State<_CommentsAdminList> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getAllCommentsForParish(widget.parishId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getAllCommentsForParish(widget.parishId); });

  Future<void> _approve(Map<String, dynamic> comment) async {
    await FirestoreService().approveComment(widget.parishId, comment['churchId'], comment['id']);
    _refresh();
  }

  Future<void> _toggleHidden(Map<String, dynamic> comment, bool hide) async {
    await FirestoreService().setCommentHidden(
      parishId: widget.parishId, churchId: comment['churchId'], commentId: comment['id'],
      hidden: hide, reason: hide ? 'Hidden by parish admin' : null,
    );
    _refresh();
  }

  Future<void> _reply(BuildContext context, Map<String, dynamic> comment) async {
    final ctrl = TextEditingController();
    final adminName = AuthService().currentUser?.displayName ?? 'Parish Office';
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Reply to Comment', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Write a reply...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await FirestoreService().replyToComment(
                parishId: widget.parishId, churchId: comment['churchId'],
                commentId: comment['id'], from: adminName, text: ctrl.text.trim(),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _refresh();
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: _future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No comments yet.',
      builder: (context, comments) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: comments.map((c) {
          final reply = c['reply'] as Map<String, dynamic>?;
          final rating = (c['rating'] as num?)?.toInt() ?? 0;
          final isPending = c['status'] == 'pendingModeration';
          final isHidden = c['hidden'] == true;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            color: isPending ? Colors.amber.withValues(alpha: 0.08) : (isHidden ? Colors.red.withValues(alpha: 0.06) : AppColors.paperDark),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(c['userDisplayName'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    if (isPending) const Pill('Contains a link — pending review', tone: 'outline'),
                    if (isHidden) const Pill('Hidden', tone: 'outline'),
                    const SizedBox(width: 6),
                    Text(c['churchName'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
                Text('★' * rating + '☆' * (5 - rating), style: const TextStyle(color: AppColors.brass, fontSize: 12)),
                const SizedBox(height: 4),
                Text(c['text'] ?? '', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                if (isPending || isHidden)
                  Wrap(
                    spacing: 8,
                    children: [
                      if (isPending)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.sage, minimumSize: const Size(0, 32)),
                          onPressed: () => _approve(c),
                          icon: const Icon(Icons.check, size: 14),
                          label: const Text('Approve', style: TextStyle(fontSize: 12)),
                        ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent), minimumSize: const Size(0, 32)),
                        onPressed: () => _toggleHidden(c, !isHidden),
                        icon: Icon(isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 14),
                        label: Text(isHidden ? 'Unhide' : 'Hide', style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                const SizedBox(height: 4),
                if (reply != null)
                  Container(
                    padding: const EdgeInsets.only(left: 10),
                    decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.sage, width: 2))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reply['from'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        Text(reply['text'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _reply(context, c),
                    icon: const Icon(Icons.reply, size: 15),
                    label: const Text('Reply'),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Shows each open comment report alongside the actual comment being
/// reported (not just the report text alone, which would tell an admin
/// nothing about what to do with it) - Hide Comment and Mark Resolved
/// are two separate actions since resolving a report doesn't have to
/// mean the comment was actually hidden (a report can be reviewed and
/// dismissed as unfounded too).
class _CommentReportsSection extends StatefulWidget {
  final String parishId;
  const _CommentReportsSection({required this.parishId});

  @override
  State<_CommentReportsSection> createState() => _CommentReportsSectionState();
}

class _CommentReportsSectionState extends State<_CommentReportsSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getCommentReportsForParish(widget.parishId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getCommentReportsForParish(widget.parishId); });

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: _future,
      isEmpty: (l) => l.where((r) => r['status'] == 'open').isEmpty,
      emptyMessage: 'No open comment reports.',
      builder: (context, reports) {
        final open = reports.where((r) => r['status'] == 'open').toList();
        if (open.isEmpty) return const Text('No open comment reports.', style: TextStyle(fontSize: 12, color: Colors.black45));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: open.map((r) => _CommentReportTile(
            report: r,
            parishId: widget.parishId,
            onChanged: _refresh,
          )).toList(),
        );
      },
    );
  }
}

class _CommentReportTile extends StatefulWidget {
  final Map<String, dynamic> report;
  final String parishId;
  final VoidCallback onChanged;
  const _CommentReportTile({required this.report, required this.parishId, required this.onChanged});

  @override
  State<_CommentReportTile> createState() => _CommentReportTileState();
}

class _CommentReportTileState extends State<_CommentReportTile> {
  Map<String, dynamic>? _comment;
  bool _loading = true;
  bool _commentGone = false;

  @override
  void initState() {
    super.initState();
    _loadComment();
  }

  Future<void> _loadComment() async {
    // The reported comment may have already been deleted by its own
    // author since the report was filed - handled explicitly rather than
    // left to throw, since a report about content that no longer exists
    // is still a real report an admin needs to be able to close out.
    try {
      final doc = await FirestoreService().getCommentById(
        widget.parishId, widget.report['churchId'], widget.report['targetCommentId'],
      );
      if (mounted) setState(() { _comment = doc; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _commentGone = true; _loading = false; });
    }
  }

  Future<void> _hideComment() async {
    if (_comment == null) return;
    await FirestoreService().setCommentHidden(
      parishId: widget.parishId, churchId: widget.report['churchId'], commentId: widget.report['targetCommentId'],
      hidden: true, reason: 'Hidden after a user report',
    );
    await _resolve();
  }

  Future<void> _resolve() async {
    await FirestoreService().updateReportStatus(widget.parishId, widget.report['churchId'], widget.report['id'], 'resolved');
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      color: Colors.red.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.report['text'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (_commentGone)
            const Text('The reported comment has since been deleted.', style: TextStyle(fontSize: 12, color: Colors.black45, fontStyle: FontStyle.italic))
          else if (_comment != null) ...[
            const Text('Reported comment:', style: TextStyle(fontSize: 11, color: Colors.black45)),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              color: AppColors.paperDark,
              child: Text(_comment!['text'] ?? '', style: const TextStyle(fontSize: 13)),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              if (!_commentGone && _comment != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent), minimumSize: const Size(0, 32)),
                  onPressed: _hideComment,
                  icon: const Icon(Icons.visibility_off_outlined, size: 14),
                  label: const Text('Hide Comment', style: TextStyle(fontSize: 12)),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone), minimumSize: const Size(0, 32)),
                onPressed: _resolve,
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Mark Resolved', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  final bool canApprove;
  const _MediaAdminSection({required this.parishId, required this.churchId, required this.canApprove});

  @override
  State<_MediaAdminSection> createState() => _MediaAdminSectionState();
}

class _MediaAdminSectionState extends State<_MediaAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = FirestoreService().getMedia(widget.parishId, widget.churchId, onlyApproved: false);
  }

  void _refresh() => setState(_load);

  Future<void> _pickAndUpload({required bool isVideo}) async {
    final picker = ImagePicker();
    final file = isVideo
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !mounted) return;

    final captionCtrl = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text('Caption this ${isVideo ? 'video' : 'photo'}', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: TextField(controller: captionCtrl, decoration: const InputDecoration(hintText: 'e.g. Sunday Mass, Feast of St Jude')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () => Navigator.pop(dialogContext, captionCtrl.text.trim()),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (caption == null || !mounted) return;

    setState(() { _uploading = true; });
    try {
      await FirestoreService().uploadMedia(
        parishId: widget.parishId, churchId: widget.churchId,
        file: file, caption: caption.isEmpty ? '(no caption)' : caption, isVideo: isVideo,
      );
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() { _uploading = false; });
    }
  }

  Future<void> _setStatus(String mediaId, String status) async {
    await FirestoreService().updateMediaStatus(parishId: widget.parishId, churchId: widget.churchId, mediaId: mediaId, status: status);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
              onPressed: _uploading ? null : () => _pickAndUpload(isVideo: false),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: const Text('Upload Photo'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
              onPressed: _uploading ? null : () => _pickAndUpload(isVideo: true),
              icon: const Icon(Icons.videocam_outlined, size: 16),
              label: const Text('Upload Video'),
            ),
          ],
        ),
        if (_uploading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        const SizedBox(height: 16),
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No photos or videos uploaded yet.',
          builder: (context, media) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: media.map((m) {
              final status = m['status'] as String? ?? 'pending';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                color: AppColors.paperDark,
                child: Row(
                  children: [
                    Icon(m['kind'] == 'video' ? Icons.videocam : Icons.image, size: 20, color: AppColors.stone),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m['caption'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text('by ${m['uploadedByName'] ?? 'Unknown'}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        ],
                      ),
                    ),
                    if (status == 'pending' && widget.canApprove) ...[
                      IconButton(
                        icon: const Icon(Icons.check_circle_outline, color: AppColors.sage, size: 22),
                        onPressed: () => _setStatus(m['id'], 'approved'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 22),
                        onPressed: () => _setStatus(m['id'], 'rejected'),
                      ),
                    ] else
                      Pill(status[0].toUpperCase() + status.substring(1), tone: status == 'approved' ? 'sage' : 'outline'),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        if (!widget.canApprove)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Only the parish priest can approve or reject uploads.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }
}

class _SongBookAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _SongBookAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_SongBookAdminSection> createState() => _SongBookAdminSectionState();
}

class _SongBookAdminSectionState extends State<_SongBookAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getSongs(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getSongs(widget.parishId, widget.churchId); });

  Future<void> _addSong(BuildContext context) async {
    final numberCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final hymnalCtrl = TextEditingController();
    final lyricsCtrl = TextEditingController();
    String language = 'EN';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('Add Song', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: numberCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Song number')),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                TextField(controller: hymnalCtrl, decoration: const InputDecoration(labelText: 'Hymnal / book (optional)', hintText: 'e.g. Laudate')),
                DropdownButton<String>(
                  value: language, isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'EN', child: Text('English')),
                    DropdownMenuItem(value: 'AF', child: Text('Afrikaans')),
                  ],
                  onChanged: (v) => setDialogState(() => language = v!),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: lyricsCtrl, maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Lyrics (optional)', hintText: 'Only if your parish has the rights to reproduce this'),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Leave lyrics blank unless this song is public domain or your parish has proper licensing to display it.',
                      style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                final number = int.tryParse(numberCtrl.text.trim());
                if (number == null || titleCtrl.text.trim().isEmpty) return;
                await FirestoreService().addSong(
                  parishId: widget.parishId, churchId: widget.churchId,
                  number: number, title: titleCtrl.text.trim(),
                  hymnal: hymnalCtrl.text.trim().isEmpty ? null : hymnalCtrl.text.trim(),
                  language: language,
                  lyrics: lyricsCtrl.text.trim().isEmpty ? null : lyricsCtrl.text.trim(),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _refresh();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No songs added for this church yet.',
          builder: (context, songs) => Column(
            children: songs.map((s) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text('#${s['number']}', style: const TextStyle(fontFamily: appSerif, fontSize: 15, color: AppColors.brass)),
              title: Text(s['title'] ?? ''),
              subtitle: Text([s['hymnal'], s['language']].where((e) => e != null).join(' · ')),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: () async {
                  await FirestoreService().deleteSong(widget.parishId, widget.churchId, s['id']);
                  _refresh();
                },
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => _addSong(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Song'),
        ),
      ],
    );
  }
}

class _PrayersAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _PrayersAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_PrayersAdminSection> createState() => _PrayersAdminSectionState();
}

class _PrayersAdminSectionState extends State<_PrayersAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getPrayers(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getPrayers(widget.parishId, widget.churchId); });

  Future<void> _addPrayer(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final textCtrl = TextEditingController();
    String language = 'EN';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('Add Prayer', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Our Father')),
                DropdownButton<String>(
                  value: language, isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'EN', child: Text('English')),
                    DropdownMenuItem(value: 'AF', child: Text('Afrikaans')),
                  ],
                  onChanged: (v) => setDialogState(() => language = v!),
                ),
                const SizedBox(height: 8),
                TextField(controller: textCtrl, maxLines: 6, decoration: const InputDecoration(labelText: 'Prayer text')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty || textCtrl.text.trim().isEmpty) return;
                await FirestoreService().addPrayer(
                  parishId: widget.parishId, churchId: widget.churchId,
                  title: titleCtrl.text.trim(), text: textCtrl.text.trim(), language: language,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _refresh();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No prayers added for this church yet.',
          builder: (context, prayers) => Column(
            children: prayers.map((p) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p['title'] ?? ''),
              subtitle: Text(p['language'] ?? 'EN'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: () async {
                  await FirestoreService().deletePrayer(widget.parishId, widget.churchId, p['id']);
                  _refresh();
                },
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => _addPrayer(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Prayer'),
        ),
      ],
    );
  }
}

class _CoursesAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  final bool isPriest;
  const _CoursesAdminSection({super.key, required this.parishId, required this.churchId, required this.isPriest});

  @override
  State<_CoursesAdminSection> createState() => _CoursesAdminSectionState();
}

class _CoursesAdminSectionState extends State<_CoursesAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = FirestoreService().getCourses(widget.parishId, widget.churchId, onlyPublished: false);
  void _refresh() => setState(_load);

  Future<void> _addCourse(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final catechistCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    bool devOnly = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Add Course', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. First Communion Preparation')),
              TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
              TextField(controller: catechistCtrl, decoration: const InputDecoration(labelText: 'Catechist / Teacher name')),
              TextField(controller: linkCtrl, decoration: const InputDecoration(labelText: 'Live session link (optional)', hintText: 'Zoom, Teams, BigBlueButton, WhatsApp...')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Colors.redAccent,
                title: const Text('Developer Only', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Still being built - only Developers and Super Admins can see it', style: TextStyle(fontSize: 11)),
                value: devOnly,
                onChanged: (v) => setDialogState(() => devOnly = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              await FirestoreService().addCourse(
                parishId: widget.parishId, churchId: widget.churchId,
                title: titleCtrl.text.trim(), description: descCtrl.text.trim(),
                catechistName: catechistCtrl.text.trim(),
                meetingLink: linkCtrl.text.trim().isEmpty ? null : linkCtrl.text.trim(),
                devOnly: devOnly,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _refresh();
            },
            child: const Text('Create'),
          ),
        ],
      ),
      ),
    );
  }


  Future<void> _deleteLesson(BuildContext context, String courseId, Map<String, dynamic> lesson) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Delete Lesson?', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: Text('"${lesson['title']}" and its quiz (if any) will be permanently removed. This can\'t be undone.', style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirestoreService().deleteQuizForLesson(widget.parishId, widget.churchId, courseId, lesson['id']);
      await FirestoreService().deleteLesson(
        parishId: widget.parishId, churchId: widget.churchId, courseId: courseId, lessonId: lesson['id'],
      );
      _refresh();
    }
  }

  Future<void> _setStatus(String courseId, String status) async {
    await FirestoreService().updateCourseStatus(parishId: widget.parishId, churchId: widget.churchId, courseId: courseId, status: status);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No courses for this church yet.',
          builder: (context, courses) => Column(
            children: courses.map((c) {
              final status = c['status'] as String? ?? 'draft';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                color: AppColors.paperDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(c['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                        Pill(status, tone: status == 'published' ? 'sage' : 'outline'),
                      ],
                    ),
                    Text(c['catechistName'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 8),
                    AsyncSection<List<Map<String, dynamic>>>(
                      future: FirestoreService().getLessons(widget.parishId, widget.churchId, c['id']),
                      isEmpty: (l) => l.isEmpty,
                      emptyMessage: 'No lessons yet.',
                      builder: (context, lessons) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ReorderableListView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            onReorder: (oldIndex, newIndex) async {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final reordered = [...lessons];
                              final item = reordered.removeAt(oldIndex);
                              reordered.insert(newIndex, item);
                              await FirestoreService().reorderLessons(
                                parishId: widget.parishId, churchId: widget.churchId, courseId: c['id'],
                                orderedLessonIds: reordered.map((l) => l['id'] as String).toList(),
                              );
                              setState(() {});
                            },
                            children: [
                              for (final l in lessons)
                                Padding(
                                  key: ValueKey(l['id']),
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.drag_handle, size: 14, color: Colors.black38),
                                      const SizedBox(width: 4),
                                      Expanded(child: Text(l['title'] ?? '', style: const TextStyle(fontSize: 12))),
                                      Checkbox(
                                        value: l['verified'] == true,
                                        activeColor: AppColors.sage,
                                        onChanged: (v) async {
                                          await FirestoreService().setLessonVerified(
                                            parishId: widget.parishId, churchId: widget.churchId,
                                            courseId: c['id'], lessonId: l['id'], verified: v ?? false,
                                          );
                                          setState(() {});
                                        },
                                      ),
                                      const Text('Verified', style: TextStyle(fontSize: 11, color: Colors.black45)),
                                      IconButton(
                                        tooltip: 'Manage Quiz',
                                        icon: const Icon(Icons.quiz_outlined, size: 16, color: AppColors.stone),
                                        onPressed: () => showDialog(
                                          context: context,
                                          builder: (_) => _ManageQuizDialog(
                                            parishId: widget.parishId, churchId: widget.churchId,
                                            courseId: c['id'], lessonId: l['id'], lessonTitle: l['title'] ?? '',
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Edit Lesson',
                                        icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.stone),
                                        onPressed: () async {
                                          final saved = await Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => LessonEditorScreen(
                                              parishId: widget.parishId, churchId: widget.churchId, courseId: c['id'],
                                              existing: l, nextOrder: lessons.length + 1,
                                            ),
                                          ));
                                          if (saved == true) setState(() {});
                                        },
                                      ),
                                      IconButton(
                                        tooltip: 'Delete Lesson',
                                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                        onPressed: () => _deleteLesson(context, c['id'], l),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final saved = await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => LessonEditorScreen(
                                  parishId: widget.parishId, churchId: widget.churchId, courseId: c['id'],
                                  nextOrder: lessons.length + 1,
                                ),
                              ));
                              if (saved == true) setState(() {});
                            },
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('Add Lesson', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (status == 'draft')
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                            onPressed: () => _setStatus(c['id'], 'pendingReview'),
                            child: const Text('Submit for Review', style: TextStyle(fontSize: 12)),
                          ),
                        if (status == 'pendingReview' && widget.isPriest) ...[
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.sage),
                            onPressed: () => _setStatus(c['id'], 'published'),
                            child: const Text('Approve & Publish', style: TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                            onPressed: () => _setStatus(c['id'], 'draft'),
                            child: const Text('Send Back', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                        if (status == 'pendingReview' && !widget.isPriest)
                          const Text('Awaiting priest review', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => _addCourse(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Course'),
        ),
      ],
    );
  }
}

class _BookingsAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _BookingsAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_BookingsAdminSection> createState() => _BookingsAdminSectionState();
}

class _BookingsAdminSectionState extends State<_BookingsAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getConfessionBookingRequests(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getConfessionBookingRequests(widget.parishId, widget.churchId); });

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: _future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No confession booking requests for this church.',
      builder: (context, requests) => Column(
        children: requests.map((r) {
          final status = r['status'] as String? ?? 'pending';
          final createdAt = r['createdAt'] as Timestamp?;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                    Pill(status, tone: status == 'contacted' ? 'sage' : 'outline'),
                  ],
                ),
                if (createdAt != null)
                  Text(DateFormat('d MMM yyyy, HH:mm').format(createdAt.toDate()), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.phone, size: 14, color: AppColors.stone),
                  const SizedBox(width: 6),
                  Text(r['contactPhone'] ?? '', style: const TextStyle(fontSize: 13)),
                ]),
                if ((r['contactEmail'] as String?)?.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const Icon(Icons.email_outlined, size: 14, color: AppColors.stone),
                      const SizedBox(width: 6),
                      Text(r['contactEmail'], style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
                const SizedBox(height: 4),
                Text('Availability: ${r['availability'] ?? ''}', style: const TextStyle(fontSize: 13)),
                if (status != 'contacted') ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.sage, side: const BorderSide(color: AppColors.sage)),
                    onPressed: () async {
                      await FirestoreService().updateBookingStatus(widget.parishId, widget.churchId, r['id'], 'contacted');
                      _refresh();
                    },
                    child: const Text('Mark as Contacted', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ReportsAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _ReportsAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_ReportsAdminSection> createState() => _ReportsAdminSectionState();
}

class _ReportsAdminSectionState extends State<_ReportsAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getReports(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getReports(widget.parishId, widget.churchId); });

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: _future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No reported issues for this church.',
      builder: (context, reports) => Column(
        children: reports.map((r) {
          final status = r['status'] as String? ?? 'open';
          final createdAt = r['createdAt'] as Timestamp?;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag_outlined, size: 16, color: Colors.redAccent),
                    const SizedBox(width: 6),
                    Expanded(child: Text(r['text'] ?? '', style: const TextStyle(fontSize: 13))),
                    Pill(status, tone: status == 'resolved' ? 'sage' : 'outline'),
                  ],
                ),
                if (createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 22),
                    child: Text(DateFormat('d MMM yyyy, HH:mm').format(createdAt.toDate()), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                  ),
                if (status != 'resolved') ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.sage, side: const BorderSide(color: AppColors.sage)),
                    onPressed: () async {
                      await FirestoreService().updateReportStatus(widget.parishId, widget.churchId, r['id'], 'resolved');
                      _refresh();
                    },
                    child: const Text('Mark as Resolved', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DevotionsAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _DevotionsAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_DevotionsAdminSection> createState() => _DevotionsAdminSectionState();
}

class _DevotionsAdminSectionState extends State<_DevotionsAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getDevotions(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getDevotions(widget.parishId, widget.churchId); });

  Future<void> _add(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: '18:00');
    String dayOfWeek = 'Thursday';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('Add Devotion', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Eucharistic Adoration')),
              DropdownButton<String>(
                value: dayOfWeek, isExpanded: true,
                items: const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
                    .map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (v) => setDialogState(() => dayOfWeek = v!),
              ),
              TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'Time (24h)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await FirestoreService().addDevotion(
                  parishId: widget.parishId, churchId: widget.churchId,
                  name: nameCtrl.text.trim(), dayOfWeek: dayOfWeek, time: timeCtrl.text.trim(),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _refresh();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No devotions listed for this church.',
          builder: (context, devotions) => Column(
            children: devotions.map((d) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.watch_later_outlined, size: 18, color: AppColors.brass),
              title: Text(d['name'] ?? ''),
              subtitle: Text('${d['dayOfWeek']} · ${d['time']}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: () async {
                  await FirestoreService().deleteDevotion(widget.parishId, widget.churchId, d['id']);
                  _refresh();
                },
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => _add(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Devotion'),
        ),
      ],
    );
  }
}

class _ParishAssociationsAdminSection extends StatefulWidget {
  final String parishId;
  const _ParishAssociationsAdminSection({required this.parishId});

  @override
  State<_ParishAssociationsAdminSection> createState() => _ParishAssociationsAdminSectionState();
}

class _ParishAssociationsAdminSectionState extends State<_ParishAssociationsAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getParishAssociations(widget.parishId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getParishAssociations(widget.parishId); });

  Future<void> _showForm(BuildContext context, {Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final purposeCtrl = TextEditingController(text: existing?['purpose'] ?? '');
    final contactCtrl = TextEditingController(text: existing?['contactPerson'] ?? '');
    final dayCtrl = TextEditingController(text: existing?['meetingDay'] ?? '');
    final timeCtrl = TextEditingController(text: existing?['meetingTime'] ?? '');
    final isEdit = existing != null;

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text(isEdit ? 'Edit Parish Association' : 'Add Parish Association', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Catholic Women\'s League')),
              TextField(controller: purposeCtrl, decoration: const InputDecoration(labelText: 'Purpose (optional)')),
              TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contact person (optional)')),
              TextField(controller: dayCtrl, decoration: const InputDecoration(labelText: 'Meeting day (optional)')),
              TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'Meeting time (optional)')),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Visible across every church in this parish.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final name = nameCtrl.text.trim();
              final purpose = purposeCtrl.text.trim().isEmpty ? null : purposeCtrl.text.trim();
              final contact = contactCtrl.text.trim().isEmpty ? null : contactCtrl.text.trim();
              final day = dayCtrl.text.trim().isEmpty ? null : dayCtrl.text.trim();
              final time = timeCtrl.text.trim().isEmpty ? null : timeCtrl.text.trim();
              if (isEdit) {
                await FirestoreService().updateParishAssociation(
                  parishId: widget.parishId, associationId: existing['id'],
                  name: name, purpose: purpose, contactPerson: contact, meetingDay: day, meetingTime: time,
                );
              } else {
                await FirestoreService().addParishAssociation(
                  parishId: widget.parishId,
                  name: name, purpose: purpose, contactPerson: contact, meetingDay: day, meetingTime: time,
                );
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _refresh();
            },
            child: Text(isEdit ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No parish-wide associations yet.',
          builder: (context, list) => Column(
            children: list.map((a) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(a['name'] ?? ''),
              subtitle: Text([a['meetingDay'], a['meetingTime'], a['contactPerson']].where((e) => e != null).join(' \u00b7 ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: AppColors.stone, size: 20),
                    onPressed: () => _showForm(context, existing: a),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    onPressed: () async {
                      await FirestoreService().deleteParishAssociation(widget.parishId, a['id']);
                      _refresh();
                    },
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => _showForm(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Parish-Wide Association'),
        ),
      ],
    );
  }
}

class _AssociationsAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _AssociationsAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_AssociationsAdminSection> createState() => _AssociationsAdminSectionState();
}

class _AssociationsAdminSectionState extends State<_AssociationsAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getChurchAssociationsOnly(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getChurchAssociationsOnly(widget.parishId, widget.churchId); });

  Future<void> _add(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final purposeCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final dayCtrl = TextEditingController();
    final timeCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Add Association', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Choir')),
              TextField(controller: purposeCtrl, decoration: const InputDecoration(labelText: 'Purpose (optional)')),
              TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contact person (optional)')),
              TextField(controller: dayCtrl, decoration: const InputDecoration(labelText: 'Meeting day (optional)')),
              TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'Meeting time (optional)')),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('This adds a church-specific group (like a choir). The parish-wide list (CWL, SVP, etc.) isn\'t editable here yet.',
                    style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await FirestoreService().addChurchAssociation(
                parishId: widget.parishId, churchId: widget.churchId,
                name: nameCtrl.text.trim(),
                purpose: purposeCtrl.text.trim().isEmpty ? null : purposeCtrl.text.trim(),
                contactPerson: contactCtrl.text.trim().isEmpty ? null : contactCtrl.text.trim(),
                meetingDay: dayCtrl.text.trim().isEmpty ? null : dayCtrl.text.trim(),
                meetingTime: timeCtrl.text.trim().isEmpty ? null : timeCtrl.text.trim(),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _refresh();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, Map<String, dynamic> association) async {
    final nameCtrl = TextEditingController(text: association['name'] ?? '');
    final purposeCtrl = TextEditingController(text: association['purpose'] ?? '');
    final contactCtrl = TextEditingController(text: association['contactPerson'] ?? '');
    final dayCtrl = TextEditingController(text: association['meetingDay'] ?? '');
    final timeCtrl = TextEditingController(text: association['meetingTime'] ?? '');

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Edit Association', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Choir')),
              TextField(controller: purposeCtrl, decoration: const InputDecoration(labelText: 'Purpose (optional)')),
              TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contact person (optional)')),
              TextField(controller: dayCtrl, decoration: const InputDecoration(labelText: 'Meeting day (optional)')),
              TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'Meeting time (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await FirestoreService().updateChurchAssociation(
                parishId: widget.parishId, churchId: widget.churchId, associationId: association['id'],
                name: nameCtrl.text.trim(),
                purpose: purposeCtrl.text.trim().isEmpty ? null : purposeCtrl.text.trim(),
                contactPerson: contactCtrl.text.trim().isEmpty ? null : contactCtrl.text.trim(),
                meetingDay: dayCtrl.text.trim().isEmpty ? null : dayCtrl.text.trim(),
                meetingTime: timeCtrl.text.trim().isEmpty ? null : timeCtrl.text.trim(),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _refresh();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No church-specific associations yet (parish-wide ones like CWL/SVP are managed separately).',
          builder: (context, list) => Column(
            children: list.map((a) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(a['name'] ?? ''),
              subtitle: Text([a['meetingDay'], a['meetingTime'], a['contactPerson']].where((e) => e != null).join(' · ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: AppColors.stone, size: 20),
                    onPressed: () => _edit(context, a),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    onPressed: () async {
                      await FirestoreService().deleteChurchAssociation(widget.parishId, widget.churchId, a['id']);
                      _refresh();
                    },
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => _add(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Association'),
        ),
      ],
    );
  }
}

class _NoticesAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _NoticesAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_NoticesAdminSection> createState() => _NoticesAdminSectionState();
}

class _NoticesAdminSectionState extends State<_NoticesAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getNotices(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getNotices(widget.parishId, widget.churchId); });

  Future<void> _add(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final associations = await FirestoreService().getAssociations(widget.parishId, widget.churchId);
    String? selectedAssociationId;

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('Add Notice', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Baptisms')),
                TextField(controller: bodyCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Notice text')),
                const SizedBox(height: 10),
                const Text('Belongs to', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                DropdownButton<String?>(
                  value: selectedAssociationId,
                  isExpanded: true,
                  hint: const Text('Parish-wide (seen by everyone)', style: TextStyle(fontSize: 13)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Parish-wide (seen by everyone)')),
                    ...associations.map((a) => DropdownMenuItem<String?>(value: a['id'] as String, child: Text(a['name'] ?? ''))),
                  ],
                  onChanged: (v) => setDialogState(() => selectedAssociationId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) return;
                await FirestoreService().addNotice(
                  parishId: widget.parishId, churchId: widget.churchId,
                  title: titleCtrl.text.trim(), body: bodyCtrl.text.trim(),
                  associationId: selectedAssociationId,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _refresh();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No notices posted for this church.',
          builder: (context, notices) => Column(
            children: notices.map((n) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(n['title'] ?? ''),
              subtitle: Text(n['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: () async {
                  await FirestoreService().deleteNotice(widget.parishId, widget.churchId, n['id']);
                  _refresh();
                },
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => _add(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Notice'),
        ),
      ],
    );
  }
}

class _EventsAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _EventsAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_EventsAdminSection> createState() => _EventsAdminSectionState();
}

class _EventsAdminSectionState extends State<_EventsAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getEvents(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getEvents(widget.parishId, widget.churchId); });

  Future<void> _showForm(BuildContext context, {Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final titleCtrl = TextEditingController(text: existing?['title'] ?? '');
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    final timeCtrl = TextEditingController(text: existing?['time'] ?? '09:00');
    final categoryCtrl = TextEditingController(text: existing?['category'] ?? '');
    DateTime? date = existing != null ? (existing['date'] as Timestamp).toDate() : DateTime.now();
    bool showInNotices = existing?['showInNotices'] == true;
    final associations = await FirestoreService().getAssociations(widget.parishId, widget.churchId);
    String? selectedAssociationId = existing?['associationId'];

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: Text(isEdit ? 'Edit Event' : 'Add Event', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(date != null ? DateFormat('EEEE, d MMM yyyy').format(date!) : 'Pick a date'),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context, initialDate: date ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: 'Time (24h)')),
                TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category (optional)', hintText: 'e.g. Community, Wedding, Funeral')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.brass,
                  title: const Text('Also show in Parochial Notices until it happens', style: TextStyle(fontSize: 13)),
                  value: showInNotices,
                  onChanged: (v) => setDialogState(() => showInNotices = v),
                ),
                const SizedBox(height: 6),
                const Text('Belongs to', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                DropdownButton<String?>(
                  value: selectedAssociationId,
                  isExpanded: true,
                  hint: const Text('Parish-wide (seen by everyone)', style: TextStyle(fontSize: 13)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Parish-wide (seen by everyone)')),
                    ...associations.map((a) => DropdownMenuItem<String?>(value: a['id'] as String, child: Text(a['name'] ?? ''))),
                  ],
                  onChanged: (v) => setDialogState(() => selectedAssociationId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty || date == null) return;
                if (isEdit) {
                  await FirestoreService().updateEvent(
                    parishId: widget.parishId, churchId: widget.churchId, eventId: existing['id'],
                    title: titleCtrl.text.trim(), description: descCtrl.text.trim(),
                    date: date!, time: timeCtrl.text.trim(),
                    category: categoryCtrl.text.trim().isEmpty ? null : categoryCtrl.text.trim(),
                    showInNotices: showInNotices,
                    associationId: selectedAssociationId,
                  );
                } else {
                  await FirestoreService().addEvent(
                    parishId: widget.parishId, churchId: widget.churchId,
                    title: titleCtrl.text.trim(), description: descCtrl.text.trim(),
                    date: date!, time: timeCtrl.text.trim(),
                    category: categoryCtrl.text.trim().isEmpty ? null : categoryCtrl.text.trim(),
                    showInNotices: showInNotices,
                    associationId: selectedAssociationId,
                  );
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _refresh();
              },
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No events for this church.',
          builder: (context, events) => Column(
            children: events.map((e) {
              final date = (e['date'] as Timestamp?)?.toDate();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e['title'] ?? ''),
                subtitle: Text('${date != null ? DateFormat('d MMM yyyy').format(date) : ''} · ${e['time'] ?? ''}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.people_outline, color: AppColors.stone, size: 20),
                      tooltip: 'View Attendees',
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _EventAttendeesDialog(parishId: widget.parishId, churchId: widget.churchId, eventId: e['id'], eventTitle: e['title'] ?? ''),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.menu_book_outlined, color: AppColors.stone, size: 20),
                      tooltip: 'Set Readings for This Event',
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _EventReadingsDialog(
                          date: date ?? DateTime.now(), eventId: e['id'], eventTitle: e['title'] ?? '',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: AppColors.stone, size: 20),
                      onPressed: () => _showForm(context, existing: e),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      onPressed: () async {
                        await FirestoreService().deleteEvent(widget.parishId, widget.churchId, e['id']);
                        _refresh();
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => _showForm(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Event'),
        ),
      ],
    );
  }
}

class _MassIntentionsAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _MassIntentionsAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_MassIntentionsAdminSection> createState() => _MassIntentionsAdminSectionState();
}

class _MassIntentionsAdminSectionState extends State<_MassIntentionsAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getMassIntentionRequests(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getMassIntentionRequests(widget.parishId, widget.churchId); });

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: _future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No Mass intention requests for this church.',
      builder: (context, requests) => Column(
        children: requests.map((r) {
          final status = r['status'] as String? ?? 'pending';
          final createdAt = r['createdAt'] as Timestamp?;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(r['requesterName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                    Pill(status, tone: status == 'scheduled' ? 'sage' : 'outline'),
                  ],
                ),
                if (createdAt != null)
                  Text(DateFormat('d MMM yyyy, HH:mm').format(createdAt.toDate()), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                const SizedBox(height: 6),
                Text('Intention: ${r['intentionFor'] ?? ''}', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                if ((r['preferredDate'] as String?)?.isNotEmpty ?? false)
                  Text('Preferred date: ${r['preferredDate']}', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.phone, size: 14, color: AppColors.stone),
                  const SizedBox(width: 6),
                  Text(r['contactPhone'] ?? '', style: const TextStyle(fontSize: 13)),
                ]),
                if (status != 'scheduled') ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.sage, side: const BorderSide(color: AppColors.sage)),
                    onPressed: () async {
                      await FirestoreService().updateMassIntentionStatus(widget.parishId, widget.churchId, r['id'], 'scheduled');
                      _refresh();
                    },
                    child: const Text('Mark as Scheduled', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EventAttendeesDialog extends StatelessWidget {
  final String parishId;
  final String churchId;
  final String eventId;
  final String eventTitle;
  const _EventAttendeesDialog({required this.parishId, required this.churchId, required this.eventId, required this.eventTitle});

  String _needLabel(String? need) {
    switch (need) {
      case 'hearing': return 'Needs hearing assistance';
      case 'vision': return 'Needs vision assistance';
      case 'mobility': return 'Needs mobility / wheelchair access';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text('Attendees — $eventTitle', style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: FirestoreService().getEventAttendees(parishId, churchId, eventId),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator()));
            }
            final attendees = snap.data ?? [];
            if (attendees.isEmpty) return const Text('No one has RSVPed yet.', style: TextStyle(fontSize: 13, color: Colors.black54));

            final reserved = attendees.where((a) => a['seatTag'] == 'reserved').toList();
            final regular = attendees.where((a) => a['seatTag'] != 'reserved').toList();

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${attendees.length} attending total (${reserved.length} needing a reserved seat)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  if (reserved.isNotEmpty) ...[
                    const Text('Reserved seats needed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brass)),
                    ...reserved.map((a) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.accessible, size: 16, color: AppColors.brass),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text(_needLabel(a['accessibilityNeed']), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                if (a['contactPhone'] != null) Text('Contact: ${a['contactPhone']}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 10),
                  ],
                  if (regular.isNotEmpty) ...[
                    const Text('Also attending', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ...regular.map((a) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(a['name'] ?? '', style: const TextStyle(fontSize: 13)),
                    )),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _MarketplaceAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _MarketplaceAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_MarketplaceAdminSection> createState() => _MarketplaceAdminSectionState();
}

class _MarketplaceAdminSectionState extends State<_MarketplaceAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getAllProducts(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getAllProducts(widget.parishId, widget.churchId); });

  Future<void> _setStatus(String productId, String status) async {
    await FirestoreService().updateProductStatus(widget.parishId, widget.churchId, productId, status);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: _future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No marketplace listings for this church.',
      builder: (context, products) => Column(
        children: products.map((p) {
          final status = p['status'] as String? ?? 'pending';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(p['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                  Pill(status, tone: status == 'approved' ? 'sage' : 'outline'),
                  IconButton(
                    tooltip: 'Delete Listing',
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    onPressed: () async {
                      await FirestoreService().deleteProduct(widget.parishId, widget.churchId, p['id']);
                      _refresh();
                    },
                  ),
                ]),
                Text('R${(p['price'] as num?)?.toStringAsFixed(2) ?? '0.00'} · ${p['sellerName'] ?? ''}', style: const TextStyle(fontSize: 12)),
                if ((p['description'] as String?)?.isNotEmpty ?? false)
                  Text(p['description'], style: const TextStyle(fontSize: 12, color: Colors.black54)),
                Text('Contact: ${p['sellerContact'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                if (status == 'pending') ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.sage),
                      onPressed: () => _setStatus(p['id'], 'approved'),
                      child: const Text('Approve', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                      onPressed: () => _setStatus(p['id'], 'rejected'),
                      child: const Text('Reject', style: TextStyle(fontSize: 12)),
                    ),
                  ]),
                ] else if (status == 'approved') ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                    onPressed: () => _setStatus(p['id'], 'rejected'),
                    child: const Text('Take Down', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MarketplaceOrdersAdminSection extends StatefulWidget {
  final String churchId;
  const _MarketplaceOrdersAdminSection({super.key, required this.churchId});

  @override
  State<_MarketplaceOrdersAdminSection> createState() => _MarketplaceOrdersAdminSectionState();
}

class _MarketplaceOrdersAdminSectionState extends State<_MarketplaceOrdersAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getOrdersForChurch(widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getOrdersForChurch(widget.churchId); });

  Future<void> _setStatus(Map<String, dynamic> order, String status) async {
    await FirestoreService().updateOrderStatus(
      parishId: order['parishId'], churchId: order['churchId'],
      productId: order['productId'], orderId: order['id'], status: status,
    );
    _refresh();
  }

  Future<void> _setFulfillment(Map<String, dynamic> order, String status) async {
    await FirestoreService().updateOrderFulfillmentStatus(
      parishId: order['parishId'], churchId: order['churchId'],
      productId: order['productId'], orderId: order['id'], fulfillmentStatus: status,
    );
    _refresh();
  }

  Future<void> _setRefundStatus(Map<String, dynamic> order, String status) async {
    await FirestoreService().updateOrderRefundStatus(
      parishId: order['parishId'], churchId: order['churchId'],
      productId: order['productId'], orderId: order['id'], refundStatus: status,
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: _future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No marketplace orders for this church yet.',
      builder: (context, orders) => Column(
        children: orders.map((o) {
          final status = o['status'] as String? ?? 'awaiting_payment';
          final proofUrl = o['proofOfPaymentUrl'] as String?;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text('${o['productTitle'] ?? ''} × ${o['quantity'] ?? 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                  Pill(status.replaceAll('_', ' '), tone: status == 'approved' ? 'sage' : 'outline'),
                ]),
                Text('Buyer: ${o['buyerName'] ?? ''} · ${o['buyerContact'] ?? ''}', style: const TextStyle(fontSize: 12)),
                Text('Total: R${(o['finalAmount'] as num?)?.toStringAsFixed(2) ?? '0.00'}${o['couponCode'] != null ? ' (coupon ${o['couponCode']})' : ''}', style: const TextStyle(fontSize: 12, color: AppColors.brass, fontWeight: FontWeight.w600)),
                if (((o['platformFeeAmount'] as num?) ?? 0) > 0)
                  Text(
                    'Platform fee: R${(o['platformFeeAmount'] as num).toStringAsFixed(2)} · Seller payout: R${(o['sellerPayoutAmount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                if (proofUrl != null) ...[
                  const SizedBox(height: 8),
                  if (o['proofOfPaymentType'] == 'pdf')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                      onPressed: () => launchUrl(Uri.parse(proofUrl), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('View Proof (PDF)', style: TextStyle(fontSize: 12)),
                    )
                  else
                    GestureDetector(
                      onTap: () => showDialog(context: context, builder: (_) => Dialog(child: Image.network(proofUrl))),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(proofUrl, height: 100, width: 100, fit: BoxFit.cover),
                      ),
                    ),
                ],
                if (status == 'proof_submitted') ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.sage),
                      onPressed: () => _setStatus(o, 'approved'),
                      child: const Text('Approve Payment', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                      onPressed: () => _setStatus(o, 'rejected'),
                      child: const Text('Reject', style: TextStyle(fontSize: 12)),
                    ),
                  ]),
                ] else if (status == 'awaiting_payment')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Waiting for buyer to upload proof of payment.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
                  ),

                if (status == 'approved') ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(o['fulfillmentMethod'] == 'courier' ? Icons.local_shipping_outlined : Icons.storefront_outlined, size: 14, color: AppColors.stone),
                    const SizedBox(width: 6),
                    Text(
                      o['fulfillmentMethod'] == 'courier'
                          ? 'Courier · ${o['deliveryAddress'] ?? ''}'
                          : 'Collect in person',
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  if ((o['fulfillmentStatus'] ?? 'pending') == 'pending')
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                      onPressed: () => _setFulfillment(o, 'ready'),
                      child: Text(o['fulfillmentMethod'] == 'courier' ? 'Mark Dispatched' : 'Mark Ready for Pickup', style: const TextStyle(fontSize: 12)),
                    )
                  else if ((o['fulfillmentStatus'] ?? '') == 'ready')
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.sage, side: const BorderSide(color: AppColors.sage)),
                      onPressed: () => _setFulfillment(o, 'completed'),
                      child: Text(o['fulfillmentMethod'] == 'courier' ? 'Mark Delivered' : 'Mark Collected', style: const TextStyle(fontSize: 12)),
                    )
                  else
                    Text(o['fulfillmentMethod'] == 'courier' ? 'Delivered' : 'Collected', style: const TextStyle(fontSize: 12, color: AppColors.sage, fontWeight: FontWeight.w600)),
                ],

                if (o['refundStatus'] == 'requested') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(border: Border.all(color: Colors.orange)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Refund requested: R${(o['refundAmount'] as num?)?.toStringAsFixed(2) ?? '0.00'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                        if ((o['refundReason'] as String?)?.isNotEmpty ?? false)
                          Text('"${o['refundReason']}"', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, children: [
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.sage),
                            onPressed: () => _setRefundStatus(o, 'approved'),
                            child: const Text('Approve Refund', style: TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                            onPressed: () => _setRefundStatus(o, 'denied'),
                            child: const Text('Deny', style: TextStyle(fontSize: 12)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ] else if (o['refundStatus'] == 'approved')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                      onPressed: () => _setRefundStatus(o, 'processed'),
                      child: const Text('Mark Refund Sent', style: TextStyle(fontSize: 12)),
                    ),
                  )
                else if (o['refundStatus'] == 'processed')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Refund sent', style: TextStyle(fontSize: 12, color: AppColors.sage, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DonationsAdminSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _DonationsAdminSection({super.key, required this.parishId, required this.churchId});

  @override
  State<_DonationsAdminSection> createState() => _DonationsAdminSectionState();
}

class _DonationsAdminSectionState extends State<_DonationsAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getDonationsForChurch(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getDonationsForChurch(widget.parishId, widget.churchId); });

  Future<void> _setStatus(String donationId, String status, {String? note}) async {
    await FirestoreService().updateDonationStatus(
      parishId: widget.parishId, churchId: widget.churchId, donationId: donationId, status: status, adminNote: note,
    );
    _refresh();
  }

  Future<void> _confirmWrongBank(String donationId) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Mark as Wrong Bank', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The donor will be notified to contact their bank about a reversal. Add a short note if useful.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 10),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note to donor (optional)'), maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _setStatus(donationId, 'wrong_bank', note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
    }
  }

  Future<void> _confirmReject(String donationId) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Reject Donation', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The donor will be notified this wasn\'t approved. A short reason helps them understand why.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 10),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Reason (optional)'), maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _setStatus(donationId, 'rejected', note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: _future,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No donations for this church yet.',
      builder: (context, donations) => Column(
        children: donations.map((d) {
          final status = d['status'] as String? ?? 'awaiting_payment';
          final proofUrl = d['proofOfPaymentUrl'] as String?;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text('${d['associationName'] ?? ''} — R${(d['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                  Pill(status.replaceAll('_', ' '), tone: status == 'approved' ? 'sage' : (status == 'wrong_bank' ? 'outline' : 'outline')),
                ]),
                Text('Donor: ${d['donorName'] ?? ''} · ${d['donorContact'] ?? ''}', style: const TextStyle(fontSize: 12)),
                if (proofUrl != null) ...[
                  const SizedBox(height: 8),
                  if (d['proofOfPaymentType'] == 'pdf')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                      onPressed: () => launchUrl(Uri.parse(proofUrl), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('View Proof (PDF)', style: TextStyle(fontSize: 12)),
                    )
                  else
                    GestureDetector(
                      onTap: () => showDialog(context: context, builder: (_) => Dialog(child: Image.network(proofUrl))),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(proofUrl, height: 100, width: 100, fit: BoxFit.cover),
                      ),
                    ),
                ],
                if (status == 'proof_submitted') ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.sage),
                      onPressed: () => _setStatus(d['id'], 'approved'),
                      child: const Text('Approve (Thank Donor)', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
                      onPressed: () => _confirmWrongBank(d['id']),
                      child: const Text('Wrong Bank', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                      onPressed: () => _confirmReject(d['id']),
                      child: const Text('Reject', style: TextStyle(fontSize: 12)),
                    ),
                  ]),
                ] else if (status == 'awaiting_payment')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Waiting for donor to upload proof of payment.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
                  )
                else if (d['adminNote'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Note: ${d['adminNote']}', style: const TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CatechistApplicationsAdminSection extends StatefulWidget {
  final String parishId;
  const _CatechistApplicationsAdminSection({required this.parishId});

  @override
  State<_CatechistApplicationsAdminSection> createState() => _CatechistApplicationsAdminSectionState();
}

class _CatechistApplicationsAdminSectionState extends State<_CatechistApplicationsAdminSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getCatechistApplicationsForParish(widget.parishId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getCatechistApplicationsForParish(widget.parishId); });

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Map<String, dynamic>>>(
      future: _future,
      isEmpty: (l) => l.where((a) => a['status'] == 'pending').isEmpty,
      emptyMessage: 'No pending catechist applications for this parish.',
      builder: (context, apps) {
        final pending = apps.where((a) => a['status'] == 'pending').toList();
        return Column(
          children: pending.map((a) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a['applicantName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(a['applicantContact'] ?? '', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.sage),
                    onPressed: () async {
                      await FirestoreService().updateCatechistApplicationStatus(a['id'], 'approved');
                      _refresh();
                    },
                    child: const Text('Approve', style: TextStyle(fontSize: 12)),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                    onPressed: () async {
                      await FirestoreService().updateCatechistApplicationStatus(a['id'], 'rejected');
                      _refresh();
                    },
                    child: const Text('Reject', style: TextStyle(fontSize: 12)),
                  ),
                ]),
              ],
            ),
          )).toList(),
        );
      },
    );
  }
}

class _ManageQuizDialog extends StatefulWidget {
  final String parishId;
  final String churchId;
  final String courseId;
  final String lessonId;
  final String lessonTitle;
  const _ManageQuizDialog({
    required this.parishId, required this.churchId, required this.courseId,
    required this.lessonId, required this.lessonTitle,
  });

  @override
  State<_ManageQuizDialog> createState() => _ManageQuizDialogState();
}

class _ManageQuizDialogState extends State<_ManageQuizDialog> {
  List<Map<String, dynamic>> _questions = [];
  final Map<String, dynamic> _answers = {};
  final _passingScoreCtrl = TextEditingController(text: '70');
  bool _randomizeOrder = false;
  final _poolSizeCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  int _questionCounter = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final quiz = await FirestoreService().getPublicQuiz(widget.parishId, widget.churchId, widget.courseId, widget.lessonId);
    if (quiz != null) {
      _questions = (quiz['questions'] as List).cast<Map<String, dynamic>>();
      _passingScoreCtrl.text = (quiz['passingScorePercent'] ?? 70).toString();
      _randomizeOrder = quiz['randomizeOrder'] == true;
      if (quiz['questionPoolSize'] != null) _poolSizeCtrl.text = quiz['questionPoolSize'].toString();
      _questionCounter = _questions.length;
      // Answer key isn't re-fetchable here by design (admin panel uses
      // the same isParishAdmin trust tier that CAN read it, but there's
      // no read method wired for it since nothing in the app needs to
      // display it back - editing a question re-specifies its answer
      // fresh rather than needing to show what was previously correct).
    }
    if (mounted) setState(() { _loading = false; });
  }

  @override
  void dispose() {
    _passingScoreCtrl.dispose();
    _poolSizeCtrl.dispose();
    super.dispose();
  }

  Future<void> _addQuestion() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AddQuestionDialog(existingQuestions: _questions),
    );
    if (result != null) {
      setState(() {
        _questionCounter++;
        final id = 'q$_questionCounter';
        _questions.add({
          'id': id, 'type': result['type'], 'text': result['text'],
          if (result['type'] == 'multipleChoice') 'options': result['options'],
          if (result['type'] == 'dragAndDrop') 'items': result['items'],
          if (result['nextIfCorrect'] != null) 'nextIfCorrect': result['nextIfCorrect'],
          if (result['nextIfWrong'] != null) 'nextIfWrong': result['nextIfWrong'],
        });
        _answers[id] = result['type'] == 'multipleChoice'
            ? {'correctIndex': result['correctIndex']}
            : {'correctOrder': List.generate((result['items'] as List).length, (i) => i)};
      });
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; });
    try {
      await FirestoreService().saveQuizForLesson(
        parishId: widget.parishId, churchId: widget.churchId, courseId: widget.courseId, lessonId: widget.lessonId,
        questions: _questions, answers: _answers,
        randomizeOrder: _randomizeOrder,
        questionPoolSize: int.tryParse(_poolSizeCtrl.text.trim()),
        passingScorePercent: double.tryParse(_passingScoreCtrl.text.trim()) ?? 70,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save quiz: $e')));
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  Future<void> _deleteQuiz() async {
    await FirestoreService().deleteQuizForLesson(widget.parishId, widget.churchId, widget.courseId, widget.lessonId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text('Quiz — ${widget.lessonTitle}', style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Passing this quiz marks the lesson complete for the student.', style: TextStyle(fontSize: 11, color: Colors.black45)),
                    const SizedBox(height: 10),
                    ..._questions.asMap().entries.map((entry) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(entry.value['type'] == 'dragAndDrop' ? Icons.swap_vert : Icons.check_box_outlined, size: 18),
                          title: Text(entry.value['text'] ?? '', style: const TextStyle(fontSize: 13)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.redAccent),
                            onPressed: () => setState(() {
                              _answers.remove(entry.value['id']);
                              _questions.removeAt(entry.key);
                            }),
                          ),
                        )),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                      onPressed: _addQuestion,
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text('Add Question', style: TextStyle(fontSize: 12)),
                    ),
                    const Divider(height: 24),
                    TextField(controller: _passingScoreCtrl, decoration: const InputDecoration(labelText: 'Passing score %'), keyboardType: TextInputType.number),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.brass,
                      title: const Text('Randomize question order', style: TextStyle(fontSize: 13)),
                      value: _randomizeOrder,
                      onChanged: (v) => setState(() => _randomizeOrder = v),
                    ),
                    TextField(controller: _poolSizeCtrl, decoration: const InputDecoration(labelText: 'Show only N random questions (optional)'), keyboardType: TextInputType.number),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _deleteQuiz, child: const Text('Delete Quiz', style: TextStyle(color: Colors.redAccent))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: (_questions.isEmpty || _saving) ? null : _save,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
        ),
      ],
    );
  }
}

class _AddQuestionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> existingQuestions;
  const _AddQuestionDialog({required this.existingQuestions});

  @override
  State<_AddQuestionDialog> createState() => _AddQuestionDialogState();
}

class _AddQuestionDialogState extends State<_AddQuestionDialog> {
  String _type = 'multipleChoice';
  final _textCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = List.generate(4, (_) => TextEditingController());
  int _correctIndex = 0;
  final List<TextEditingController> _itemCtrls = [TextEditingController(), TextEditingController(), TextEditingController()];
  String? _nextIfCorrect;
  String? _nextIfWrong;

  @override
  void dispose() {
    _textCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    for (final c in _itemCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('Add Question', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<String>(
                value: _type, isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'multipleChoice', child: Text('Multiple Choice')),
                  DropdownMenuItem(value: 'dragAndDrop', child: Text('Drag & Drop (put in order)')),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
              TextField(controller: _textCtrl, decoration: const InputDecoration(labelText: 'Question')),
              const SizedBox(height: 10),
              if (_type == 'multipleChoice') ...[
                const Text('Options - select the correct one', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                RadioGroup<int>(
                  groupValue: _correctIndex,
                  onChanged: (v) => setState(() => _correctIndex = v!),
                  child: Column(
                    children: List.generate(4, (i) => Row(
                          children: [
                            Radio<int>(value: i, activeColor: AppColors.sage),
                            Expanded(child: TextField(controller: _optionCtrls[i], decoration: InputDecoration(labelText: 'Option ${i + 1}'))),
                          ],
                        )),
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.existingQuestions.isNotEmpty) ...[
                  const Text('Branching (optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  DropdownButton<String?>(
                    value: _nextIfCorrect, isExpanded: true,
                    hint: const Text('If correct, go to... (default: next)', style: TextStyle(fontSize: 12)),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Next in order')),
                      ...widget.existingQuestions.map((q) => DropdownMenuItem(value: q['id'] as String, child: Text(q['text'] ?? '', overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() => _nextIfCorrect = v),
                  ),
                  DropdownButton<String?>(
                    value: _nextIfWrong, isExpanded: true,
                    hint: const Text('If wrong, go to... (default: next)', style: TextStyle(fontSize: 12)),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Next in order')),
                      ...widget.existingQuestions.map((q) => DropdownMenuItem(value: q['id'] as String, child: Text(q['text'] ?? '', overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() => _nextIfWrong = v),
                  ),
                ],
              ],
              if (_type == 'dragAndDrop') ...[
                const Text('Items, in the CORRECT order (students see them shuffled)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ..._itemCtrls.asMap().entries.map((e) => TextField(controller: e.value, decoration: InputDecoration(labelText: 'Item ${e.key + 1}'))),
                TextButton.icon(
                  onPressed: () => setState(() => _itemCtrls.add(TextEditingController())),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add item', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: () {
            if (_textCtrl.text.trim().isEmpty) return;
            if (_type == 'multipleChoice') {
              Navigator.pop(context, {
                'type': 'multipleChoice', 'text': _textCtrl.text.trim(),
                'options': _optionCtrls.map((c) => c.text.trim()).toList(),
                'correctIndex': _correctIndex,
                'nextIfCorrect': _nextIfCorrect, 'nextIfWrong': _nextIfWrong,
              });
            } else {
              final items = _itemCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
              if (items.length < 2) return;
              Navigator.pop(context, {'type': 'dragAndDrop', 'text': _textCtrl.text.trim(), 'items': items});
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Sets readings scoped to one specific event (a wedding, a funeral) -
/// separate from the ordinary reading for that date, which stays
/// unaffected. Pre-fills from any existing override so this doubles as
/// edit, not just create.
class _EventReadingsDialog extends StatefulWidget {
  final DateTime date;
  final String eventId;
  final String eventTitle;
  const _EventReadingsDialog({required this.date, required this.eventId, required this.eventTitle});

  @override
  State<_EventReadingsDialog> createState() => _EventReadingsDialogState();
}

class _EventReadingsDialogState extends State<_EventReadingsDialog> {
  final _titleCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _psalmCtrl = TextEditingController();
  final _secondCtrl = TextEditingController();
  final _gospelCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _hasExisting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final existing = await FirestoreService().getLiturgicalDayForContext(widget.date, eventId: widget.eventId);
    if (!mounted) return;
    if (existing != null) {
      final en = existing.readingsByLanguage['en'];
      setState(() {
        _hasExisting = true;
        _titleCtrl.text = existing.liturgicalTitle;
        _firstCtrl.text = en?.firstReading ?? '';
        _psalmCtrl.text = en?.psalm ?? '';
        _secondCtrl.text = en?.secondReading ?? '';
        _gospelCtrl.text = en?.gospel ?? '';
      });
    }
    setState(() { _loading = false; });
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty || _firstCtrl.text.trim().isEmpty || _gospelCtrl.text.trim().isEmpty) return;
    setState(() { _saving = true; });
    try {
      await FirestoreService().setScopedReading(
        date: widget.date, eventId: widget.eventId,
        liturgicalTitle: _titleCtrl.text.trim(),
        firstReading: _firstCtrl.text.trim(),
        psalm: _psalmCtrl.text.trim(),
        secondReading: _secondCtrl.text.trim(),
        gospel: _gospelCtrl.text.trim(),
        source: 'manual - event-specific',
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  Future<void> _remove() async {
    await FirestoreService().deleteScopedReading(widget.date, eventId: widget.eventId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text('Readings — ${widget.eventTitle}', style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasExisting
                          ? 'This event already has its own readings, separate from the ordinary day.'
                          : 'Not set yet - this event currently shows the ordinary daily readings. Fill this in to override them (e.g. a couple\'s chosen wedding readings).',
                      style: const TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Occasion title', hintText: 'e.g. Wedding of John & Mary')),
                    TextField(controller: _firstCtrl, decoration: const InputDecoration(labelText: 'First Reading')),
                    TextField(controller: _psalmCtrl, decoration: const InputDecoration(labelText: 'Responsorial Psalm')),
                    TextField(controller: _secondCtrl, decoration: const InputDecoration(labelText: 'Second Reading')),
                    TextField(controller: _gospelCtrl, decoration: const InputDecoration(labelText: 'Gospel')),
                  ],
                ),
              ),
      ),
      actions: [
        if (_hasExisting)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: _remove,
            child: const Text('Remove Override'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}