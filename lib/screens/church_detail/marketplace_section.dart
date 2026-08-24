import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin_crud_section.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_section.dart';
import '../../widgets/verified_name.dart';

/// Phase 1 marketplace, deliberately scoped: listings and a way to reach
/// the seller directly, nothing more. No payment collection, no escrow -
/// see the earlier design conversation for exactly why that boundary is
/// intentional, not a missing feature waiting to be added carelessly.
class MarketplaceSection extends StatefulWidget {
  final String parishId;
  final String churchId;
  const MarketplaceSection({super.key, required this.parishId, required this.churchId});

  @override
  State<MarketplaceSection> createState() => _MarketplaceSectionState();
}

class _MarketplaceSectionState extends State<MarketplaceSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().getApprovedProducts(widget.parishId, widget.churchId);
  }

  void _refresh() => setState(() { _future = FirestoreService().getApprovedProducts(widget.parishId, widget.churchId); });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncSection<List<Map<String, dynamic>>>(
          future: _future,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'Nothing listed for sale at this church yet.',
          builder: (context, products) => Column(
            children: products.map((p) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              color: AppColors.paperDark,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p['imageUrl'] != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(p['imageUrl'], width: 64, height: 64, fit: BoxFit.cover),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('R${(p['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}', style: const TextStyle(fontSize: 13, color: AppColors.brass, fontWeight: FontWeight.w600)),
                        if ((p['description'] as String?)?.isNotEmpty ?? false)
                          Text(p['description'], style: const TextStyle(fontSize: 12)),
                        VerifiedName(
                          uid: p['sellerId'] ?? '',
                          name: 'Seller: ${p['sellerName'] ?? ''}',
                          style: const TextStyle(fontSize: 11, color: Colors.black45),
                          kind: 'trustedSeller',
                        ),
                        if (p['sellerId'] == AuthService().currentUser?.uid)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.brass, side: const BorderSide(color: AppColors.brass), visualDensity: VisualDensity.compact),
                              onPressed: () => showDialog(context: context, builder: (_) => MyCouponDialog(parishId: widget.parishId, churchId: widget.churchId, product: p)),
                              icon: const Icon(Icons.local_offer_outlined, size: 13),
                              label: const Text('My Coupons', style: TextStyle(fontSize: 11)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                        onPressed: () => showDialog(context: context, builder: (_) => PurchaseDialog(parishId: widget.parishId, churchId: widget.churchId, product: p)),
                        icon: const Icon(Icons.shopping_bag_outlined, size: 14),
                        label: const Text('Buy', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                        onPressed: () => launchUrl(Uri.parse('https://wa.me/${(p['sellerContact'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')}'), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.chat_bubble_outline, size: 14),
                        label: const Text('Contact', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
          onPressed: () async {
            await showDialog(context: context, builder: (_) => _ListItemDialog(parishId: widget.parishId, churchId: widget.churchId));
            _refresh();
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('List an Item'),
        ),
        const SizedBox(height: 6),
        const Text(
          'Listings need approval before they appear publicly. Payment and delivery are arranged directly with the seller - the app does not handle payment for marketplace listings.',
          style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _ListItemDialog extends StatefulWidget {
  final String parishId;
  final String churchId;
  const _ListItemDialog({required this.parishId, required this.churchId});

  @override
  State<_ListItemDialog> createState() => _ListItemDialogState();
}

class _ListItemDialogState extends State<_ListItemDialog> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  Uint8List? _pickedImageBytes;
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _refundPercentCtrl = TextEditingController(text: '0');
  String _fulfillmentMethod = 'pickup';
  String? _selectedGroupId;
  late Future<List<Map<String, dynamic>>> _groupsFuture;
  bool _submitting = false;
  bool _signingIn = false;
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = AuthService().currentUser;
    if (_user != null) _nameCtrl.text = _user!.displayName ?? '';
    _groupsFuture = FirestoreService().getProductGroups();
  }

  Future<void> _signIn() async {
    setState(() { _signingIn = true; });
    try {
      final user = await AuthService().signInWithGoogle();
      if (user != null && mounted) {
        setState(() { _user = user; _nameCtrl.text = user.displayName ?? ''; });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() { _signingIn = false; });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _refundPercentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final price = double.tryParse(_priceCtrl.text.trim());
    if (_titleCtrl.text.trim().isEmpty || price == null || _nameCtrl.text.trim().isEmpty || _contactCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in the item name, a valid price, your name, and a contact number.')));
      return;
    }
    setState(() { _submitting = true; });
    try {
      final productId = await FirestoreService().submitProduct(
        parishId: widget.parishId, churchId: widget.churchId,
        title: _titleCtrl.text.trim(), description: _descCtrl.text.trim(), price: price,
        sellerName: _nameCtrl.text.trim(), sellerContact: _contactCtrl.text.trim(),
        fulfillmentMethod: _fulfillmentMethod,
        refundPercent: double.tryParse(_refundPercentCtrl.text.trim()) ?? 0,
        groupId: _selectedGroupId,
      );
      if (_pickedImageBytes != null) {
        await FirestoreService().uploadProductImage(
          parishId: widget.parishId, churchId: widget.churchId, productId: productId, bytes: _pickedImageBytes!,
        );
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(content: Text('Listed — it will appear once approved by the parish.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not list item: $e')));
    } finally {
      if (mounted) setState(() { _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('List an Item', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: const Text('Sign in first so this listing is tied to your account.', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _signingIn ? null : _signIn,
            icon: _signingIn
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.login, size: 16),
            label: const Text('Sign in with Google'),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: const Text('List an Item', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_pickedImageBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(_pickedImageBytes!, height: 120, width: double.infinity, fit: BoxFit.cover),
                ),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
                if (result != null && result.files.isNotEmpty && result.files.single.bytes != null) {
                  setState(() { _pickedImageBytes = result.files.single.bytes; });
                }
              },
              icon: const Icon(Icons.add_a_photo_outlined, size: 16),
              label: Text(_pickedImageBytes == null ? 'Add a Photo' : 'Change Photo', style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 10),
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Item name', hintText: 'e.g. Rosary')),
            const SizedBox(height: 10),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _groupsFuture,
              builder: (context, snap) {
                final groups = snap.data ?? [];
                if (groups.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButton<String?>(
                    value: _selectedGroupId,
                    isExpanded: true,
                    hint: const Text('Category (optional)', style: TextStyle(fontSize: 13)),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('No category')),
                      ...groups.map((g) => DropdownMenuItem<String?>(value: g['id'] as String, child: Text(g['name'] ?? ''))),
                    ],
                    onChanged: (v) => setState(() => _selectedGroupId = v),
                  ),
                );
              },
            ),
            TextField(controller: _descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (optional)')),
            const SizedBox(height: 10),
            TextField(controller: _priceCtrl, decoration: const InputDecoration(labelText: 'Price (ZAR)', prefixText: 'R '), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 10),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Your name')),
            const SizedBox(height: 10),
            TextField(controller: _contactCtrl, decoration: const InputDecoration(labelText: 'WhatsApp/contact number', hintText: 'e.g. 0821234567'), keyboardType: TextInputType.phone),
            const SizedBox(height: 14),
            const Text('How will the buyer get this item?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            DropdownButton<String>(
              value: _fulfillmentMethod, isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'pickup', child: Text('Buyer collects in person')),
                DropdownMenuItem(value: 'courier', child: Text('Courier (buyer provides delivery address)')),
              ],
              onChanged: (v) => setState(() => _fulfillmentMethod = v!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _refundPercentCtrl,
              decoration: const InputDecoration(labelText: 'Refund policy (% refundable if returned)', suffixText: '%'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit Listing'),
        ),
      ],
    );
  }
}

/// Two steps in one dialog: place the order (quantity, coupon, buyer
/// details), then - only for bank_deposit, the one method available while
/// there's no real checkout - show where to pay and let them attach proof
/// once they have. Admin approves from the Marketplace Orders section.
class PurchaseDialog extends StatefulWidget {
  final String parishId;
  final String churchId;
  final Map<String, dynamic> product;
  const PurchaseDialog({super.key, required this.parishId, required this.churchId, required this.product});

  @override
  State<PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<PurchaseDialog> {
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _couponCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  int _quantity = 1;
  Map<String, dynamic>? _appliedCoupon;
  String? _couponError;
  bool _checkingCoupon = false;
  bool _placingOrder = false;
  bool _uploadingProof = false;

  // Step 2 state, populated once the order's placed.
  String? _orderId;
  Map<String, dynamic>? _bankDetails;

  double get _unitPrice => (widget.product['price'] as num?)?.toDouble() ?? 0;
  double get _originalAmount => _unitPrice * _quantity;
  double get _discountAmount {
    if (_appliedCoupon == null) return 0;
    final value = (_appliedCoupon!['discountValue'] as num?)?.toDouble() ?? 0;
    if (_appliedCoupon!['discountType'] == 'percent') return _originalAmount * (value / 100);
    return value.clamp(0, _originalAmount);
  }
  double get _finalAmount => _originalAmount - _discountAmount;

  @override
  void initState() {
    super.initState();
    final user = AuthService().currentUser;
    if (user != null) _nameCtrl.text = user.displayName ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _couponCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyCoupon() async {
    if (_couponCtrl.text.trim().isEmpty) return;
    setState(() { _checkingCoupon = true; _couponError = null; });
    final coupon = await FirestoreService().validateCoupon(widget.parishId, _couponCtrl.text.trim(), productId: widget.product['id']);
    if (mounted) {
      setState(() {
        _checkingCoupon = false;
        _appliedCoupon = coupon;
        _couponError = coupon == null ? 'Invalid or expired code' : null;
      });
    }
  }

  Future<void> _placeOrder() async {
    if (AuthService().currentUser == null) {
      try {
        await AuthService().signInWithGoogle();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
        return;
      }
    }
    if (!mounted) return;
    if (_nameCtrl.text.trim().isEmpty || _contactCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in your name and contact number.')));
      return;
    }
    final fulfillmentMethod = widget.product['fulfillmentMethod'] ?? 'pickup';
    if (fulfillmentMethod == 'courier' && _addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide a delivery address.')));
      return;
    }
    setState(() { _placingOrder = true; });
    try {
      final provider = await FirestoreService().getPublicPaymentProvider(widget.parishId);
      final orderId = await FirestoreService().createOrder(
        parishId: widget.parishId, churchId: widget.churchId,
        productId: widget.product['id'], productTitle: widget.product['title'] ?? '', sellerId: widget.product['sellerId'],
        quantity: _quantity, originalAmount: _originalAmount, discountAmount: _discountAmount, finalAmount: _finalAmount,
        couponCode: _appliedCoupon?['code'],
        buyerName: _nameCtrl.text.trim(), buyerContact: _contactCtrl.text.trim(),
        fulfillmentMethod: fulfillmentMethod,
        deliveryAddress: fulfillmentMethod == 'courier' ? _addressCtrl.text.trim() : null,
        refundPercent: (widget.product['refundPercent'] as num?)?.toDouble() ?? 0,
        sellerHasOwnGateway: provider != 'platform',
      );
      final bank = await FirestoreService().getBankDetails(widget.parishId);
      if (mounted) setState(() { _orderId = orderId; _bankDetails = bank; _placingOrder = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _placingOrder = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not place order: $e')));
      }
    }
  }

  Future<void> _uploadProof() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || _orderId == null) return;
    final file = result.files.single;
    if (file.bytes == null) return;
    setState(() { _uploadingProof = true; });
    try {
      await FirestoreService().uploadProofOfPayment(
        parishId: widget.parishId, churchId: widget.churchId,
        productId: widget.product['id'], orderId: _orderId!,
        bytes: file.bytes!, fileName: file.name,
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(content: Text('Proof of payment uploaded — the parish will confirm it shortly.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() { _uploadingProof = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_orderId != null) {
      // Step 2: pay by bank deposit, then attach proof.
      return AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Pay by Bank Deposit', style: TextStyle(fontFamily: appSerif, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order placed for R${_finalAmount.toStringAsFixed(2)}.', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (_bankDetails == null)
                const Text('This parish hasn\'t set up bank deposit details yet — contact the seller directly to arrange payment.', style: TextStyle(fontSize: 12, color: Colors.black54))
              else ...[
                _bankRow('Account Name', _bankDetails!['accountName'] ?? ''),
                _bankRow('Bank', _bankDetails!['bank'] ?? ''),
                _bankRow('Account Number', _bankDetails!['accountNumber'] ?? ''),
                _bankRow('Branch Code', _bankDetails!['branchCode'] ?? ''),
              ],
              const SizedBox(height: 16),
              const Text('Once you\'ve made the deposit, upload a screenshot or photo of the proof below.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
            onPressed: _uploadingProof ? null : _uploadProof,
            icon: _uploadingProof
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_outlined, size: 16),
            label: const Text('Upload Proof of Payment'),
          ),
        ],
      );
    }

    // Step 1: order details.
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text(widget.product['title'] ?? '', style: const TextStyle(fontFamily: appSerif, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Quantity', style: TextStyle(fontSize: 13)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null),
                Text('$_quantity', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle_outline, size: 20), onPressed: () => setState(() => _quantity++)),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(controller: _couponCtrl, decoration: const InputDecoration(labelText: 'Coupon code (optional)')),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                  onPressed: _checkingCoupon ? null : _applyCoupon,
                  child: _checkingCoupon
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Apply'),
                ),
              ],
            ),
            if (_couponError != null) Text(_couponError!, style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
            if (_appliedCoupon != null) Text('Coupon applied: -R${_discountAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: AppColors.sage, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              color: AppColors.paperDark,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('R${_finalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.brass)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Your name')),
            const SizedBox(height: 10),
            TextField(controller: _contactCtrl, decoration: const InputDecoration(labelText: 'Contact number'), keyboardType: TextInputType.phone),
            if ((widget.product['fulfillmentMethod'] ?? 'pickup') == 'courier') ...[
              const SizedBox(height: 10),
              TextField(controller: _addressCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Delivery address')),
            ] else ...[
              const SizedBox(height: 8),
              const Text('This item is collected in person from the seller.', style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
            ],
            if (((widget.product['refundPercent'] as num?) ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Refund policy: ${widget.product['refundPercent']}% refundable if returned.',
                  style: const TextStyle(fontSize: 11, color: AppColors.sage, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _placingOrder ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
          onPressed: _placingOrder ? null : _placeOrder,
          child: _placingOrder ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Place Order'),
        ),
      ],
    );
  }
}

Widget _bankRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.black45))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

/// A seller managing coupons for their own listing - same underlying
/// GenericAdminCrudSection used for Saints and parish-wide coupons,
/// scoped here to just this one product via the fetch/add closures.
class MyCouponDialog extends StatelessWidget {
  final String parishId;
  final String churchId;
  final Map<String, dynamic> product;
  const MyCouponDialog({super.key, required this.parishId, required this.churchId, required this.product});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text('Coupons — ${product['title'] ?? ''}', style: const TextStyle(fontFamily: appSerif, fontSize: 17)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: GenericAdminCrudSection(
            spec: AdminCollectionSpec(
              title: 'Coupon',
              icon: Icons.local_offer_outlined,
              fields: const [
                AdminFieldSpec(key: 'code', label: 'Code', required: true, hint: 'e.g. FRIEND10'),
                AdminFieldSpec(key: 'discountType', label: 'Discount type', type: AdminFieldType.dropdown, options: ['percent', 'fixed']),
                AdminFieldSpec(key: 'discountValue', label: 'Discount value', required: true, hint: 'e.g. 10'),
                AdminFieldSpec(key: 'expiresAt', label: 'Expires (YYYY-MM-DD, optional)'),
              ],
              titleBuilder: (c) => c['code'] ?? '',
              subtitleBuilder: (c) {
                final suffix = c['discountType'] == 'percent' ? '%' : ' ZAR';
                return '${c['discountValue'] ?? ''}$suffix off';
              },
              fetchAll: () => FirestoreService().getCouponsForProduct(parishId, product['id']),
              onAdd: (data) => FirestoreService().addProductCoupon(
                parishId: parishId, churchId: churchId, productId: product['id'],
                code: data['code'], discountType: data['discountType'] ?? 'percent',
                discountValue: double.tryParse(data['discountValue'].toString()) ?? 0,
                expiresAt: (data['expiresAt'] as String?)?.isEmpty ?? true ? null : data['expiresAt'],
              ),
              onEdit: (id, data) => FirestoreService().updateCoupon(parishId, id, {
                'code': (data['code'] as String).trim().toUpperCase(),
                'discountType': data['discountType'],
                'discountValue': double.tryParse(data['discountValue'].toString()) ?? 0,
                'expiresAt': (data['expiresAt'] as String?)?.isEmpty ?? true ? null : data['expiresAt'],
              }),
              onDelete: (id) => FirestoreService().deleteCoupon(parishId, id),
              idOf: (c) => c['id'],
            ),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}