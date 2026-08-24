import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../widgets/admin_crud_section.dart';
import '../widgets/super_admin_menu_widgets.dart';
import '../theme/app_theme.dart';

class SuperAdminStoreScreen extends StatelessWidget {
  const SuperAdminStoreScreen({super.key});

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
                  const Text('Store', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Store Management', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.percent,
                    title: 'Marketplace Fee',
                    subtitle: 'Platform commission when a parish has no payment gateway of its own.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSectionHost(title: 'Marketplace Fee', child: _MarketplaceFeeSection()))),
                  ),
                  const SizedBox(height: 20),
                  const Text('Store', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.category_outlined,
                    title: 'Items',
                    subtitle: 'Product groups (Bible, Rosary, Candle, etc.) shown across every parish\'s shop.',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSectionHost(title: 'Items', child: _ItemGroupsSection()))),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.local_shipping_outlined,
                    title: 'Deliveries',
                    subtitle: 'Not built yet - no courier integration exists. Tapping this explains that rather than open an empty screen.',
                    onTap: () => _showNotBuiltYet(context, 'Deliveries', 'Courier integration (Bob Go or similar) is listed as pending work - no delivery tracking exists in this app yet. This menu entry is here to show where it will live once it does.'),
                  ),
                  const SizedBox(height: 8),
                  AdminMenuCard(
                    icon: Icons.payments_outlined,
                    title: 'Payments',
                    subtitle: 'Not built yet - no platform-wide payments admin view exists. Tapping this explains that rather than open an empty screen.',
                    onTap: () => _showNotBuiltYet(context, 'Payments', 'Individual orders already show buyer/seller payment and refund status on their own order screens. A single, platform-wide view across every parish\'s payments doesn\'t exist yet - this menu entry is here to show where it will live once it does.'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotBuiltYet(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text('$title - Not Built Yet', style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK'))],
      ),
    );
  }
}

/// Small enough to build fresh here rather than extract from the main
/// panel screen's shared state - avoids touching that already-working
/// screen just to pull three fields and a save button out of it.
class _MarketplaceFeeSection extends StatefulWidget {
  const _MarketplaceFeeSection();

  @override
  State<_MarketplaceFeeSection> createState() => _MarketplaceFeeSectionState();
}

class _MarketplaceFeeSectionState extends State<_MarketplaceFeeSection> {
  final _feePercentCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fee = await FirestoreService().getPlatformFeePercent();
    _feePercentCtrl.text = fee.toString();
    if (mounted) setState(() { _loading = false; });
  }

  @override
  void dispose() {
    _feePercentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_feePercentCtrl.text.trim());
    if (value == null || value < 0 || value > 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a percentage between 0 and 100.')));
      return;
    }
    setState(() { _saving = true; });
    try {
      await FirestoreService().setPlatformFeePercent(value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Platform fee saved.')));
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
        const Text(
          'Applies only when a parish has no gateway of its own configured (payment lands with the platform). '
          'Once a parish/seller has their own PayFast/PayStack/PayPal, use their gateway\'s own commission feature instead.',
          style: TextStyle(fontSize: 11, color: Colors.black45),
        ),
        const SizedBox(height: 10),
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
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Identical spec to the one already live on the main panel screen -
/// same collection, same fields, so nothing about how groups actually
/// work changes, only where the control for it lives.
class _ItemGroupsSection extends StatelessWidget {
  const _ItemGroupsSection();

  @override
  Widget build(BuildContext context) {
    return GenericAdminCrudSection(
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
    );
  }
}