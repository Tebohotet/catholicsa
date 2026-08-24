import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';

/// Where a seller who's delivering an item themselves (rather than a real
/// courier company) posts proof at each step - packed, on the way,
/// delivered - since there's no real courier tracking system to lean on
/// for a self-delivery. The buyer sees the same log in My Orders.
class MySalesScreen extends StatefulWidget {
  const MySalesScreen({super.key});

  @override
  State<MySalesScreen> createState() => _MySalesScreenState();
}

class _MySalesScreenState extends State<MySalesScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getMySales(AuthService().currentUser?.uid ?? '');
  }

  void _refresh() => setState(() { _future = FirestoreService().getMySales(AuthService().currentUser?.uid ?? ''); });

  // A self-couriering seller is the one actually delivering the item, so
  // they - not the parish office - should be the one who marks it
  // dispatched/delivered. Same fulfillmentStatus values and method the
  // Admin Panel uses for the pickup case, just triggered from the
  // person who's actually doing the work for a courier order.
  Widget _sellerFulfillmentButton(Map<String, dynamic> order) {
    final status = order['fulfillmentStatus'] as String? ?? 'pending';
    if (status == 'completed') {
      return const Text('Marked as delivered', style: TextStyle(fontSize: 12, color: AppColors.sage, fontWeight: FontWeight.w600));
    }
    final nextStatus = status == 'ready' ? 'completed' : 'ready';
    final label = status == 'ready' ? 'Mark Delivered' : 'Mark Dispatched';
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.sage, side: const BorderSide(color: AppColors.sage)),
      onPressed: () async {
        await FirestoreService().updateOrderFulfillmentStatus(
          parishId: order['parishId'], churchId: order['churchId'],
          productId: order['productId'], orderId: order['id'], fulfillmentStatus: nextStatus,
        );
        _refresh();
      },
      icon: const Icon(Icons.local_shipping_outlined, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
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
                  const Text('My Sales', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AsyncSection<List<Map<String, dynamic>>>(
                  future: _future,
                  isEmpty: (l) => l.isEmpty,
                  emptyMessage: 'No sales yet.',
                  builder: (context, orders) => ListView.builder(
                    itemCount: orders.length,
                    itemBuilder: (context, i) {
                      final o = orders[i];
                      final status = o['status'] as String? ?? 'awaiting_payment';
                      final method = o['fulfillmentMethod'] ?? 'pickup';
                      final updates = (o['fulfillmentUpdates'] as List?) ?? [];
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
                            if (method == 'courier' && (o['deliveryAddress'] as String?)?.isNotEmpty == true)
                              Text('Deliver to: ${o['deliveryAddress']}', style: const TextStyle(fontSize: 12)),
                            if (status == 'approved' && method == 'courier') ...[
                              const SizedBox(height: 10),
                              if (updates.isNotEmpty) ...[
                                const Text('Delivery Log', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone)),
                                ...updates.map((u) {
                                  final m = u as Map;
                                  final ts = m['createdAt'];
                                  final when = ts is Timestamp ? DateFormat('d MMM, HH:mm').format(ts.toDate()) : '';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.circle, size: 6, color: AppColors.brass),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('${m['note'] ?? ''} · $when', style: const TextStyle(fontSize: 11)),
                                              if (m['photoUrl'] != null)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(4),
                                                    child: Image.network(m['photoUrl'], height: 60, width: 60, fit: BoxFit.cover),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 6),
                              ],
                              _sellerFulfillmentButton(o),
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                                onPressed: () async {
                                  await showDialog(context: context, builder: (_) => _AddUpdateDialog(order: o));
                                  _refresh();
                                },
                                icon: const Icon(Icons.add_location_alt_outlined, size: 14),
                                label: const Text('Add Delivery Update', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddUpdateDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  const _AddUpdateDialog({required this.order});

  @override
  State<_AddUpdateDialog> createState() => _AddUpdateDialogState();
}

class _AddUpdateDialogState extends State<_AddUpdateDialog> {
  final _noteCtrl = TextEditingController();
  String? _pickedFileName;
  List<int>? _pickedBytes;
  bool _submitting = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;
    setState(() {
      _pickedFileName = result.files.single.name;
      _pickedBytes = result.files.single.bytes;
    });
  }

  Future<void> _submit() async {
    if (_noteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a short note, e.g. "Packed and ready" or "On the way".')));
      return;
    }
    setState(() { _submitting = true; });
    try {
      String? photoUrl;
      if (_pickedBytes != null && _pickedFileName != null) {
        photoUrl = await FirestoreService().uploadFulfillmentProofPhoto(
          parishId: widget.order['parishId'], churchId: widget.order['churchId'],
          orderId: widget.order['id'], bytes: Uint8List.fromList(_pickedBytes!), fileName: _pickedFileName!,
        );
      }
      await FirestoreService().addFulfillmentUpdate(
        parishId: widget.order['parishId'], churchId: widget.order['churchId'],
        productId: widget.order['productId'], orderId: widget.order['id'],
        note: _noteCtrl.text.trim(), photoUrl: photoUrl,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add update: $e')));
    } finally {
      if (mounted) setState(() { _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('Add Delivery Update', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(controller: _noteCtrl, decoration: const InputDecoration(labelText: 'Update', hintText: 'e.g. Packed, On the way, Delivered'), maxLines: 2),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
            onPressed: _pickPhoto,
            icon: const Icon(Icons.camera_alt_outlined, size: 16),
            label: Text(_pickedFileName ?? 'Attach Photo (optional)', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Post Update'),
        ),
      ],
    );
  }
}