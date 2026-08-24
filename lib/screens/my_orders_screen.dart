import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  // Same status values and method-aware wording the Admin Panel already
  // uses (see _MarketplaceOrdersAdminSectionState) - kept consistent so
  // "Mark Dispatched" in the admin's view and what the buyer reads here
  // are describing the same thing in the same words.
  String _fulfillmentLabel(String? method, String? status) {
    final isCourier = method == 'courier';
    switch (status) {
      case 'ready':
        return isCourier ? 'Dispatched' : 'Ready for Pickup';
      case 'completed':
        return isCourier ? 'Delivered' : 'Collected';
      default:
        return isCourier ? 'Preparing for dispatch' : 'Preparing for pickup';
    }
  }


  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getMyOrders(AuthService().currentUser?.uid ?? '');
  }

  void _refresh() => setState(() { _future = FirestoreService().getMyOrders(AuthService().currentUser?.uid ?? ''); });

  Future<void> _requestRefund(Map<String, dynamic> order) async {
    final reasonCtrl = TextEditingController();
    final refundPercent = (order['refundPercent'] as num?)?.toDouble() ?? 0;
    if (refundPercent <= 0) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('No Refund Policy'),
          content: const Text('This seller doesn\'t offer refunds on this item. Contact them directly if there\'s an issue.', style: TextStyle(fontSize: 13)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Request Refund', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This seller refunds $refundPercent% — you\'d receive R${((order['finalAmount'] as num) * (refundPercent / 100)).toStringAsFixed(2)}.', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(controller: reasonCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirestoreService().requestRefund(
        parishId: order['parishId'], churchId: order['churchId'], productId: order['productId'], orderId: order['id'],
        finalAmount: (order['finalAmount'] as num).toDouble(), refundPercent: refundPercent,
        reason: reasonCtrl.text.trim(),
      );
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
                  const Text('My Orders', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AsyncSection<List<Map<String, dynamic>>>(
                  future: _future,
                  isEmpty: (l) => l.isEmpty,
                  emptyMessage: 'No orders yet.',
                  builder: (context, orders) => ListView.builder(
                    itemCount: orders.length,
                    itemBuilder: (context, i) {
                      final o = orders[i];
                      final status = o['status'] as String? ?? 'awaiting_payment';
                      final refundStatus = o['refundStatus'] as String?;
                      final canRequestRefund = status == 'approved' && refundStatus == null;
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
                            Text('R${(o['finalAmount'] as num?)?.toStringAsFixed(2) ?? '0.00'}', style: const TextStyle(fontSize: 13, color: AppColors.brass, fontWeight: FontWeight.w600)),
                            if (refundStatus != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Refund: $refundStatus', style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
                              ),
                            if (status == 'approved' && o['fulfillmentMethod'] != null) ...[
                              const SizedBox(height: 6),
                              Row(children: [
                                Icon(o['fulfillmentMethod'] == 'courier' ? Icons.local_shipping_outlined : Icons.storefront_outlined, size: 14, color: AppColors.stone),
                                const SizedBox(width: 6),
                                Text(_fulfillmentLabel(o['fulfillmentMethod'], o['fulfillmentStatus']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                              if (o['fulfillmentMethod'] == 'courier' && (o['deliveryAddress'] as String?)?.isNotEmpty == true)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text('Delivering to: ${o['deliveryAddress']}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                ),
                            ],
                            if (((o['fulfillmentUpdates'] as List?) ?? []).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text('Delivery Updates', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone)),
                              ...(o['fulfillmentUpdates'] as List).map((u) {
                                final m = u as Map;
                                final ts = m['createdAt'];
                                final when = ts is Timestamp ? DateFormat('d MMM, HH:mm').format(ts.toDate()) : '';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text('• ${m['note'] ?? ''} · $when', style: const TextStyle(fontSize: 11)),
                                );
                              }),
                            ],
                            if (canRequestRefund)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                                  onPressed: () => _requestRefund(o),
                                  child: const Text('Request Refund', style: TextStyle(fontSize: 12)),
                                ),
                              ),
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