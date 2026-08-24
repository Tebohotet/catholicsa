import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';

/// Same gap this closes as My Donations did earlier - a seller could
/// list an item and never see it again to edit or remove it, even
/// though the rule has always supported them doing exactly that.
class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  late Future<List<Map<String, dynamic>>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getMyProducts(AuthService().currentUser?.uid ?? '');
    _groupsFuture = FirestoreService().getProductGroups();
  }

  void _refresh() => setState(() { _future = FirestoreService().getMyProducts(AuthService().currentUser?.uid ?? ''); });

  String _statusLabel(String? status) {
    switch (status) {
      case 'approved':
        return 'Live';
      case 'rejected':
        return 'Rejected / Taken down';
      default:
        return 'Awaiting approval';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'approved':
        return AppColors.sage;
      case 'rejected':
        return Colors.redAccent;
      default:
        return AppColors.stone;
    }
  }

  Future<void> _edit(Map<String, dynamic> product, List<Map<String, dynamic>> groups) async {
    final titleCtrl = TextEditingController(text: product['title'] ?? '');
    final descCtrl = TextEditingController(text: product['description'] ?? '');
    final priceCtrl = TextEditingController(text: (product['price'] as num?)?.toString() ?? '0');
    final refundCtrl = TextEditingController(text: (product['refundPercent'] as num?)?.toString() ?? '0');
    String fulfillmentMethod = product['fulfillmentMethod'] ?? 'pickup';
    String? selectedGroupId = product['groupId'];

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('Edit Listing', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Item name')),
                TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
                TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Price (ZAR)', prefixText: 'R '), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                TextField(controller: refundCtrl, decoration: const InputDecoration(labelText: 'Refund policy (%)'), keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                const Text('How will the buyer get this item?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                DropdownButton<String>(
                  value: fulfillmentMethod, isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
                    DropdownMenuItem(value: 'courier', child: Text('Courier')),
                  ],
                  onChanged: (v) => setDialogState(() => fulfillmentMethod = v!),
                ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  DropdownButton<String?>(
                    value: selectedGroupId,
                    isExpanded: true,
                    hint: const Text('No category', style: TextStyle(fontSize: 13)),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('No category')),
                      ...groups.map((g) => DropdownMenuItem<String?>(value: g['id'] as String, child: Text(g['name'] ?? ''))),
                    ],
                    onChanged: (v) => setDialogState(() => selectedGroupId = v),
                  ),
                ],
                if (product['status'] == 'approved')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('This listing is live - changes apply immediately, no re-approval needed.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
              onPressed: () async {
                final price = double.tryParse(priceCtrl.text.trim());
                if (titleCtrl.text.trim().isEmpty || price == null) return;
                await FirestoreService().updateProduct(
                  parishId: product['parishId'], churchId: product['churchId'], productId: product['id'],
                  title: titleCtrl.text.trim(), description: descCtrl.text.trim(), price: price,
                  fulfillmentMethod: fulfillmentMethod,
                  refundPercent: double.tryParse(refundCtrl.text.trim()) ?? 0,
                  groupId: selectedGroupId,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _refresh();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Delete Listing?', style: TextStyle(fontFamily: appSerif, fontSize: 17)),
        content: Text('"${product['title']}" will be permanently removed. This can\'t be undone.', style: const TextStyle(fontSize: 13)),
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
      await FirestoreService().deleteProduct(product['parishId'], product['churchId'], product['id']);
      _refresh();
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
                  const Text('My Listings', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _groupsFuture,
                  builder: (context, groupsSnap) {
                    final groups = groupsSnap.data ?? [];
                    return AsyncSection<List<Map<String, dynamic>>>(
                      future: _future,
                      isEmpty: (l) => l.isEmpty,
                      emptyMessage: 'You haven\'t listed anything yet.',
                      builder: (context, products) => ListView.builder(
                        itemCount: products.length,
                        itemBuilder: (context, i) {
                          final p = products[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            color: AppColors.paperDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(child: Text(p['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                                  Text('R${(p['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}', style: const TextStyle(fontSize: 13, color: AppColors.brass, fontWeight: FontWeight.w600)),
                                ]),
                                const SizedBox(height: 4),
                                Text(_statusLabel(p['status']), style: TextStyle(fontSize: 12, color: _statusColor(p['status']), fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone), minimumSize: const Size(0, 32)),
                                    onPressed: () => _edit(p, groups),
                                    icon: const Icon(Icons.edit_outlined, size: 14),
                                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent), minimumSize: const Size(0, 32)),
                                    onPressed: () => _delete(p),
                                    icon: const Icon(Icons.delete_outline, size: 14),
                                    label: const Text('Delete', style: TextStyle(fontSize: 12)),
                                  ),
                                ]),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}