import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/verified_name.dart';
import 'church_detail/marketplace_section.dart';

/// Where tapping an item anywhere it's listed (Shop, national Browse
/// rollups) should actually go - a real page with the full picture and
/// real actions, not just a static row in a list. Reuses PurchaseDialog
/// and MyCouponDialog directly rather than rebuilding the purchase flow
/// a second time.
class ProductDetailScreen extends StatelessWidget {
  final String parishId;
  final String churchId;
  final Map<String, dynamic> product;
  const ProductDetailScreen({super.key, required this.parishId, required this.churchId, required this.product});

  @override
  Widget build(BuildContext context) {
    final isMine = product['sellerId'] == AuthService().currentUser?.uid;
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
                  Expanded(child: Text(product['title'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 20, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (product['imageUrl'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(product['imageUrl'], width: double.infinity, height: 220, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 16),
                  Text(product['title'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 22)),
                  const SizedBox(height: 6),
                  Text('R${(product['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}', style: const TextStyle(fontSize: 18, color: AppColors.brass, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if ((product['description'] as String?)?.isNotEmpty ?? false)
                    Text(product['description'], style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  VerifiedName(
                    uid: product['sellerId'] ?? '',
                    name: 'Seller: ${product['sellerName'] ?? ''}',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                    kind: 'trustedSeller',
                  ),
                  if (product['churchName'] != null) ...[
                    const SizedBox(height: 4),
                    Text('At: ${product['churchName']}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                          onPressed: () => showDialog(context: context, builder: (_) => PurchaseDialog(parishId: parishId, churchId: churchId, product: product)),
                          icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                          label: const Text('Buy'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                          onPressed: () => launchUrl(
                            Uri.parse('https://wa.me/${(product['sellerContact'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')}'),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.chat_bubble_outline, size: 16),
                          label: const Text('Contact'),
                        ),
                      ),
                    ],
                  ),
                  if (isMine) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.brass, side: const BorderSide(color: AppColors.brass)),
                      onPressed: () => showDialog(context: context, builder: (_) => MyCouponDialog(parishId: parishId, churchId: churchId, product: product)),
                      icon: const Icon(Icons.local_offer_outlined, size: 16),
                      label: const Text('My Coupons'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}