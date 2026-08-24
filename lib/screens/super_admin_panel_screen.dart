import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle, FilteringTextInputFormatter;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../services/audit_log_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import '../widgets/admin_crud_section.dart';
import '../services/auth_service.dart';


class SuperAdminPanelScreen extends StatefulWidget {
  const SuperAdminPanelScreen({super.key});

  @override
  State<SuperAdminPanelScreen> createState() => _SuperAdminPanelScreenState();
}

class _SuperAdminPanelScreenState extends State<SuperAdminPanelScreen> {
  // Forcing a fresh Key on these two widgets after any province CRUD
  // makes Flutter dispose their old state and re-run initState, which
  // is what actually re-fetches the province list - the exact mechanism
  // already used elsewhere in this app (_servicesKey) for the same
  // "something changed elsewhere, this needs to know" problem.
  Key _createParishKey = UniqueKey();
  Key _dioceseManagementKey = UniqueKey();
  Key _provinceManagementKey = UniqueKey();

  void _refreshProvinceDependents() {
    setState(() {
      _createParishKey = UniqueKey();
      _dioceseManagementKey = UniqueKey();
    });
  }

  // A country changing means province creation's own country dropdown
  // needs to know - the same "parent tells the child" principle, one
  // level further up the hierarchy.
  void _refreshCountryDependents() {
    setState(() { _provinceManagementKey = UniqueKey(); });
  }
  final _emailCtrl = TextEditingController();
  Map<String, dynamic>? _foundUser;
  bool _searching = false;
  bool _searched = false;

  // Starts with just the demo parish as a guaranteed fallback so the
  // dropdown is never empty before the real fetch completes - the actual
  // list is loaded dynamically in initState, replacing what used to be a
  // hardcoded map that would have silently hidden any newly-created
  // parish from ever being assignable an admin.
  Map<String, String> _parishOptions = {'demo-parish': '⚡ Demo Parish (training)'};
  String _selectedParishId = 'demo-parish';
  String _selectedRole = 'priest';

  final _feePercentCtrl = TextEditingController();
  bool _loadingFee = true;
  bool _savingFee = false;

  @override
  void initState() {
    super.initState();
    _loadFee();
    _loadParishOptions();
  }

  Future<void> _loadParishOptions() async {
    final parishes = await FirestoreService().getAllParishesFlat();
    if (!mounted) return;
    setState(() {
      _parishOptions = {for (final p in parishes) p['id']!: p['name']!};
      if (_parishOptions.isEmpty) _parishOptions = {'demo-parish': '⚡ Demo Parish (training)'};
      if (!_parishOptions.containsKey(_selectedParishId)) {
        _selectedParishId = _parishOptions.keys.first;
      }
    });
  }

  Future<void> _showEditParishDialog(BuildContext context) async {
    final parish = await FirestoreService().getParish(_selectedParishId);
    if (!context.mounted) return;
    final nameCtrl = TextEditingController(text: parish.name);
    final phoneCtrl = TextEditingController(text: parish.contactPhone);
    final emailCtrl = TextEditingController(text: parish.contactEmail);

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Edit Parish', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Parish name')),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Contact phone')),
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Contact email')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await FirestoreService().updateParish(
                parishId: _selectedParishId,
                name: nameCtrl.text.trim(), contactPhone: phoneCtrl.text.trim(), contactEmail: emailCtrl.text.trim(),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              await _loadParishOptions();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteParish(BuildContext context) async {
    final parishName = _parishOptions[_selectedParishId] ?? _selectedParishId;
    if (_selectedParishId == 'demo-parish') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The demo parish can\'t be deleted - every new admin trains here.')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Delete Parish?', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: Text(
          '"$parishName" and its admin assignments will be permanently removed. Every church, course, product, and comment nested under it becomes orphaned data - not automatically cleaned up. This can\'t be undone.',
          style: const TextStyle(fontSize: 13),
        ),
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
      await FirestoreService().deleteParish(_selectedParishId);
      await _loadParishOptions();
    }
  }

  Future<void> _loadFee() async {
    final fee = await FirestoreService().getPlatformFeePercent();
    _feePercentCtrl.text = fee.toString();
    if (mounted) setState(() { _loadingFee = false; });
  }

  Future<void> _saveFee() async {
    final value = double.tryParse(_feePercentCtrl.text.trim());
    if (value == null || value < 0 || value > 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a percentage between 0 and 100.')));
      return;
    }
    setState(() { _savingFee = true; });
    try {
      await FirestoreService().setPlatformFeePercent(value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Platform fee saved.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() { _savingFee = false; });
    }
  }

  Future<void> _search() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() { _searching = true; _searched = true; });
    final user = await FirestoreService().findUserByEmail(email);
    if (mounted) setState(() { _foundUser = user; _searching = false; });
  }

  Future<void> _grant() async {
    if (_foundUser == null) return;
    await FirestoreService().assignParishAdmin(
      parishId: _selectedParishId, uid: _foundUser!['uid'],
      role: _selectedRole, displayName: _foundUser!['displayName'] ?? '', email: _foundUser!['email'] ?? '',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Granted $_selectedRole on ${_parishOptions[_selectedParishId]}')));
      setState(() {});
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _feePercentCtrl.dispose();
    super.dispose();
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
                  const Text('Super Admin — Roles', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'The person must have signed in with Google at least once already - that\'s what creates their account record. '
                      'Search by the exact email they signed in with.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(labelText: 'Email address', hintText: 'someone@gmail.com'),
                            onSubmitted: (_) => _search(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                          onPressed: _searching ? null : _search,
                          child: _searching
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Find'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_searched && !_searching)
                      _foundUser == null
                          ? const Text('No account found with that email. They need to sign in at least once first.', style: TextStyle(color: Colors.redAccent, fontSize: 13))
                          : Container(
                              padding: const EdgeInsets.all(14),
                              color: AppColors.paperDark,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_foundUser!['displayName'] ?? '(no name)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text(_foundUser!['email'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                  const SizedBox(height: 16),
                                  DropdownButton<String>(
                                    value: _selectedParishId, isExpanded: true,
                                    items: _parishOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                                    onChanged: (v) => setState(() => _selectedParishId = v!),
                                  ),
                                  DropdownButton<String>(
                                    value: _selectedRole, isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(value: 'priest', child: Text('Priest (full admin, incl. finances & approvals)')),
                                      DropdownMenuItem(value: 'secretary', child: Text('Secretary (edit content, no finance/approval access)')),
                                    ],
                                    onChanged: (v) => setState(() => _selectedRole = v!),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(backgroundColor: AppColors.sage),
                                    onPressed: _grant,
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('Grant Role'),
                                  ),
                                  FutureBuilder<Map<String, dynamic>?>(
                                    future: FirestoreService().getUserDoc(AuthService().currentUser?.uid ?? ''),
                                    builder: (context, viewerSnap) {
                                      final viewerIsDeveloper = viewerSnap.data?['isDeveloper'] == true;
                                      final viewerIsSuperAdmin = viewerSnap.data?['isSuperAdmin'] == true;
                                      if (!viewerIsDeveloper && !viewerIsSuperAdmin) return const SizedBox.shrink();
                                      final targetIsSuperAdmin = _foundUser!['isSuperAdmin'] == true;
                                      final targetIsDeveloper = _foundUser!['isDeveloper'] == true;
                                      final targetIsDesigner = _foundUser!['isDesigner'] == true;
                                      final targetIsAuditor = _foundUser!['isAuditor'] == true;
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (viewerIsDeveloper) ...[
                                              const Divider(),
                                              const Text('Platform Role (Developer only)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone)),
                                              SwitchListTile(
                                                contentPadding: EdgeInsets.zero,
                                                activeThumbColor: AppColors.brass,
                                                title: const Text('Super Admin', style: TextStyle(fontSize: 13)),
                                                value: targetIsSuperAdmin,
                                                onChanged: (v) async {
                                                  await FirestoreService().setUserSuperAdminStatus(_foundUser!['uid'], v);
                                                  await AuditLogService().log(
                                                    action: v ? 'user.grantSuperAdmin' : 'user.revokeSuperAdmin',
                                                    targetId: _foundUser!['uid'], detail: _foundUser!['email'],
                                                  );
                                                  setState(() {});
                                                },
                                              ),
                                              SwitchListTile(
                                                contentPadding: EdgeInsets.zero,
                                                activeThumbColor: AppColors.brass,
                                                title: const Text('Developer', style: TextStyle(fontSize: 13)),
                                                value: targetIsDeveloper,
                                                onChanged: (v) async {
                                                  await FirestoreService().setUserDeveloperStatus(_foundUser!['uid'], v);
                                                  await AuditLogService().log(
                                                    action: v ? 'user.grantDeveloper' : 'user.revokeDeveloper',
                                                    targetId: _foundUser!['uid'], detail: _foundUser!['email'],
                                                  );
                                                  setState(() {});
                                                },
                                              ),
                                            ],
                                            const Divider(),
                                            const Text('Content Role (Super Admin or Developer)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone)),
                                            const Text('Lower-stakes than Platform Role - only affects visibility into draft/test content, never platform control.', style: TextStyle(fontSize: 10, color: Colors.black45)),
                                            SwitchListTile(
                                              contentPadding: EdgeInsets.zero,
                                              activeThumbColor: AppColors.sage,
                                              title: const Text('Designer', style: TextStyle(fontSize: 13)),
                                              subtitle: const Text('Sees draft/unpublished content for visual work', style: TextStyle(fontSize: 10)),
                                              value: targetIsDesigner,
                                              onChanged: (v) async {
                                                await FirestoreService().setUserDesignerStatus(_foundUser!['uid'], v);
                                                await AuditLogService().log(
                                                  action: v ? 'user.grantDesigner' : 'user.revokeDesigner',
                                                  targetId: _foundUser!['uid'], detail: _foundUser!['email'],
                                                );
                                                setState(() {});
                                              },
                                            ),
                                            SwitchListTile(
                                              contentPadding: EdgeInsets.zero,
                                              activeThumbColor: AppColors.sage,
                                              title: const Text('Auditor', style: TextStyle(fontSize: 13)),
                                              subtitle: const Text('Read-only visibility into draft/test content for review', style: TextStyle(fontSize: 10)),
                                              value: targetIsAuditor,
                                              onChanged: (v) async {
                                                await FirestoreService().setUserAuditorStatus(_foundUser!['uid'], v);
                                                await AuditLogService().log(
                                                  action: v ? 'user.grantAuditor' : 'user.revokeAuditor',
                                                  targetId: _foundUser!['uid'], detail: _foundUser!['email'],
                                                );
                                                setState(() {});
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'I', title: 'Current Admins'),
                    DropdownButton<String>(
                      value: _selectedParishId, isExpanded: true,
                      items: _parishOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setState(() => _selectedParishId = v!),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                        onPressed: () => _showEditParishDialog(context),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit This Parish'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                        onPressed: () => _confirmDeleteParish(context),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete This Parish'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    AsyncSection<List<Map<String, dynamic>>>(
                      key: ValueKey('admins-$_selectedParishId'),
                      future: FirestoreService().getParishAdmins(_selectedParishId),
                      isEmpty: (l) => l.isEmpty,
                      emptyMessage: 'No admins assigned to this parish yet.',
                      builder: (context, admins) => Column(
                        children: admins.map((a) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(a['displayName'] ?? a['email'] ?? ''),
                          subtitle: Text('${a['role']} · ${a['email'] ?? ''}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                            onPressed: () async {
                              await FirestoreService().removeParishAdmin(_selectedParishId, a['uid']);
                              setState(() {});
                            },
                          ),
                        )).toList(),
                      ),
                    ),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'II', title: 'Saints Database'),
                    const Text(
                      'Real date pickers, no free-typed dates - a feast date picked once fills both the lookup key and the written-out label automatically. Patron Of is a growing, shared tag list, not retyped each time. Birth date is separate from feast date specifically so "saints who share your birthday" can work.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    const SaintsManagementSection(),

                    const SizedBox(height: 24),
                    const Text('Store Item Groups (Bible, Rosary, Candle, etc.)', style: TextStyle(fontFamily: appSerif, fontSize: 15)),
                    const SizedBox(height: 8),
                    GenericAdminCrudSection(
                      spec: AdminCollectionSpec(
                        title: 'Group',
                        icon: Icons.category_outlined,
                        fields: const [
                          AdminFieldSpec(key: 'name', label: 'Name', required: true, hint: 'e.g. Rosary'),
                        ],
                        titleBuilder: (g) => g['name'] ?? '',
                        subtitleBuilder: (g) => '',
                        fetchAll: () => FirestoreService().getProductGroups(),
                        onAdd: (data) => FirestoreService().addProductGroup(data['name']),
                        onEdit: (id, data) => FirestoreService().updateProductGroup(id, data['name']),
                        onDelete: (id) => FirestoreService().deleteProductGroup(id),
                        idOf: (g) => g['id'],
                      ),
                    ),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'III', title: 'Marketplace Fee'),
                    const Text(
                      'Applies only when a parish has no gateway of its own configured (payment lands with the platform). '
                      'Once a parish/seller has their own PayFast/PayStack/PayPal, use their gateway\'s own commission feature instead.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    if (_loadingFee)
                      const Center(child: CircularProgressIndicator())
                    else
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _feePercentCtrl,
                              decoration: const InputDecoration(labelText: 'Fee percentage', suffixText: '%'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                            onPressed: _savingFee ? null : _saveFee,
                            child: _savingFee
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Save'),
                          ),
                        ],
                      ),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'IV', title: 'Dev Flags'),
                    const Text(
                      'Off = hidden from everyone, even you. Preview = only super admins can see it, so it can be tested before anyone else does. '
                      'Live = visible to everyone.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    const DevFlagsSection(),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'V', title: 'Custom Pages'),
                    const Text(
                      'Server-driven pages assembled from existing blocks - no app update needed to publish, edit, or unpublish one.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    const CustomPagesSection(),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'VI', title: 'Design Tokens'),
                    const Text(
                      'A bounded set of choices, not free-form styling - applies to the nav bar position and the default theme colour/corner radius. '
                      'Existing screens with their own explicit colours aren\'t retroactively re-themed by this.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    const DesignTokensSection(),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'VII', title: 'App Branding'),
                    const Text('Used throughout the app - currently applied to the app title. Takes effect next restart.', style: TextStyle(fontSize: 11, color: Colors.black45)),
                    const SizedBox(height: 10),
                    const BrandingSection(),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'VIII', title: 'National Catechist Applications'),
                    const Text('Platform-wide verification - a bigger claim than one priest vouching for someone they know.', style: TextStyle(fontSize: 11, color: Colors.black45)),
                    const SizedBox(height: 10),
                    const _NationalCatechistSection(),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'IX', title: 'Liturgical Readings'),
                    const Text(
                      'Real date picker, no free-typed "YYYY-MM-DD" strings. Year Cycle exists specifically so content transcribed from an older physical missal can\'t silently end up attached to the wrong lectionary year.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    const LiturgicalReadingsSection(),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'X', title: 'Create Parish'),
                    const Text(
                      'A brand new administrative unit - not a second church within an existing parish (any parish admin can already add one of those). Once created, assign an admin below and they can add churches, Mass times, and everything else from their own Admin Panel.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    _CreateParishSection(key: _createParishKey, onCreated: _loadParishOptions),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'XI', title: 'Dioceses / Archdioceses'),
                    const Text(
                      'An archdiocese is a diocese elevated in rank - led by an Archbishop rather than a Bishop, and typically the metropolitan see for nearby suffragan dioceses. That relationship is informational (an archbishop doesn\'t govern the other dioceses), not a permission structure.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    _DioceseManagementSection(key: _dioceseManagementKey),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'XII', title: 'Countries'),
                    const Text(
                      'Genuinely new - this app has always been scoped to South Africa with no country level at all. Added above provinces without restructuring the existing browse flow to require it, so this is real, working structure ready for whenever it\'s needed, not yet wired into Browse/Search.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    GenericAdminCrudSection(
                      spec: AdminCollectionSpec(
                        title: 'Country',
                        icon: Icons.flag_outlined,
                        fields: const [
                          AdminFieldSpec(key: 'name', label: 'Name', required: true, hint: 'e.g. South Africa'),
                        ],
                        titleBuilder: (c) => c['name'] ?? '',
                        subtitleBuilder: (c) => '',
                        fetchAll: () => FirestoreService().getCountries(),
                        onAdd: (data) async {
                          await FirestoreService().addCountry(data['name']);
                          _refreshCountryDependents();
                        },
                        onEdit: (id, data) async {
                          await FirestoreService().updateCountry(id, data['name']);
                          _refreshCountryDependents();
                        },
                        onDelete: (id) async {
                          await FirestoreService().deleteCountry(id);
                          _refreshCountryDependents();
                        },
                        idOf: (c) => c['id'],
                      ),
                    ),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'XIII', title: 'Provinces'),
                    const Text(
                      'The top of the whole hierarchy - every diocese, parish, and church sits under one of these. Currently 9, but the structure isn\'t hardcoded to that number anywhere - add, rename, or remove as the real ecclesiastical structure changes. A province belongs to a country, same as a diocese belongs to a province - pick one below.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    _ProvinceManagementSection(key: _provinceManagementKey, onProvinceChanged: _refreshProvinceDependents),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'XIV', title: 'Feast Calendar Sync'),
                    const Text(
                      'Pulls a year of real feast data - name, rank, and actual reading citations - from the LitCal API. Self-diagnosing: anything that doesn\'t match what this sync expects gets reported below rather than silently written. Never overwrites a liturgicalReadings entry that already exists.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    const FeastCalendarSyncSection(),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'XV', title: 'Bible'),
                    const Text(
                      'Genuinely multi-translation - add a translation once (name it, mark whether it\'s public domain), then paste chapter text under it. A licensed translation later is just a new translation here, never a rebuild.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    const BibleManagementSection(),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'XVI', title: 'Bible Cross-References'),
                    const Text(
                      'Genuinely a content problem, not a code one - no reference pairs exist yet. This links two passages (e.g. an Old Testament prophecy and its New Testament fulfilment); it doesn\'t suggest or generate them.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    const CrossReferencesSection(),

                    const SizedBox(height: 32),
                    const SectionLabel(numeral: 'XVII', title: 'Audit Log'),
                    const Text(
                      'Write-once - nothing here can be edited or deleted, by anyone, including Developer. Currently covers role grants/revokes (the highest-stakes actions) - not yet every admin action across the app.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    const SizedBox(height: 10),
                    const _AuditLogSection(),
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

class DevFlagsSection extends StatefulWidget {
  const DevFlagsSection();

  @override
  State<DevFlagsSection> createState() => _DevFlagsSectionState();
}

class _DevFlagsSectionState extends State<DevFlagsSection> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getDevFlags();
  }

  void _refresh() => setState(() { _future = FirestoreService().getDevFlags(); });

  Future<void> _addFlag() async {
    final keyCtrl = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('New Dev Flag', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: 'Flag key', hintText: 'e.g. shopOnlineCheckout')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () => Navigator.pop(dialogContext, keyCtrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (key != null && key.isNotEmpty) {
      await FirestoreService().setDevFlag(key, 'off');
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final flags = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (flags.isEmpty)
              const Text('No dev flags registered yet.', style: TextStyle(fontSize: 12, color: Colors.black45)),
            ...flags.entries.map((entry) {
              final key = entry.key;
              final state = entry.value as String? ?? 'off';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: AppColors.paperDark,
                child: Row(
                  children: [
                    Expanded(child: Text(key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    DropdownButton<String>(
                      value: state,
                      items: const [
                        DropdownMenuItem(value: 'off', child: Text('Off')),
                        DropdownMenuItem(value: 'preview', child: Text('Preview')),
                        DropdownMenuItem(value: 'live', child: Text('Live')),
                      ],
                      onChanged: (v) async {
                        await FirestoreService().setDevFlag(key, v!);
                        _refresh();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      onPressed: () async {
                        await FirestoreService().deleteDevFlag(key);
                        _refresh();
                      },
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
              onPressed: _addFlag,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Register New Flag'),
            ),
          ],
        );
      },
    );
  }
}

class CustomPagesSection extends StatefulWidget {
  const CustomPagesSection();

  @override
  State<CustomPagesSection> createState() => _CustomPagesSectionState();
}

class _CustomPagesSectionState extends State<CustomPagesSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getCustomPages();
  }

  void _refresh() => setState(() { _future = FirestoreService().getCustomPages(); });

  Future<void> _createPage() async {
    final titleCtrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('New Page', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Page title', hintText: 'e.g. My Notes')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () => Navigator.pop(dialogContext, titleCtrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      await FirestoreService().createCustomPage(title: title, icon: 'note_outlined');
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final pages = snap.data!;
            if (pages.isEmpty) return const Text('No custom pages yet.', style: TextStyle(fontSize: 12, color: Colors.black45));
            return Column(
              children: pages.map((p) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: AppColors.paperDark,
                child: Row(
                  children: [
                    Expanded(child: Text(p['title'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    Text('${((p['blocks'] as List?) ?? []).length} blocks', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    Switch(
                      value: p['visible'] == true,
                      activeThumbColor: AppColors.brass,
                      onChanged: (v) async {
                        await FirestoreService().setCustomPageVisible(p['id'], v);
                        _refresh();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () async {
                        await showDialog(context: context, builder: (_) => _EditBlocksDialog(page: p));
                        _refresh();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      onPressed: () async {
                        await FirestoreService().deleteCustomPage(p['id']);
                        _refresh();
                      },
                    ),
                  ],
                ),
              )).toList(),
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: _createPage,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Create Page'),
        ),
      ],
    );
  }
}

class _EditBlocksDialog extends StatefulWidget {
  final Map<String, dynamic> page;
  const _EditBlocksDialog({required this.page});

  @override
  State<_EditBlocksDialog> createState() => _EditBlocksDialogState();
}

class _EditBlocksDialogState extends State<_EditBlocksDialog> {
  late List<Map<String, dynamic>> _blocks;
  String _newType = 'textBlock';
  final _field1Ctrl = TextEditingController(); // text / title
  final _field2Ctrl = TextEditingController(); // body / url / height

  @override
  void initState() {
    super.initState();
    _blocks = ((widget.page['blocks'] as List?) ?? []).map((b) => (b as Map).cast<String, dynamic>()).toList();
  }

  @override
  void dispose() {
    _field1Ctrl.dispose();
    _field2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await FirestoreService().updateCustomPageBlocks(widget.page['id'], _blocks);
    if (mounted) Navigator.pop(context);
  }

  void _addBlock() {
    Map<String, dynamic> config;
    switch (_newType) {
      case 'textBlock':
        config = {'text': _field1Ctrl.text.trim(), 'heading': false};
        break;
      case 'shareButton':
        config = {'title': _field1Ctrl.text.trim(), 'body': _field2Ctrl.text.trim()};
        break;
      case 'spacer':
        config = {'height': double.tryParse(_field1Ctrl.text.trim()) ?? 16};
        break;
      default:
        config = {};
    }
    setState(() {
      _blocks.add({'type': _newType, 'config': config});
      _field1Ctrl.clear();
      _field2Ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text('Blocks — ${widget.page['title'] ?? ''}', style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._blocks.asMap().entries.map((entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(entry.value['type'] ?? '', style: const TextStyle(fontSize: 13)),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.redAccent),
                      onPressed: () => setState(() => _blocks.removeAt(entry.key)),
                    ),
                  )),
              const Divider(),
              DropdownButton<String>(
                value: _newType, isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'textBlock', child: Text('Text')),
                  DropdownMenuItem(value: 'notesList', child: Text('Notes List')),
                  DropdownMenuItem(value: 'shareButton', child: Text('Share Button')),
                  DropdownMenuItem(value: 'spacer', child: Text('Spacer')),
                ],
                onChanged: (v) => setState(() => _newType = v!),
              ),
              if (_newType == 'textBlock') TextField(controller: _field1Ctrl, decoration: const InputDecoration(labelText: 'Text')),
              if (_newType == 'shareButton') ...[
                TextField(controller: _field1Ctrl, decoration: const InputDecoration(labelText: 'Share title')),
                TextField(controller: _field2Ctrl, decoration: const InputDecoration(labelText: 'Share body (optional)')),
              ],
              if (_newType == 'spacer') TextField(controller: _field1Ctrl, decoration: const InputDecoration(labelText: 'Height'), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                onPressed: _addBlock,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Block', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.brass), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class DesignTokensSection extends StatefulWidget {
  const DesignTokensSection();

  @override
  State<DesignTokensSection> createState() => _DesignTokensSectionState();
}

class _DesignTokensSectionState extends State<DesignTokensSection> {
  bool _loading = true;
  bool _saving = false;
  String _navPosition = 'bottom';
  double _cornerRadius = 8;
  final _accentColorCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tokens = await FirestoreService().getDesignTokens();
    // Only 'bottom' is an offered option below (see build()) - hardcoded
    // rather than read from Firestore for now, so a stored 'top' from
    // before that option was removed can't crash the dropdown with a
    // value that has no matching item.
    _navPosition = 'bottom';
    _cornerRadius = (tokens['cornerRadius'] as num?)?.toDouble() ?? 8;
    _accentColorCtrl.text = tokens['accentColor'] ?? '#A9822F';
    if (mounted) setState(() { _loading = false; });
  }

  @override
  void dispose() {
    _accentColorCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; });
    try {
      await FirestoreService().setDesignTokens({
        'navPosition': _navPosition,
        'cornerRadius': _cornerRadius,
        'accentColor': _accentColorCtrl.text.trim().isEmpty ? '#A9822F' : _accentColorCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved — takes effect next app restart.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Navigation bar position', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        DropdownButton<String>(
          value: _navPosition, isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'bottom', child: Text('Bottom (default)')),
            // 'Top' is deliberately not offered here - it isn't actually
            // built yet. HomeScreen's navigation is hardcoded to the
            // bottom regardless of this setting, so offering a selectable
            // "Top" option that saves successfully and then does nothing
            // would be actively misleading, not just incomplete.
          ],
          onChanged: (v) => setState(() => _navPosition = v!),
        ),
        const Text(
          'Top-position navigation is a planned option, not yet built into the app itself.',
          style: TextStyle(fontSize: 10, color: Colors.black45, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 12),
        Text('Corner radius: ${_cornerRadius.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Slider(
          value: _cornerRadius, min: 0, max: 24, divisions: 24,
          activeColor: AppColors.brass,
          onChanged: (v) => setState(() => _cornerRadius = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _accentColorCtrl,
          decoration: const InputDecoration(labelText: 'Accent colour (hex)', hintText: '#A9822F'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ),
      ],
    );
  }
}

class BrandingSection extends StatefulWidget {
  const BrandingSection();

  @override
  State<BrandingSection> createState() => _BrandingSectionState();
}

class _BrandingSectionState extends State<BrandingSection> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await FirestoreService().getBranding();
    _nameCtrl.text = b['appName'] ?? 'CatholicSA';
    _descCtrl.text = b['description'] ?? '';
    if (mounted) setState(() { _loading = false; });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; });
    try {
      await FirestoreService().setBranding({'appName': _nameCtrl.text.trim(), 'description': _descCtrl.text.trim()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Branding saved.')));
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'App name')),
        const SizedBox(height: 10),
        TextField(controller: _descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
          ),
        ),
      ],
    );
  }
}

/// National-level catechist applications - only reachable by Super Admin
/// (Developer included), matching the escalation this whole feature was
/// designed to demonstrate.
class _NationalCatechistSection extends StatefulWidget {
  const _NationalCatechistSection();

  @override
  State<_NationalCatechistSection> createState() => _NationalCatechistSectionState();
}

class _NationalCatechistSectionState extends State<_NationalCatechistSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getNationalCatechistApplications();
  }

  void _refresh() => setState(() { _future = FirestoreService().getNationalCatechistApplications(); });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final apps = snap.data!.where((a) => a['status'] == 'pending').toList();
        if (apps.isEmpty) return const Text('No pending national applications.', style: TextStyle(fontSize: 12, color: Colors.black45));
        return Column(
          children: apps.map((a) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(a['applicantName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  Pill(a['type'] == 'trustedSeller' ? 'Trusted Seller' : 'Catechist', tone: 'outline'),
                ]),
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

class _CreateParishSection extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateParishSection({super.key, required this.onCreated});

  @override
  State<_CreateParishSection> createState() => _CreateParishSectionState();
}

class _CreateParishSectionState extends State<_CreateParishSection> {
  late Future<List<Map<String, dynamic>>> _provincesFuture;
  String? _selectedProvinceId;
  List<Map<String, dynamic>> _dioceses = [];
  String? _selectedDioceseId;
  bool _loadingDioceses = false;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _submitting = false;
  String? _lastCreatedName;

  @override
  void initState() {
    super.initState();
    _provincesFuture = FirestoreService().getProvinces();
  }

  Future<void> _onProvinceChanged(String? provinceId) async {
    setState(() { _selectedProvinceId = provinceId; _selectedDioceseId = null; _dioceses = []; _loadingDioceses = provinceId != null; });
    if (provinceId == null) return;
    final dioceses = await FirestoreService().getDioceses(provinceId);
    if (mounted) setState(() { _dioceses = dioceses; _loadingDioceses = false; });
  }

  Future<void> _submit() async {
    if (_selectedDioceseId == null || _nameCtrl.text.trim().isEmpty) return;
    setState(() { _submitting = true; });
    try {
      await FirestoreService().addParish(
        dioceseId: _selectedDioceseId!,
        name: _nameCtrl.text.trim(),
        contactPhone: _phoneCtrl.text.trim(),
        contactEmail: _emailCtrl.text.trim(),
      );
      setState(() {
        _lastCreatedName = _nameCtrl.text.trim();
        _nameCtrl.clear(); _phoneCtrl.clear(); _emailCtrl.clear();
        _selectedDioceseId = null;
      });
      widget.onCreated();
    } finally {
      if (mounted) setState(() { _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_lastCreatedName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              const Icon(Icons.check_circle, color: AppColors.sage, size: 16),
              const SizedBox(width: 6),
              Text('"$_lastCreatedName" created. Assign an admin above in Section I.', style: const TextStyle(fontSize: 12, color: AppColors.sage)),
            ]),
          ),
        Row(
          children: [
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _provincesFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                  final provinces = snap.data ?? [];
                  return DropdownButton<String>(
                    value: _selectedProvinceId,
                    isExpanded: true,
                    hint: const Text('Select a province', style: TextStyle(fontSize: 13)),
                    items: provinces.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text(p['name'] ?? ''))).toList(),
                    onChanged: _onProvinceChanged,
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Refresh - if you just added a province in Section XII, it won\'t appear here until refreshed',
              icon: const Icon(Icons.refresh, size: 20, color: AppColors.stone),
              onPressed: () => setState(() { _provincesFuture = FirestoreService().getProvinces(); }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectedProvinceId != null)
          _loadingDioceses
              ? const LinearProgressIndicator()
              : DropdownButton<String>(
                  value: _selectedDioceseId,
                  isExpanded: true,
                  hint: const Text('Select a diocese', style: TextStyle(fontSize: 13)),
                  items: _dioceses.map((d) => DropdownMenuItem(value: d['id'] as String, child: Text(d['name'] ?? ''))).toList(),
                  onChanged: (v) => setState(() => _selectedDioceseId = v),
                ),
        const SizedBox(height: 10),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Parish name', hintText: 'e.g. St Jude Parish'), onChanged: (_) => setState(() {})),
        TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Contact phone (optional)')),
        TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Contact email (optional)')),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: (_selectedDioceseId == null || _nameCtrl.text.trim().isEmpty || _submitting) ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Create Parish'),
        ),
      ],
    );
  }
}

/// Create + edit + leadership, combined - a diocese is a much smaller,
/// slower-changing part of the hierarchy than parishes/churches, so one
/// section covering all three doesn't need the same "select from a huge
/// list" treatment Section I needs for parishes.
class _DioceseManagementSection extends StatefulWidget {
  const _DioceseManagementSection({super.key});

  @override
  State<_DioceseManagementSection> createState() => _DioceseManagementSectionState();
}

class _DioceseManagementSectionState extends State<_DioceseManagementSection> {
  late Future<List<Map<String, dynamic>>> _provincesFuture;
  String? _selectedProvinceId;
  List<Map<String, dynamic>> _dioceses = [];
  String? _selectedDioceseId;
  bool _loadingDioceses = false;

  final _nameCtrl = TextEditingController();
  String _dioceseType = 'diocese';
  bool _submittingDiocese = false;
  bool _showAddDioceseForm = false;

  final _bishopNameCtrl = TextEditingController();
  final _bishopTitleCtrl = TextEditingController();
  final _cathedralCtrl = TextEditingController();
  final _leadershipPhoneCtrl = TextEditingController();
  bool _loadingLeadership = false;
  bool _savingLeadership = false;

  @override
  void initState() {
    super.initState();
    _provincesFuture = FirestoreService().getProvinces();
  }

  Future<void> _onProvinceChanged(String? provinceId) async {
    setState(() { _selectedProvinceId = provinceId; _selectedDioceseId = null; _dioceses = []; _loadingDioceses = provinceId != null; });
    if (provinceId == null) return;
    final dioceses = await FirestoreService().getDioceses(provinceId);
    if (mounted) setState(() { _dioceses = dioceses; _loadingDioceses = false; });
  }

  Future<void> _onDioceseChanged(String? dioceseId) async {
    setState(() { _selectedDioceseId = dioceseId; _loadingLeadership = dioceseId != null; _showAddDioceseForm = false; });
    if (dioceseId == null) return;
    final leadership = await FirestoreService().getDioceseLeadership(dioceseId);
    if (!mounted) return;
    setState(() {
      _bishopNameCtrl.text = leadership?['bishopName'] ?? '';
      _bishopTitleCtrl.text = leadership?['bishopTitle'] ?? '';
      _cathedralCtrl.text = leadership?['cathedralName'] ?? '';
      _leadershipPhoneCtrl.text = leadership?['phone'] ?? '';
      _loadingLeadership = false;
    });
  }

  Future<void> _createDiocese() async {
    if (_selectedProvinceId == null || _nameCtrl.text.trim().isEmpty) return;
    setState(() { _submittingDiocese = true; });
    try {
      final newId = await FirestoreService().addDiocese(
        provinceId: _selectedProvinceId!, name: _nameCtrl.text.trim(), dioceseType: _dioceseType,
      );
      _nameCtrl.clear();
      final dioceses = await FirestoreService().getDioceses(_selectedProvinceId!);
      if (mounted) setState(() { _dioceses = dioceses; _showAddDioceseForm = false; });
      await _onDioceseChanged(newId);
    } finally {
      if (mounted) setState(() { _submittingDiocese = false; });
    }
  }

  Future<void> _saveLeadership() async {
    if (_selectedDioceseId == null) return;
    setState(() { _savingLeadership = true; });
    try {
      await FirestoreService().updateDioceseLeadership(_selectedDioceseId!, {
        'bishopName': _bishopNameCtrl.text.trim().isEmpty ? null : _bishopNameCtrl.text.trim(),
        'bishopTitle': _bishopTitleCtrl.text.trim().isEmpty ? null : _bishopTitleCtrl.text.trim(),
        'cathedralName': _cathedralCtrl.text.trim().isEmpty ? null : _cathedralCtrl.text.trim(),
        'phone': _leadershipPhoneCtrl.text.trim().isEmpty ? null : _leadershipPhoneCtrl.text.trim(),
        'verified': true,
      });
      // Genuinely re-read what was actually saved, rather than just
      // trusting the local form fields already matched it - a real
      // confirmation, not an assumption.
      final confirmed = await FirestoreService().getDioceseLeadership(_selectedDioceseId!);
      if (!mounted) return;
      setState(() {
        _bishopNameCtrl.text = confirmed?['bishopName'] ?? '';
        _bishopTitleCtrl.text = confirmed?['bishopTitle'] ?? '';
        _cathedralCtrl.text = confirmed?['cathedralName'] ?? '';
        _leadershipPhoneCtrl.text = confirmed?['phone'] ?? '';
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leadership info saved and confirmed.')));
    } finally {
      if (mounted) setState(() { _savingLeadership = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _provincesFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                  final provinces = snap.data ?? [];
                  return DropdownButton<String>(
                    value: _selectedProvinceId, isExpanded: true,
                    hint: const Text('Select a province', style: TextStyle(fontSize: 13)),
                    items: provinces.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text(p['name'] ?? ''))).toList(),
                    onChanged: _onProvinceChanged,
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Refresh - if you just added a province in Section XII, it won\'t appear here until refreshed',
              icon: const Icon(Icons.refresh, size: 20, color: AppColors.stone),
              onPressed: () => setState(() { _provincesFuture = FirestoreService().getProvinces(); }),
            ),
          ],
        ),
        if (_selectedProvinceId != null) ...[
          const SizedBox(height: 8),
          _loadingDioceses
              ? const LinearProgressIndicator()
              : DropdownButton<String>(
                  value: _selectedDioceseId, isExpanded: true,
                  hint: const Text('Select a diocese to edit, or add a new one below', style: TextStyle(fontSize: 13)),
                  items: _dioceses.map((d) => DropdownMenuItem(
                    value: d['id'] as String,
                    child: Text('${d['name'] ?? ''}${d['dioceseType'] == 'archdiocese' ? ' (Archdiocese)' : ''}'),
                  )).toList(),
                  onChanged: _onDioceseChanged,
                ),
          const SizedBox(height: 10),
          if (!_showAddDioceseForm)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
              onPressed: () => setState(() => _showAddDioceseForm = true),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add New Diocese'),
            )
          else
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(child: Text('Add New Diocese', style: TextStyle(fontFamily: appSerif, fontSize: 14))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _showAddDioceseForm = false),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Diocese name', hintText: 'e.g. Diocese of Oudtshoorn')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        contentPadding: EdgeInsets.zero, dense: true,
                        title: const Text('Diocese', style: TextStyle(fontSize: 13)),
                        value: 'diocese', groupValue: _dioceseType,
                        onChanged: (v) => setState(() => _dioceseType = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        contentPadding: EdgeInsets.zero, dense: true,
                        title: const Text('Archdiocese', style: TextStyle(fontSize: 13)),
                        value: 'archdiocese', groupValue: _dioceseType,
                        onChanged: (v) => setState(() => _dioceseType = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                  onPressed: _submittingDiocese ? null : _createDiocese,
                  child: _submittingDiocese
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add Diocese'),
                ),
              ],
            ),
          ),
        ],
        if (_selectedDioceseId != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Leadership — ${_dioceses.firstWhere((d) => d['id'] == _selectedDioceseId, orElse: () => {'name': ''})['name']}',
                    style: const TextStyle(fontFamily: appSerif, fontSize: 14)),
                const SizedBox(height: 8),
                if (_loadingLeadership)
                  const LinearProgressIndicator()
                else ...[
                  TextField(controller: _bishopTitleCtrl, decoration: const InputDecoration(labelText: 'Title', hintText: 'Bishop or Archbishop')),
                  TextField(controller: _bishopNameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                  TextField(controller: _cathedralCtrl, decoration: const InputDecoration(labelText: 'Cathedral name (optional)')),
                  TextField(controller: _leadershipPhoneCtrl, decoration: const InputDecoration(labelText: 'Diocesan office phone (optional)')),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.sage),
                    onPressed: _savingLeadership ? null : _saveLeadership,
                    child: _savingLeadership
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Leadership Info'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Shows the full diagnostic result after each sync - synced count,
/// how many readings got auto-populated, and critically, exactly what
/// needed review, so a shape mismatch is visible immediately rather
/// than a silent gap someone finds weeks later.
class FeastCalendarSyncSection extends StatefulWidget {
  const FeastCalendarSyncSection();

  @override
  State<FeastCalendarSyncSection> createState() => _FeastCalendarSyncSectionState();
}

class _FeastCalendarSyncSectionState extends State<FeastCalendarSyncSection> {
  final _yearCtrl = TextEditingController(text: DateTime.now().year.toString());
  final _nationalCalendarCtrl = TextEditingController();
  bool _syncing = false;
  Map<String, dynamic>? _lastResult;
  String? _error;

  Future<void> _sync() async {
    final year = int.tryParse(_yearCtrl.text.trim());
    if (year == null) return;
    setState(() { _syncing = true; _error = null; _lastResult = null; });
    try {
      final result = await FirestoreService().syncFeastCalendar(
        year: year,
        nationalCalendar: _nationalCalendarCtrl.text.trim().isEmpty ? null : _nationalCalendarCtrl.text.trim(),
      );
      if (mounted) setState(() { _lastResult = result; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _syncing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: TextField(controller: _yearCtrl, decoration: const InputDecoration(labelText: 'Year'), keyboardType: TextInputType.number),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _nationalCalendarCtrl,
              decoration: const InputDecoration(labelText: 'National calendar (optional)', hintText: 'e.g. ZA - leave blank for General Roman'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _syncing ? null : _sync,
          icon: _syncing
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync, size: 16),
          label: Text(_syncing ? 'Syncing...' : 'Sync Feast Calendar'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              color: Colors.red.withValues(alpha: 0.08),
              child: Text('Sync failed: $_error', style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
            ),
          ),
        if (_lastResult != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Synced ${_lastResult!['synced']} days, auto-populated ${_lastResult!['readingsPopulated']} readings.', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                if ((_lastResult!['needsReviewCount'] as int? ?? 0) > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_lastResult!['needsReviewCount']} entries needed review - the API response didn\'t match what this sync expected for these:',
                    style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  ...((_lastResult!['needsReview'] as List<dynamic>? ?? []).map((item) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${item['event_key'] ?? '(no event_key)'} - ${item['reason']}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ))),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Nothing needed review - every entry matched the expected shape.', style: TextStyle(fontSize: 12, color: AppColors.sage)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Same structure and reasoning as _DioceseManagementSection, one level
/// higher in the hierarchy - a province genuinely belongs to a country,
/// and the generic GenericAdminCrudSection framework can't do a
/// dynamically-fetched dropdown (only static option lists), which is
/// exactly why this field never existed until now despite addProvince
/// having supported it since Country CRUD was first built.
class _ProvinceManagementSection extends StatefulWidget {
  final VoidCallback onProvinceChanged;
  const _ProvinceManagementSection({super.key, required this.onProvinceChanged});

  @override
  State<_ProvinceManagementSection> createState() => _ProvinceManagementSectionState();
}

class _ProvinceManagementSectionState extends State<_ProvinceManagementSection> {
  late Future<List<Map<String, dynamic>>> _countriesFuture;
  String? _selectedCountryId;
  List<Map<String, dynamic>> _allProvinces = [];
  bool _loadingProvinces = true;

  final _nameCtrl = TextEditingController();
  bool _submittingProvince = false;
  bool _showAddProvinceForm = false;

  @override
  void initState() {
    super.initState();
    _countriesFuture = FirestoreService().getCountries();
    _loadProvinces();
  }

  Future<void> _loadProvinces() async {
    setState(() { _loadingProvinces = true; });
    final provinces = await FirestoreService().getProvinces();
    if (mounted) setState(() { _allProvinces = provinces; _loadingProvinces = false; });
  }

  List<Map<String, dynamic>> get _provincesForSelectedCountry {
    if (_selectedCountryId == null) return _allProvinces.where((p) => p['countryId'] == null).toList();
    return _allProvinces.where((p) => p['countryId'] == _selectedCountryId).toList();
  }

  Future<void> _createProvince() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() { _submittingProvince = true; });
    try {
      await FirestoreService().addProvince(_nameCtrl.text.trim(), countryId: _selectedCountryId);
      _nameCtrl.clear();
      await _loadProvinces();
      if (mounted) setState(() { _showAddProvinceForm = false; });
      widget.onProvinceChanged();
    } finally {
      if (mounted) setState(() { _submittingProvince = false; });
    }
  }

  Future<void> _editProvince(Map<String, dynamic> province) async {
    final nameCtrl = TextEditingController(text: province['name'] ?? '');
    String? editCountryId = province['countryId'];
    final countries = await _countriesFuture;
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('Edit Province', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Province name')),
              const SizedBox(height: 8),
              DropdownButton<String?>(
                value: editCountryId, isExpanded: true,
                hint: const Text('No country set', style: TextStyle(fontSize: 13)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('No country set')),
                  ...countries.map((c) => DropdownMenuItem<String?>(value: c['id'] as String, child: Text(c['name'] ?? ''))),
                ],
                onChanged: (v) => setDialogState(() => editCountryId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await FirestoreService().updateProvince(province['id'], nameCtrl.text.trim(), countryId: editCountryId);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _loadProvinces();
                widget.onProvinceChanged();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProvince(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Delete Province?', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: const Text('Every diocese, parish, and church under it becomes orphaned data - not automatically cleaned up. This can\'t be undone.', style: TextStyle(fontSize: 13)),
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
      await FirestoreService().deleteProvince(id);
      await _loadProvinces();
      widget.onProvinceChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _countriesFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            final countries = snap.data ?? [];
            return DropdownButton<String?>(
              value: _selectedCountryId,
              isExpanded: true,
              hint: const Text('Filter by country (optional)', style: TextStyle(fontSize: 13)),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All / no country set')),
                ...countries.map((c) => DropdownMenuItem<String?>(value: c['id'] as String, child: Text(c['name'] ?? ''))),
              ],
              onChanged: (v) => setState(() => _selectedCountryId = v),
            );
          },
        ),
        const SizedBox(height: 10),
        if (_loadingProvinces)
          const LinearProgressIndicator()
        else
          ..._provincesForSelectedCountry.map((p) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p['name'] ?? ''),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.stone),
                onPressed: () => _editProvince(p),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                onPressed: () => _deleteProvince(p['id']),
              ),
            ]),
          )),
        const SizedBox(height: 8),
        if (!_showAddProvinceForm)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => setState(() => _showAddProvinceForm = true),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Province'),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(child: Text('Add New Province', style: TextStyle(fontFamily: appSerif, fontSize: 14))),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _showAddProvinceForm = false)),
                ]),
                Text(
                  _selectedCountryId == null ? 'Will be added with no country set - filter above and select one first if it should belong to a specific country.' : 'Will be added under the country selected above.',
                  style: const TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 8),
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Province name', hintText: 'e.g. Western Cape')),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                  onPressed: _submittingProvince ? null : _createProvince,
                  child: _submittingProvince
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add Province'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Paste-and-parse chapter entry - reusable for all 73 books going
/// forward, not a one-off seed. Handles both "1. text" and "1:1. text"
/// verse prefixes (Gutenberg-style source text uses the latter with a
/// chapter number repeated per verse; stripped here since the chapter
/// is already selected above).
class BibleManagementSection extends StatefulWidget {
  const BibleManagementSection();

  @override
  State<BibleManagementSection> createState() => _BibleManagementSectionState();
}

class _BibleManagementSectionState extends State<BibleManagementSection> {
  late Future<List<Map<String, dynamic>>> _translationsFuture;
  String? _selectedTranslationId;
  final _newTransNameCtrl = TextEditingController();
  bool _newTransIsPublicDomain = true;
  bool _showAddTranslation = false;

  List<Map<String, dynamic>> _manifestBooks = [];
  String? _selectedBookCode;
  int? _selectedChapter;
  final _pasteCtrl = TextEditingController();
  Map<String, String>? _preview;
  bool _saving = false;

  bool _fullSyncRunning = false;
  String? _fullSyncResult;
  List<String> _fullSyncNeedsReview = [];
  Future<List<Map<String, dynamic>>>? _syncSourcesFuture;
  String? _selectedSyncSourceId;

  @override
  void initState() {
    super.initState();
    _translationsFuture = FirestoreService().getBibleTranslations();
    _loadManifest();
    _syncSourcesFuture = FirestoreService().getBibleSyncSources();
  }

  Future<void> _runFullSync() async {
    if (_selectedSyncSourceId == null) return;
    setState(() { _fullSyncRunning = true; _fullSyncResult = null; _fullSyncNeedsReview = []; });
    try {
      final result = await FirestoreService().syncFullBible(sourceId: _selectedSyncSourceId!);
      setState(() {
        _fullSyncResult = '${result['chaptersSynced']} chapters synced across ${result['booksProcessed']} books.';
        _fullSyncNeedsReview = List<String>.from(result['needsReview'] ?? []);
      });
      _refreshTranslations();
    } catch (e) {
      setState(() { _fullSyncResult = 'Sync failed: $e'; });
    } finally {
      if (mounted) setState(() => _fullSyncRunning = false);
    }
  }

  Future<void> _loadManifest() async {
    final raw = await rootBundle.loadString('assets/bible/manifest.json');
    final manifest = json.decode(raw) as Map<String, dynamic>;
    if (mounted) setState(() { _manifestBooks = (manifest['books'] as List).cast<Map<String, dynamic>>(); });
  }

  int? get _chapterCountForSelectedBook {
    if (_selectedBookCode == null) return null;
    final book = _manifestBooks.firstWhere((b) => b['code'] == _selectedBookCode, orElse: () => {});
    return book['chapters'] as int?;
  }

  void _refreshTranslations() {
    setState(() { _translationsFuture = FirestoreService().getBibleTranslations(); });
  }

  Future<void> _addTranslation() async {
    if (_newTransNameCtrl.text.trim().isEmpty) return;
    final code = _newTransNameCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    await FirestoreService().addBibleTranslation(
      code: code, name: _newTransNameCtrl.text.trim(), isPublicDomain: _newTransIsPublicDomain,
    );
    _newTransNameCtrl.clear();
    setState(() { _showAddTranslation = false; });
    _refreshTranslations();
  }

  void _parsePreview() {
    final text = _pasteCtrl.text.trim();
    if (text.isEmpty) { setState(() { _preview = null; }); return; }
    // Splits on a verse-number prefix ("1. " or "1:1. ") at the start of
    // each verse, stripping any repeated chapter number.
    final matches = RegExp(r'(?:\d+:)?(\d+)\.\s+').allMatches(text).toList();
    final verses = <String, String>{};
    for (var i = 0; i < matches.length; i++) {
      final verseNum = matches[i].group(1)!;
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      verses[verseNum] = text.substring(start, end).trim();
    }
    setState(() { _preview = verses.isEmpty ? null : verses; });
  }

  Future<void> _saveChapter() async {
    if (_selectedTranslationId == null || _selectedBookCode == null || _selectedChapter == null || _preview == null) return;
    final chapter = _selectedChapter!;
    setState(() { _saving = true; });
    try {
      await FirestoreService().setBibleChapter(
        translationCode: _selectedTranslationId!,
        bookCode: _selectedBookCode!,
        chapter: chapter,
        verses: _preview!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${_preview!.length} verses.')));
        setState(() { _pasteCtrl.clear(); _preview = null; });
      }
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: AppColors.stone,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sync the Whole Bible', style: TextStyle(fontFamily: appSerif, fontSize: 14, color: Colors.white)),
              const Text(
                'Real, server-side - fetches the complete text for whichever translation you pick below and writes every book and chapter directly. Can take a few minutes for the full text.',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _syncSourcesFuture,
                builder: (context, snap) {
                  final sources = snap.data ?? [];
                  if (sources.isNotEmpty && _selectedSyncSourceId == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _selectedSyncSourceId = sources.first['id']);
                    });
                  }
                  if (sources.isEmpty) return const SizedBox.shrink();
                  return DropdownButton<String>(
                    value: _selectedSyncSourceId,
                    isExpanded: true,
                    dropdownColor: AppColors.stone,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: sources.map((s) => DropdownMenuItem(
                      value: s['id'] as String,
                      child: Text('${s['name']}${s['isPublicDomain'] == true ? ' (public domain)' : ''}'),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedSyncSourceId = v),
                  );
                },
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                onPressed: (_fullSyncRunning || _selectedSyncSourceId == null) ? null : _runFullSync,
                icon: _fullSyncRunning
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_sync, size: 16),
                label: Text(_fullSyncRunning ? 'Syncing... this can take a few minutes' : 'Sync Full Bible'),
              ),
              if (_fullSyncResult != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_fullSyncResult!, style: const TextStyle(fontSize: 12, color: Colors.white)),
                ),
              if (_fullSyncNeedsReview.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _fullSyncNeedsReview.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(item, style: const TextStyle(fontSize: 11, color: Colors.amberAccent)),
                    )).toList(),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _translationsFuture,
          builder: (context, snap) {
            final translations = snap.data ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (translations.isNotEmpty)
                  DropdownButton<String>(
                    value: _selectedTranslationId, isExpanded: true,
                    hint: const Text('Select a translation', style: TextStyle(fontSize: 13)),
                    items: translations.map((t) => DropdownMenuItem(
                      value: t['id'] as String,
                      child: Text('${t['name'] ?? ''}${t['isPublicDomain'] == true ? ' (public domain)' : ''}'),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedTranslationId = v),
                  )
                else
                  const Text('No translations added yet.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                if (!_showAddTranslation)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                    onPressed: () => setState(() => _showAddTranslation = true),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Translation'),
                  )
                else
                  Material(
                    color: AppColors.paperDark,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(controller: _newTransNameCtrl, decoration: const InputDecoration(labelText: 'Translation name', hintText: 'e.g. Douay-Rheims (Challoner)')),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: AppColors.sage,
                          title: const Text('Public domain', style: TextStyle(fontSize: 13)),
                          value: _newTransIsPublicDomain,
                          onChanged: (v) => setState(() => _newTransIsPublicDomain = v),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                          onPressed: _addTranslation,
                          child: const Text('Add'),
                        ),
                      ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (_selectedTranslationId != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add / Replace a Chapter', style: TextStyle(fontFamily: appSerif, fontSize: 14)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButton<String>(
                      value: _selectedBookCode,
                      isExpanded: true,
                      hint: const Text('Book', style: TextStyle(fontSize: 13)),
                      items: _manifestBooks.map((b) => DropdownMenuItem(value: b['code'] as String, child: Text(b['name'] ?? ''))).toList(),
                      onChanged: (v) => setState(() { _selectedBookCode = v; _selectedChapter = null; }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<int>(
                      value: _selectedChapter,
                      isExpanded: true,
                      hint: const Text('Chapter', style: TextStyle(fontSize: 13)),
                      items: _chapterCountForSelectedBook == null
                          ? []
                          : List.generate(_chapterCountForSelectedBook!, (i) => i + 1)
                              .map((c) => DropdownMenuItem(value: c, child: Text('$c')))
                              .toList(),
                      onChanged: (v) => setState(() => _selectedChapter = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: _pasteCtrl, maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Paste chapter text', hintText: '1. In the beginning God created heaven, and earth. 2. And the earth was void...'),
                  onChanged: (_) => _parsePreview(),
                ),
                const SizedBox(height: 8),
                if (_preview != null)
                  Text('${_preview!.length} verses parsed - ready to save.', style: const TextStyle(fontSize: 12, color: AppColors.sage, fontWeight: FontWeight.w600))
                else
                  const Text('Paste text above to preview the verse split.', style: TextStyle(fontSize: 12, color: Colors.black45)),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                  onPressed: (_preview == null || _saving) ? null : _saveChapter,
                  child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Chapter'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _BulkBookImportSection(translationId: _selectedTranslationId!, manifestBooks: _manifestBooks),
        ],
      ],
    );
  }
}

/// Accepts an entire book at once in "chapter:verse. text" format (the
/// standard shape real source text like Gutenberg's Douay-Rheims comes
/// in) and splits it into proper per-chapter documents automatically -
/// built specifically so seeing what the reader actually looks like
/// with real content doesn't require pasting one chapter at a time.
class _BulkBookImportSection extends StatefulWidget {
  final String translationId;
  final List<Map<String, dynamic>> manifestBooks;
  const _BulkBookImportSection({required this.translationId, required this.manifestBooks});

  @override
  State<_BulkBookImportSection> createState() => _BulkBookImportSectionState();
}

class _BulkBookImportSectionState extends State<_BulkBookImportSection> {
  String? _bookCode;
  final _pasteCtrl = TextEditingController();
  Map<int, Map<String, String>>? _preview; // chapter -> {verse: text}
  bool _saving = false;
  int _savedCount = 0;

  void _parse() {
    final text = _pasteCtrl.text.trim();
    if (text.isEmpty) { setState(() { _preview = null; }); return; }
    // Matches "C:V. " at the start of each verse - the exact shape real
    // source text like Gutenberg's Douay-Rheims uses throughout.
    final matches = RegExp(r'(\d+):(\d+)\.\s+').allMatches(text).toList();
    final chapters = <int, Map<String, String>>{};
    for (var i = 0; i < matches.length; i++) {
      final chapter = int.parse(matches[i].group(1)!);
      final verse = matches[i].group(2)!;
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      chapters.putIfAbsent(chapter, () => {})[verse] = text.substring(start, end).trim();
    }
    setState(() { _preview = chapters.isEmpty ? null : chapters; });
  }

  Future<void> _saveAll() async {
    if (_bookCode == null || _preview == null) return;
    setState(() { _saving = true; _savedCount = 0; });
    try {
      for (final entry in _preview!.entries) {
        await FirestoreService().setBibleChapter(
          translationCode: widget.translationId, bookCode: _bookCode!,
          chapter: entry.key, verses: entry.value,
        );
        if (mounted) setState(() => _savedCount++);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $_savedCount chapters.')));
        setState(() { _pasteCtrl.clear(); _preview = null; });
      }
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.paperDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bulk Import a Whole Book', style: TextStyle(fontFamily: appSerif, fontSize: 14)),
          const Text(
            'Paste an entire book at once in "chapter:verse. text" format - splits into separate chapters automatically. Useful for seeing what real, substantial content actually looks like, rather than one chapter at a time.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: _bookCode, isExpanded: true,
            hint: const Text('Book', style: TextStyle(fontSize: 13)),
            items: widget.manifestBooks.map((b) => DropdownMenuItem(value: b['code'] as String, child: Text(b['name'] ?? ''))).toList(),
            onChanged: (v) => setState(() => _bookCode = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pasteCtrl, maxLines: 12,
            decoration: const InputDecoration(labelText: 'Paste the whole book', hintText: '1:1. In the beginning God created heaven, and earth. 1:2. And the earth was void... 2:1. Thus the heavens and the earth were finished...'),
            onChanged: (_) => _parse(),
          ),
          const SizedBox(height: 8),
          if (_preview != null)
            Text('${_preview!.length} chapters, ${_preview!.values.fold(0, (sum, v) => sum + v.length)} verses parsed - ready to save.', style: const TextStyle(fontSize: 12, color: AppColors.sage, fontWeight: FontWeight.w600))
          else
            const Text('Paste text above to preview the chapter split.', style: TextStyle(fontSize: 12, color: Colors.black45)),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: (_bookCode == null || _preview == null || _saving) ? null : _saveAll,
            child: _saving
                ? Text('Saving... ($_savedCount/${_preview?.length ?? 0})', style: const TextStyle(color: Colors.white, fontSize: 13))
                : const Text('Save All Chapters'),
          ),
        ],
      ),
    );
  }
}

/// Real date pickers instead of free-typed "MM-DD" strings, a growing
/// shared tag list for Patron Of instead of retyping the same values,
/// and image upload with a manual-URL fallback for saints an API
/// wouldn't have artwork for. Built bespoke because the generic CRUD
/// framework has no support for any of these three things.
class SaintsManagementSection extends StatefulWidget {
  const SaintsManagementSection();

  @override
  State<SaintsManagementSection> createState() => _SaintsManagementSectionState();
}

class _SaintsManagementSectionState extends State<SaintsManagementSection> {
  late Future<List<Map<String, dynamic>>> _saintsFuture;
  bool _showForm = false;
  Map<String, dynamic>? _editing;

  @override
  void initState() {
    super.initState();
    _saintsFuture = FirestoreService().getAllSaints();
  }

  void _refresh() => setState(() { _saintsFuture = FirestoreService().getAllSaints(); });

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Delete Saint?', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: const Text('This can\'t be undone.', style: TextStyle(fontSize: 13)),
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
      await FirestoreService().deleteSaint(id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _saintsFuture,
          builder: (context, snap) {
            final saints = snap.data ?? [];
            if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            return Column(
              children: saints.map((s) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: s['imageUrl'] != null
                    ? CircleAvatar(backgroundImage: NetworkImage(s['imageUrl']))
                    : const CircleAvatar(child: Icon(Icons.church, size: 18)),
                title: Text(s['name'] ?? ''),
                subtitle: Text(s['feastDay'] ?? s['feastMonthDay'] ?? ''),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.stone),
                    onPressed: () => setState(() { _editing = s; _showForm = true; }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    onPressed: () => _delete(s['id']),
                  ),
                ]),
              )).toList(),
            );
          },
        ),
        const SizedBox(height: 8),
        if (!_showForm)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => setState(() { _editing = null; _showForm = true; }),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Saint'),
          )
        else
          _SaintForm(
            existing: _editing,
            onDone: () { setState(() { _showForm = false; }); _refresh(); },
            onCancel: () => setState(() => _showForm = false),
          ),
      ],
    );
  }
}

class _SaintForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onDone;
  final VoidCallback onCancel;
  const _SaintForm({required this.existing, required this.onDone, required this.onCancel});

  @override
  State<_SaintForm> createState() => _SaintFormState();
}

class _SaintFormState extends State<_SaintForm> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _earlyLifeCtrl = TextEditingController();
  final _whySaintCtrl = TextEditingController();
  final _newTagCtrl = TextEditingController();

  DateTime? _feastDate;
  DateTime? _birthDate;
  DateTime? _deathDate;
  bool _birthYearOnly = false;
  bool _deathYearOnly = false;
  int? _birthYearValue;
  int? _deathYearValue;

  String? _imageUrl;
  XFile? _pickedImage;
  bool _uploadingImage = false;
  bool _saving = false;

  late Future<List<String>> _tagsFuture;
  final Set<String> _selectedTags = {};

  @override
  void initState() {
    super.initState();
    _tagsFuture = FirestoreService().getPatronageTags();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e['name'] ?? '';
      _bioCtrl.text = e['bio'] ?? '';
      _earlyLifeCtrl.text = e['earlyLife'] ?? '';
      _whySaintCtrl.text = e['whySaint'] ?? '';
      _imageUrl = e['imageUrl'];
      _selectedTags.addAll(List<String>.from(e['patronage'] ?? []));
      if (e['feastMonthDay'] != null) {
        final parts = (e['feastMonthDay'] as String).split('-');
        if (parts.length == 2) _feastDate = DateTime(2000, int.parse(parts[0]), int.parse(parts[1]));
      }
      if (e['birthYear'] != null && e['birthMonthDay'] == null) { _birthYearOnly = true; _birthYearValue = e['birthYear']; }
      if (e['birthMonthDay'] != null) {
        final parts = (e['birthMonthDay'] as String).split('-');
        if (parts.length == 2) _birthDate = DateTime(e['birthYear'] ?? 2000, int.parse(parts[0]), int.parse(parts[1]));
      }
      if (e['deathYear'] != null && e['deathMonthDay'] == null) { _deathYearOnly = true; _deathYearValue = e['deathYear']; }
      if (e['deathMonthDay'] != null) {
        final parts = (e['deathMonthDay'] as String).split('-');
        if (parts.length == 2) _deathDate = DateTime(e['deathYear'] ?? 2000, int.parse(parts[0]), int.parse(parts[1]));
      }
    }
  }

  Future<void> _pickFeastDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _feastDate ?? DateTime.now(),
      firstDate: DateTime(2000, 1, 1), lastDate: DateTime(2000, 12, 31),
      helpText: 'Pick the feast date (year doesn\'t matter - it repeats annually)',
    );
    if (picked != null) setState(() { _feastDate = DateTime(2000, picked.month, picked.day); });
  }

  Future<void> _pickBirthOrDeathDate({required bool isBirth}) async {
    final current = isBirth ? _birthDate : _deathDate;
    final picked = await showDatePicker(
      context: context, initialDate: current ?? DateTime(1950),
      firstDate: DateTime(100), lastDate: DateTime.now(),
      helpText: isBirth ? 'Pick the birth date, if known' : 'Pick the death date, if known',
    );
    if (picked != null) {
      setState(() {
        if (isBirth) { _birthDate = picked; _birthYearOnly = false; } else { _deathDate = picked; _deathYearOnly = false; }
      });
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800);
    if (picked != null) setState(() { _pickedImage = picked; });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() { _saving = true; });
    try {
      String? imageUrl = _imageUrl;
      if (_pickedImage != null) {
        setState(() { _uploadingImage = true; });
        imageUrl = await FirestoreService().uploadSaintImage(_pickedImage!);
        setState(() { _uploadingImage = false; });
      }

      if (_selectedTags.isNotEmpty) await FirestoreService().ensurePatronageTagsExist(_selectedTags.toList());

      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'earlyLife': _earlyLifeCtrl.text.trim().isEmpty ? null : _earlyLifeCtrl.text.trim(),
        'whySaint': _whySaintCtrl.text.trim().isEmpty ? null : _whySaintCtrl.text.trim(),
        'imageUrl': imageUrl,
        'patronage': _selectedTags.toList(),
        if (_feastDate != null) 'feastMonthDay': '${_feastDate!.month.toString().padLeft(2, '0')}-${_feastDate!.day.toString().padLeft(2, '0')}',
        if (_feastDate != null) 'feastDay': DateFormat('MMMM d').format(_feastDate!),
        if (_birthDate != null) 'birthMonthDay': '${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}',
        if (_birthDate != null) 'birthYear': _birthDate!.year,
        if (_birthYearOnly && _birthYearValue != null) 'birthYear': _birthYearValue,
        if (_deathDate != null) 'deathMonthDay': '${_deathDate!.month.toString().padLeft(2, '0')}-${_deathDate!.day.toString().padLeft(2, '0')}',
        if (_deathDate != null) 'deathYear': _deathDate!.year,
        if (_deathYearOnly && _deathYearValue != null) 'deathYear': _deathYearValue,
      };

      if (widget.existing != null) {
        await FirestoreService().updateSaint(widget.existing!['id'], data);
      } else {
        await FirestoreService().addSaint(data);
      }
      widget.onDone();
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  Widget _dateField(String label, DateTime? date, VoidCallback onTap, {bool showYearOnlyOption = false, bool yearOnly = false, int? yearOnlyValue, ValueChanged<bool>? onYearOnlyChanged, ValueChanged<int?>? onYearChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              const Icon(Icons.calendar_today, size: 16, color: Colors.black45),
              const SizedBox(width: 8),
              Expanded(child: Text(date != null ? DateFormat(showYearOnlyOption ? 'd MMMM yyyy' : 'MMMM d').format(date) : label, style: const TextStyle(fontSize: 13))),
            ]),
          ),
        ),
        if (showYearOnlyOption)
          Row(children: [
            Checkbox(value: yearOnly, onChanged: (v) => onYearOnlyChanged?.call(v ?? false)),
            const Text('Only the year is known (historical saint)', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        if (showYearOnlyOption && yearOnly)
          TextField(
            decoration: const InputDecoration(labelText: 'Year', hintText: 'e.g. 1195'),
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: yearOnlyValue?.toString() ?? ''),
            onChanged: (v) => onYearChanged?.call(int.tryParse(v)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.paperDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(widget.existing != null ? 'Edit Saint' : 'Add Saint', style: const TextStyle(fontFamily: appSerif, fontSize: 15))),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: widget.onCancel),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            if (_pickedImage != null || _imageUrl != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _pickedImage != null
                    ? FutureBuilder<Uint8List>(
                        future: _pickedImage!.readAsBytes(),
                        builder: (context, snap) => CircleAvatar(
                          radius: 28,
                          backgroundImage: snap.hasData ? MemoryImage(snap.data!) : null,
                          child: snap.hasData ? null : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      )
                    : CircleAvatar(radius: 28, backgroundImage: NetworkImage(_imageUrl!)),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
              onPressed: _uploadingImage ? null : _pickImage,
              icon: const Icon(Icons.image_outlined, size: 16),
              label: Text(_pickedImage != null ? 'New image selected' : (_imageUrl != null ? 'Replace Photo' : 'Choose Photo')),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Saint Jude Thaddeus')),
          const SizedBox(height: 10),
          const Text('Feast Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          _dateField('Pick the feast date', _feastDate, _pickFeastDate),
          const SizedBox(height: 10),
          const Text('Born', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          _dateField(
            'Pick birth date (if known)', _birthDate, () => _pickBirthOrDeathDate(isBirth: true),
            showYearOnlyOption: true, yearOnly: _birthYearOnly, yearOnlyValue: _birthYearValue,
            onYearOnlyChanged: (v) => setState(() { _birthYearOnly = v; if (v) _birthDate = null; }),
            onYearChanged: (v) => setState(() => _birthYearValue = v),
          ),
          const SizedBox(height: 10),
          const Text('Died', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          _dateField(
            'Pick death date (if known)', _deathDate, () => _pickBirthOrDeathDate(isBirth: false),
            showYearOnlyOption: true, yearOnly: _deathYearOnly, yearOnlyValue: _deathYearValue,
            onYearOnlyChanged: (v) => setState(() { _deathYearOnly = v; if (v) _deathDate = null; }),
            onYearChanged: (v) => setState(() => _deathYearValue = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: _earlyLifeCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Early life / childhood (optional)')),
          const SizedBox(height: 8),
          TextField(controller: _whySaintCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Why is this person a saint? (optional)')),
          const SizedBox(height: 8),
          TextField(controller: _bioCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'General biography')),
          const SizedBox(height: 10),
          const Text('Patron Of', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FutureBuilder<List<String>>(
            future: _tagsFuture,
            builder: (context, snap) {
              final tags = snap.data ?? [];
              return Wrap(
                spacing: 6, runSpacing: 6,
                children: tags.map((t) => FilterChip(
                  label: Text(t, style: const TextStyle(fontSize: 12)),
                  selected: _selectedTags.contains(t),
                  selectedColor: AppColors.brass.withValues(alpha: 0.25),
                  onSelected: (sel) => setState(() { if (sel) { _selectedTags.add(t); } else { _selectedTags.remove(t); } }),
                )).toList(),
              );
            },
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _newTagCtrl,
                decoration: const InputDecoration(labelText: 'New patronage (not in the list above)', hintText: 'e.g. fishermen'),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: AppColors.brass),
              onPressed: () {
                final v = _newTagCtrl.text.trim();
                if (v.isEmpty) return;
                setState(() { _selectedTags.add(v); _newTagCtrl.clear(); _tagsFuture = FirestoreService().getPatronageTags(); });
              },
            ),
          ]),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Saint'),
          ),
        ],
      ),
    );
  }
}

/// Bespoke because the generic CRUD framework can't do a date picker,
/// year-cycle dropdowns, or a dynamic petitions list. Follows the exact
/// order of a real missal: title/date up top, then Entrance Antiphon,
/// First Reading, Psalm, Second Reading, Gospel Acclamation, Gospel,
/// Verse for the Day, Reflection, a second themed box, Prayers of the
/// Faithful, Communion Antiphon.
class LiturgicalReadingsSection extends StatefulWidget {
  const LiturgicalReadingsSection();

  @override
  State<LiturgicalReadingsSection> createState() => _LiturgicalReadingsSectionState();
}

class _LiturgicalReadingsSectionState extends State<LiturgicalReadingsSection> {
  late Future<List<Map<String, dynamic>>> _readingsFuture;
  final _searchCtrl = TextEditingController();

  bool _citationsSyncing = false;
  String? _citationsSyncResult;
  final _citationsSyncYearCtrl = TextEditingController(text: DateTime.now().year.toString());

  bool _usccbSyncing = false;
  String? _usccbSyncResult;
  final _usccbYearCtrl = TextEditingController(text: DateTime.now().year.toString());
  final _usccbMonthCtrl = TextEditingController(text: DateTime.now().month.toString());

  @override
  void initState() {
    super.initState();
    _readingsFuture = FirestoreService().getAllLiturgicalReadings();
  }

  void _refresh() => setState(() { _readingsFuture = FirestoreService().getAllLiturgicalReadings(); });

  Future<void> _syncCitations() async {
    final year = int.tryParse(_citationsSyncYearCtrl.text.trim());
    if (year == null) return;
    setState(() { _citationsSyncing = true; _citationsSyncResult = null; });
    try {
      final result = await FirestoreService().syncDailyReadingsCitations(year: year);
      setState(() {
        _citationsSyncResult = '${result['created']} days created, ${result['filled']} filled in, ${result['unchanged']} already complete.'
            '${(result['failureCount'] ?? 0) > 0 ? ' ${result['failureCount']} failed.' : ''}';
      });
      _refresh();
    } catch (e) {
      setState(() { _citationsSyncResult = 'Sync failed: $e'; });
    } finally {
      if (mounted) setState(() { _citationsSyncing = false; });
    }
  }

  Future<void> _syncUsccb() async {
    final year = int.tryParse(_usccbYearCtrl.text.trim());
    final month = int.tryParse(_usccbMonthCtrl.text.trim());
    if (year == null || month == null || month < 1 || month > 12) {
      setState(() { _usccbSyncResult = 'Enter a valid year and a month between 1 and 12.'; });
      return;
    }
    setState(() { _usccbSyncing = true; _usccbSyncResult = null; });
    try {
      final result = await FirestoreService().syncUsccbCitations(year: year, month: month);
      setState(() {
        final failures = List<String>.from(result['failures'] ?? []);
        _usccbSyncResult = '${result['datesFound']} dates found, ${result['created']} created, ${result['filled']} filled in, ${result['unchanged']} already complete.'
            '${failures.isNotEmpty ? '\n\n${result['failureCount']} failed:\n${failures.take(10).join('\n')}' : ''}';
      });
      _refresh();
    } catch (e) {
      setState(() { _usccbSyncResult = 'Sync failed: $e'; });
    } finally {
      if (mounted) setState(() { _usccbSyncing = false; });
    }
  }

  Future<void> _delete(String date) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Delete this day\'s readings?', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: const Text('This can\'t be undone.', style: TextStyle(fontSize: 13)),
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
      await FirestoreService().deleteLiturgicalReading(date);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: AppColors.stone,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sync Reading Citations', style: TextStyle(fontFamily: appSerif, fontSize: 14, color: Colors.white)),
              const Text(
                'Real, verified source (cpbjr Catholic Readings API, MIT licensed) - fills in First Reading/Psalm/Second Reading/Gospel citations for every day of the year, independent of whether a saint entry exists for that date. Never overwrites an existing entry - a priest\'s own manual citation always wins. Citations only, never the reading\'s actual text.',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _citationsSyncYearCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Year', labelStyle: TextStyle(color: Colors.white70)),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                  onPressed: _citationsSyncing ? null : _syncCitations,
                  icon: _citationsSyncing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync, size: 16),
                  label: Text(_citationsSyncing ? 'Syncing...' : 'Sync Citations'),
                ),
              ]),
              if (_citationsSyncResult != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(_citationsSyncResult!, style: const TextStyle(fontSize: 12, color: Colors.white))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: AppColors.paperDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sync Citations from USCCB', style: TextStyle(fontFamily: appSerif, fontSize: 14)),
              const Text(
                'Real, official source (bible.usccb.org) - scrapes that month\'s calendar page for each date\'s real URL first (some dates use a slug instead of the standard pattern), then follows each real link for citations only. USCCB\'s own reading text is confirmed copyrighted, so only the linked reference (e.g. "Genesis 1:1-2:2") is ever extracted, never the verse text itself. Correctly captures the Easter Vigil\'s full multi-reading structure into Vigil Readings when a day has more than the standard 4.',
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(width: 90, child: TextField(controller: _usccbYearCtrl, decoration: const InputDecoration(labelText: 'Year'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: TextField(controller: _usccbMonthCtrl, decoration: const InputDecoration(labelText: 'Month'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.sage),
                  onPressed: _usccbSyncing ? null : _syncUsccb,
                  icon: _usccbSyncing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync, size: 16),
                  label: Text(_usccbSyncing ? 'Syncing...' : 'Sync Month'),
                ),
              ]),
              if (_usccbSyncResult != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(_usccbSyncResult!, style: const TextStyle(fontSize: 12))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(labelText: 'Search by date or title', prefixIcon: Icon(Icons.search)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _readingsFuture,
          builder: (context, snap) {
            var readings = snap.data ?? [];
            if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            final query = _searchCtrl.text.trim().toLowerCase();
            if (query.isNotEmpty) {
              readings = readings.where((r) =>
                (r['date'] as String? ?? '').toLowerCase().contains(query) ||
                (r['liturgicalTitle'] as String? ?? '').toLowerCase().contains(query)
              ).toList();
            }
            if (readings.isEmpty) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No matching dates.', style: TextStyle(fontSize: 12, color: Colors.black45)));
            }
            return Column(
              children: readings.map((r) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${r['date']} — ${r['liturgicalTitle'] ?? ''}', style: const TextStyle(fontSize: 13)),
                subtitle: Text(r['firstReading'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.stone),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: AppColors.paper,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: _LiturgicalReadingForm(
                              existing: r,
                              onDone: () { Navigator.pop(context); _refresh(); },
                              onCancel: () => Navigator.pop(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    onPressed: () => _delete(r['date']),
                  ),
                ]),
              )).toList(),
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: AppColors.paper,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _LiturgicalReadingForm(
                    existing: null,
                    onDone: () { Navigator.pop(context); _refresh(); },
                    onCancel: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Reading'),
        ),
      ],
    );
  }
}

class _LiturgicalReadingForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onDone;
  final VoidCallback onCancel;
  const _LiturgicalReadingForm({required this.existing, required this.onDone, required this.onCancel});

  @override
  State<_LiturgicalReadingForm> createState() => _LiturgicalReadingFormState();
}

class _LiturgicalReadingFormState extends State<_LiturgicalReadingForm> {
  DateTime? _date;
  final _titleCtrl = TextEditingController();
  String? _sundayCycle;
  String? _weekdayCycle;

  final _entranceAntiphonCtrl = TextEditingController();
  final _firstReadingCtrl = TextEditingController();
  final _psalmCtrl = TextEditingController();
  final _psalmResponseCtrl = TextEditingController();
  final _secondReadingCtrl = TextEditingController();
  final _gospelAcclamationCtrl = TextEditingController();
  final _gospelCtrl = TextEditingController();
  final _verseForTheDayCtrl = TextEditingController();
  final _verseForTheDayCitationCtrl = TextEditingController();
  final _reflectionTitleCtrl = TextEditingController();
  final _reflectionBodyCtrl = TextEditingController();
  final _themedBoxTitleCtrl = TextEditingController();
  final _themedBoxBodyCtrl = TextEditingController();
  final _prayersIntroCtrl = TextEditingController();
  final _prayersResponseCtrl = TextEditingController();
  final List<TextEditingController> _petitionCtrls = [];
  final _prayersClosingCtrl = TextEditingController();
  final _communionAntiphonCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();

  // Vigil readings - empty on every ordinary day, only used for a
  // liturgy needing more than the standard First/Second Reading
  // structure (the Easter Vigil's traditional up-to-7 Old Testament
  // readings, each with its own psalm, is the real example). Three
  // parallel lists, index-matched, rather than one list of small
  // objects - simpler to wire up with TextEditingControllers this way.
  final List<TextEditingController> _vigilReadingCtrls = [];
  final List<TextEditingController> _vigilPsalmCtrls = [];
  final List<TextEditingController> _vigilPsalmResponseCtrls = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final parts = (e['date'] as String).split('-');
      if (parts.length == 3) _date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      _titleCtrl.text = e['liturgicalTitle'] ?? '';
      _sundayCycle = (e['sundayCycle'] as String?)?.isEmpty ?? true ? null : e['sundayCycle'];
      _weekdayCycle = (e['weekdayCycle'] as String?)?.isEmpty ?? true ? null : e['weekdayCycle'];
      _entranceAntiphonCtrl.text = e['entranceAntiphon'] ?? '';
      _firstReadingCtrl.text = e['firstReading'] ?? '';
      _psalmCtrl.text = e['psalm'] ?? '';
      _psalmResponseCtrl.text = e['psalmResponse'] ?? '';
      _secondReadingCtrl.text = e['secondReading'] ?? '';
      _gospelAcclamationCtrl.text = e['gospelAcclamation'] ?? '';
      _gospelCtrl.text = e['gospel'] ?? '';
      _verseForTheDayCtrl.text = e['verseForTheDay'] ?? '';
      _verseForTheDayCitationCtrl.text = e['verseForTheDayCitation'] ?? '';
      _reflectionTitleCtrl.text = e['reflectionTitle'] ?? '';
      _reflectionBodyCtrl.text = e['reflectionBody'] ?? '';
      _themedBoxTitleCtrl.text = e['themedBoxTitle'] ?? '';
      _themedBoxBodyCtrl.text = e['themedBoxBody'] ?? '';
      _prayersIntroCtrl.text = e['prayersIntro'] ?? '';
      _prayersResponseCtrl.text = e['prayersResponse'] ?? '';
      for (final p in List<String>.from(e['petitions'] ?? [])) {
        _petitionCtrls.add(TextEditingController(text: p));
      }
      _prayersClosingCtrl.text = e['prayersClosing'] ?? '';
      _communionAntiphonCtrl.text = e['communionAntiphon'] ?? '';
      _sourceCtrl.text = e['source'] ?? '';
      final vigilList = List<dynamic>.from(e['vigilReadings'] ?? [])
          .map((v) => Map<String, dynamic>.from(v))
          .toList()
        ..sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
      for (final v in vigilList) {
        _vigilReadingCtrls.add(TextEditingController(text: v['reading'] ?? ''));
        _vigilPsalmCtrls.add(TextEditingController(text: v['psalm'] ?? ''));
        _vigilPsalmResponseCtrls.add(TextEditingController(text: v['psalmResponse'] ?? ''));
      }
    }
    if (_petitionCtrls.isEmpty) _petitionCtrls.add(TextEditingController());
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2035),
    );
    if (picked != null) setState(() { _date = picked; });
  }

  Future<void> _save() async {
    if (_date == null || _titleCtrl.text.trim().isEmpty || _firstReadingCtrl.text.trim().isEmpty || _gospelCtrl.text.trim().isEmpty) return;
    setState(() { _saving = true; });
    try {
      final dateStr = '${_date!.year.toString().padLeft(4, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}';
      final data = {
        'liturgicalTitle': _titleCtrl.text.trim(),
        'sundayCycle': _sundayCycle,
        'weekdayCycle': _weekdayCycle,
        'entranceAntiphon': _entranceAntiphonCtrl.text.trim(),
        'firstReading': _firstReadingCtrl.text.trim(),
        'psalm': _psalmCtrl.text.trim(),
        'psalmResponse': _psalmResponseCtrl.text.trim(),
        'secondReading': _secondReadingCtrl.text.trim(),
        'gospelAcclamation': _gospelAcclamationCtrl.text.trim(),
        'gospel': _gospelCtrl.text.trim(),
        'verseForTheDay': _verseForTheDayCtrl.text.trim(),
        'verseForTheDayCitation': _verseForTheDayCitationCtrl.text.trim(),
        'reflectionTitle': _reflectionTitleCtrl.text.trim(),
        'reflectionBody': _reflectionBodyCtrl.text.trim(),
        'themedBoxTitle': _themedBoxTitleCtrl.text.trim(),
        'themedBoxBody': _themedBoxBodyCtrl.text.trim(),
        'prayersIntro': _prayersIntroCtrl.text.trim(),
        'prayersResponse': _prayersResponseCtrl.text.trim(),
        'petitions': _petitionCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList(),
        'prayersClosing': _prayersClosingCtrl.text.trim(),
        'communionAntiphon': _communionAntiphonCtrl.text.trim(),
        'source': _sourceCtrl.text.trim().isEmpty ? 'manual' : _sourceCtrl.text.trim(),
        'vigilReadings': [
          for (var i = 0; i < _vigilReadingCtrls.length; i++)
            if (_vigilReadingCtrls[i].text.trim().isNotEmpty)
              {
                'order': i,
                'reading': _vigilReadingCtrls[i].text.trim(),
                'psalm': _vigilPsalmCtrls[i].text.trim().isEmpty ? null : _vigilPsalmCtrls[i].text.trim(),
                'psalmResponse': _vigilPsalmResponseCtrls[i].text.trim().isEmpty ? null : _vigilPsalmResponseCtrls[i].text.trim(),
              },
        ],
      };
      if (widget.existing != null) {
        await FirestoreService().updateLiturgicalReading(dateStr, data);
      } else {
        await FirestoreService().addLiturgicalReading({...data, 'date': dateStr});
      }
      widget.onDone();
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  Widget _field(TextEditingController ctrl, String label, {int maxLines = 1, bool required = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(controller: ctrl, maxLines: maxLines, decoration: InputDecoration(labelText: required ? '$label *' : label)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.paperDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(widget.existing != null ? 'Edit Reading' : 'Add Reading', style: const TextStyle(fontFamily: appSerif, fontSize: 15))),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: widget.onCancel),
          ]),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.black45),
                const SizedBox(width: 8),
                Text(_date != null ? DateFormat('EEEE, d MMMM yyyy').format(_date!) : 'Pick a date *', style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          _field(_titleCtrl, 'Liturgical Title', required: true),
          Row(children: [
            Expanded(
              child: DropdownButton<String?>(
                value: _sundayCycle, isExpanded: true,
                hint: const Text('Sunday Cycle (A/B/C)', style: TextStyle(fontSize: 12)),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('N/A - not a Sunday')),
                  DropdownMenuItem<String?>(value: 'A', child: Text('Year A')),
                  DropdownMenuItem<String?>(value: 'B', child: Text('Year B')),
                  DropdownMenuItem<String?>(value: 'C', child: Text('Year C')),
                ],
                onChanged: (v) => setState(() => _sundayCycle = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String?>(
                value: _weekdayCycle, isExpanded: true,
                hint: const Text('Weekday Cycle (I/II)', style: TextStyle(fontSize: 12)),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('N/A - not a weekday')),
                  DropdownMenuItem<String?>(value: 'I', child: Text('Cycle I')),
                  DropdownMenuItem<String?>(value: 'II', child: Text('Cycle II')),
                ],
                onChanged: (v) => setState(() => _weekdayCycle = v),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _field(_entranceAntiphonCtrl, 'Entrance Antiphon', maxLines: 2),
          _field(_firstReadingCtrl, 'First Reading', maxLines: 3, required: true),
          _field(_psalmCtrl, 'Psalm (verses)', maxLines: 3),
          _field(_psalmResponseCtrl, 'Psalm Response (the repeated "R." line)'),
          _field(_secondReadingCtrl, 'Second Reading (Sundays)', maxLines: 3),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Additional Vigil Readings', style: TextStyle(fontFamily: appSerif, fontSize: 13)),
                const Text(
                  'Only for a liturgy needing more than the standard structure - the Easter Vigil\'s traditional up to 7 Old Testament readings, each with its own psalm, is the real example. Leave empty on every ordinary day.',
                  style: TextStyle(fontSize: 11, color: Colors.black45),
                ),
                const SizedBox(height: 8),
                ..._vigilReadingCtrls.asMap().entries.map((entry) {
                  final i = entry.key;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(4)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text('Reading ${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.stone))),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.redAccent),
                            onPressed: () => setState(() {
                              _vigilReadingCtrls.removeAt(i);
                              _vigilPsalmCtrls.removeAt(i);
                              _vigilPsalmResponseCtrls.removeAt(i);
                            }),
                          ),
                        ]),
                        TextField(controller: _vigilReadingCtrls[i], maxLines: 2, decoration: const InputDecoration(labelText: 'Reading citation')),
                        const SizedBox(height: 6),
                        TextField(controller: _vigilPsalmCtrls[i], decoration: const InputDecoration(labelText: 'Psalm citation (optional)')),
                        const SizedBox(height: 6),
                        TextField(controller: _vigilPsalmResponseCtrls[i], decoration: const InputDecoration(labelText: 'Psalm response (optional)')),
                      ],
                    ),
                  );
                }),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                  onPressed: () => setState(() {
                    _vigilReadingCtrls.add(TextEditingController());
                    _vigilPsalmCtrls.add(TextEditingController());
                    _vigilPsalmResponseCtrls.add(TextEditingController());
                  }),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add Another Reading', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _field(_gospelAcclamationCtrl, 'Gospel Acclamation'),
          _field(_gospelCtrl, 'Gospel', maxLines: 4, required: true),
          Row(children: [
            Expanded(child: _field(_verseForTheDayCtrl, 'Verse for the Day')),
            const SizedBox(width: 8),
            Expanded(child: _field(_verseForTheDayCitationCtrl, 'Citation', )),
          ]),
          _field(_reflectionTitleCtrl, 'Reflection Title (optional)'),
          _field(_reflectionBodyCtrl, 'Reflection', maxLines: 5),
          _field(_themedBoxTitleCtrl, 'Second Themed Box Title (optional)', ),
          _field(_themedBoxBodyCtrl, 'Second Themed Box Body', maxLines: 4),
          _field(_prayersIntroCtrl, 'Prayers of the Faithful — Intro', maxLines: 2),
          _field(_prayersResponseCtrl, 'Response (e.g. "Lord, hear our prayer")'),
          const Text('Petitions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ..._petitionCtrls.asMap().entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 4),
            child: Row(children: [
              Expanded(child: TextField(controller: entry.value, maxLines: 2, decoration: InputDecoration(labelText: 'Petition ${entry.key + 1}'))),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.redAccent),
                onPressed: () => setState(() => _petitionCtrls.removeAt(entry.key)),
              ),
            ]),
          )),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => setState(() => _petitionCtrls.add(TextEditingController())),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add Petition', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 8),
          _field(_prayersClosingCtrl, 'Closing Prayer', maxLines: 2),
          _field(_communionAntiphonCtrl, 'Communion Antiphon', maxLines: 2),
          _field(_sourceCtrl, 'Source', ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Reading'),
          ),
        ],
      ),
    );
  }
}

/// Links two passages by book+chapter - deliberately chapter-level, not
/// verse-level, to keep this simple and actually usable. Loads the same
/// manifest already used by BibleManagementSection for real book
/// dropdowns, not free-typed codes.
class CrossReferencesSection extends StatefulWidget {
  const CrossReferencesSection();

  @override
  State<CrossReferencesSection> createState() => _CrossReferencesSectionState();
}

class _CrossReferencesSectionState extends State<CrossReferencesSection> {
  List<Map<String, dynamic>> _manifestBooks = [];
  late Future<List<Map<String, dynamic>>> _refsFuture;
  bool _showForm = false;

  String? _fromBook, _toBook;
  int? _fromChapter, _toChapter;
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _refsFuture = FirestoreService().getAllBibleCrossReferences();
    _loadManifest();
  }

  Future<void> _loadManifest() async {
    final raw = await rootBundle.loadString('assets/bible/manifest.json');
    final manifest = json.decode(raw) as Map<String, dynamic>;
    if (mounted) setState(() { _manifestBooks = (manifest['books'] as List).cast<Map<String, dynamic>>(); });
  }

  void _refresh() => setState(() { _refsFuture = FirestoreService().getAllBibleCrossReferences(); });

  String _bookName(String? code) => _manifestBooks.firstWhere((b) => b['code'] == code, orElse: () => {'name': code ?? ''})['name'];

  int? _chapterCountFor(String? code) {
    if (code == null) return null;
    return _manifestBooks.firstWhere((b) => b['code'] == code, orElse: () => {})['chapters'] as int?;
  }

  Future<void> _save() async {
    if (_fromBook == null || _fromChapter == null || _toBook == null || _toChapter == null) return;
    setState(() { _saving = true; });
    try {
      await FirestoreService().addBibleCrossReference(
        fromBookCode: _fromBook!, fromChapter: _fromChapter!,
        toBookCode: _toBook!, toChapter: _toChapter!,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      setState(() { _showForm = false; _fromBook = null; _fromChapter = null; _toBook = null; _toChapter = null; _noteCtrl.clear(); });
      _refresh();
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  Widget _bookChapterPicker({
    required String label, required String? selectedBook, required int? selectedChapter,
    required ValueChanged<String?> onBookChanged, required ValueChanged<int?> onChapterChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Row(children: [
          Expanded(
            child: DropdownButton<String>(
              value: selectedBook, isExpanded: true,
              hint: const Text('Book', style: TextStyle(fontSize: 12)),
              items: _manifestBooks.map((b) => DropdownMenuItem(value: b['code'] as String, child: Text(b['name'] ?? ''))).toList(),
              onChanged: onBookChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<int>(
              value: selectedChapter, isExpanded: true,
              hint: const Text('Ch.', style: TextStyle(fontSize: 12)),
              items: _chapterCountFor(selectedBook) == null
                  ? []
                  : List.generate(_chapterCountFor(selectedBook)!, (i) => i + 1).map((c) => DropdownMenuItem(value: c, child: Text('$c'))).toList(),
              onChanged: onChapterChanged,
            ),
          ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _refsFuture,
          builder: (context, snap) {
            final refs = snap.data ?? [];
            if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            if (refs.isEmpty) return const Text('No cross-references added yet.', style: TextStyle(fontSize: 12, color: Colors.black54));
            return Column(
              children: refs.map((r) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${_bookName(r['fromBookCode'])} ${r['fromChapter']}  →  ${_bookName(r['toBookCode'])} ${r['toChapter']}', style: const TextStyle(fontSize: 13)),
                subtitle: r['note'] != null ? Text(r['note'], style: const TextStyle(fontSize: 11)) : null,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  onPressed: () async { await FirestoreService().deleteBibleCrossReference(r['id']); _refresh(); },
                ),
              )).toList(),
            );
          },
        ),
        const SizedBox(height: 8),
        if (!_showForm)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: () => setState(() => _showForm = true),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Link Two Passages'),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.paperDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(child: Text('Link Two Passages', style: TextStyle(fontFamily: appSerif, fontSize: 14))),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _showForm = false)),
                ]),
                const SizedBox(height: 8),
                _bookChapterPicker(
                  label: 'From', selectedBook: _fromBook, selectedChapter: _fromChapter,
                  onBookChanged: (v) => setState(() { _fromBook = v; _fromChapter = null; }),
                  onChapterChanged: (v) => setState(() => _fromChapter = v),
                ),
                const SizedBox(height: 8),
                _bookChapterPicker(
                  label: 'To', selectedBook: _toBook, selectedChapter: _toChapter,
                  onBookChanged: (v) => setState(() { _toBook = v; _toChapter = null; }),
                  onChapterChanged: (v) => setState(() => _toChapter = v),
                ),
                const SizedBox(height: 8),
                TextField(controller: _noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Prophecy fulfilled'), maxLines: 2),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Link'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Read-only, deliberately - there's no edit or delete anywhere in this
/// widget, matching the rule which permits neither for anyone.
class _AuditLogSection extends StatelessWidget {
  const _AuditLogSection();

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: AuditLogService().getRecentLogs(limit: 50),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
        final logs = snap.data ?? [];
        if (logs.isEmpty) return const Text('No audit entries yet.', style: TextStyle(fontSize: 12, color: Colors.black54));
        return Column(
          children: logs.map((l) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.circle, size: 6, color: AppColors.brass),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l['action'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(
                        '${l['actorEmail'] ?? l['actorUid'] ?? ''}${l['detail'] != null ? ' → ${l['detail']}' : ''}',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Text(_timeAgo(l['timestamp'] as Timestamp?), style: const TextStyle(fontSize: 10, color: Colors.black38)),
              ],
            ),
          )).toList(),
        );
      },
    );
  }
}