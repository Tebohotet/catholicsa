import 'package:flutter/material.dart';
import '../models/church.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

/// The "Add Church" / "Edit Church" dialog - originally lived only inside
/// AdminPanelScreen, pulled out here so it can ALSO open directly from
/// ParishDetailScreen (add) and ChurchDetailScreen (edit). That's the
/// whole point: an admin looking at their own parish or church page
/// shouldn't have to leave it and go hunting for the separate Admin
/// Panel just to fix a name or address - the same idea as the Readings
/// screen's inline edit button.
///
/// [onSaved] is called with the affected church's id once the write
/// succeeds, so each caller can refresh whatever it's showing (a
/// churches list, or the single church page currently open) however
/// makes sense for it - this file doesn't assume which.
Future<void> showChurchFormDialog(
  BuildContext context, {
  required String parishId,
  Church? existing,
  required void Function(String churchId) onSaved,
}) async {
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
                child: Text('GPS location, accessibility details, and amenities can be added afterward from the Admin Panel - this gets the church listed so you can start adding Mass times right away.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
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
                  parishId: parishId, churchId: existing.id,
                  name: nameCtrl.text.trim(), address: addressCtrl.text.trim(),
                  contactPhone: phoneCtrl.text.trim(), contactEmail: emailCtrl.text.trim(),
                  buildingType: buildingType, seatingCapacity: capacity,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                onSaved(existing.id);
              } else {
                final newId = await FirestoreService().addChurch(
                  parishId: parishId,
                  name: nameCtrl.text.trim(), address: addressCtrl.text.trim(),
                  contactPhone: phoneCtrl.text.trim(), contactEmail: emailCtrl.text.trim(),
                  buildingType: buildingType, seatingCapacity: capacity,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                onSaved(newId);
              }
            },
            child: Text(isEdit ? 'Save' : 'Add Church'),
          ),
        ],
      ),
    ),
  );
}

/// Same reasoning as showChurchFormDialog above - deliberately minimal,
/// for a school hall or community hall used for Mass occasionally,
/// sometimes only once. Name, address, capacity, and basic accessibility
/// notes are the only real questions; everything heavier (building
/// type, verification, church history) genuinely doesn't apply here
/// and isn't asked.
Future<void> showVenueFormDialog(
  BuildContext context, {
  required String parishId,
  required void Function(String churchId) onSaved,
}) async {
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
              parishId: parishId,
              name: nameCtrl.text.trim(), address: addressCtrl.text.trim(),
              seatingCapacity: int.tryParse(capacityCtrl.text.trim()),
              venueType: 'venue',
            );
            if (accessibilityNotesCtrl.text.trim().isNotEmpty) {
              await FirestoreService().updateChurchAccessibility(parishId, newId, {
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
            onSaved(newId);
          },
          child: const Text('Add Venue'),
        ),
      ],
    ),
  );
}
