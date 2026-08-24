import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_crud_section.dart';

/// Settings only - this does NOT process a payment. Wiring an actual
/// checkout (redirecting to PayFast/PayStack/PayPal, verifying the
/// webhook/ITN callback, confirming funds actually arrived) is separate,
/// gateway-specific integration work that needs real sandbox credentials
/// to build and test properly. What this screen gets right: where the
/// money should go, stored somewhere only this parish's priest (or a
/// super admin) can ever read - never the public parish document, never
/// re-displayed once a secret's been saved.
class PaymentGatewaySettingsScreen extends StatefulWidget {
  final String parishId;
  const PaymentGatewaySettingsScreen({super.key, required this.parishId});

  @override
  State<PaymentGatewaySettingsScreen> createState() => _PaymentGatewaySettingsScreenState();
}

class _PaymentGatewaySettingsScreenState extends State<PaymentGatewaySettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String _provider = 'platform'; // platform | payfast | paystack | paypal
  bool _hasExistingSecrets = false;

  final _payfastMerchantIdCtrl = TextEditingController();
  final _payfastMerchantKeyCtrl = TextEditingController();
  final _paystackPublicKeyCtrl = TextEditingController();
  final _paystackSecretKeyCtrl = TextEditingController();
  final _paypalClientIdCtrl = TextEditingController();
  final _paypalClientSecretCtrl = TextEditingController();

  final _bankAccountNameCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _bankAccountNumberCtrl = TextEditingController();
  final _bankBranchCodeCtrl = TextEditingController();
  bool _savingBankDetails = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await FirestoreService().getPaymentGatewayConfig(widget.parishId);
    if (config != null) {
      _provider = config['provider'] ?? 'platform';
      _payfastMerchantIdCtrl.text = config['payfastMerchantId'] ?? '';
      _paystackPublicKeyCtrl.text = config['paystackPublicKey'] ?? '';
      _paypalClientIdCtrl.text = config['paypalClientId'] ?? '';
      _hasExistingSecrets = (config['payfastMerchantKey'] != null) ||
          (config['paystackSecretKey'] != null) || (config['paypalClientSecret'] != null);
    }
    final bank = await FirestoreService().getBankDetails(widget.parishId);
    if (bank != null) {
      _bankAccountNameCtrl.text = bank['accountName'] ?? '';
      _bankNameCtrl.text = bank['bank'] ?? '';
      _bankAccountNumberCtrl.text = bank['accountNumber'] ?? '';
      _bankBranchCodeCtrl.text = bank['branchCode'] ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _payfastMerchantIdCtrl.dispose();
    _payfastMerchantKeyCtrl.dispose();
    _paystackPublicKeyCtrl.dispose();
    _paystackSecretKeyCtrl.dispose();
    _paypalClientIdCtrl.dispose();
    _paypalClientSecretCtrl.dispose();
    _bankAccountNameCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccountNumberCtrl.dispose();
    _bankBranchCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{'provider': _provider};

      if (_provider == 'payfast') {
        data['payfastMerchantId'] = _payfastMerchantIdCtrl.text.trim();
        if (_payfastMerchantKeyCtrl.text.trim().isNotEmpty) {
          data['payfastMerchantKey'] = _payfastMerchantKeyCtrl.text.trim();
        }
      } else if (_provider == 'paystack') {
        data['paystackPublicKey'] = _paystackPublicKeyCtrl.text.trim();
        if (_paystackSecretKeyCtrl.text.trim().isNotEmpty) {
          data['paystackSecretKey'] = _paystackSecretKeyCtrl.text.trim();
        }
      } else if (_provider == 'paypal') {
        data['paypalClientId'] = _paypalClientIdCtrl.text.trim();
        if (_paypalClientSecretCtrl.text.trim().isNotEmpty) {
          data['paypalClientSecret'] = _paypalClientSecretCtrl.text.trim();
        }
      }

      data['escrowEnabled'] = false;

      await FirestoreService().savePaymentGatewayConfig(widget.parishId, data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment settings saved.')));
        _payfastMerchantKeyCtrl.clear();
        _paystackSecretKeyCtrl.clear();
        _paypalClientSecretCtrl.clear();
        setState(() => _hasExistingSecrets = true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveBankDetails() async {
    setState(() => _savingBankDetails = true);
    try {
      await FirestoreService().updateBankDetails(widget.parishId, {
        'accountName': _bankAccountNameCtrl.text.trim(),
        'bank': _bankNameCtrl.text.trim(),
        'accountNumber': _bankAccountNumberCtrl.text.trim(),
        'branchCode': _bankBranchCodeCtrl.text.trim(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bank details saved.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _savingBankDetails = false);
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
                  const Text('Payment Settings', style: TextStyle(fontFamily: appSerif, fontSize: 22, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Choose where payment for anything sold through this parish should go. This saves your settings only - '
                            'connecting an actual checkout screen is separate work still to come.',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          const SizedBox(height: 20),

                          const Text('Payment goes to', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone, letterSpacing: 0.4)),
                          RadioGroup<String>(
                            groupValue: _provider,
                            onChanged: (v) => setState(() => _provider = v!),
                            child: const Column(
                              children: [
                                RadioListTile<String>(
                                  contentPadding: EdgeInsets.zero,
                                  value: 'platform',
                                  title: Text('Platform default', style: TextStyle(fontSize: 14)),
                                  subtitle: Text('No gateway configured - payments are collected by us and forwarded to the parish separately.', style: TextStyle(fontSize: 11)),
                                ),
                                RadioListTile<String>(
                                  contentPadding: EdgeInsets.zero,
                                  value: 'payfast',
                                  title: Text('PayFast', style: TextStyle(fontSize: 14)),
                                ),
                                RadioListTile<String>(
                                  contentPadding: EdgeInsets.zero,
                                  value: 'paystack',
                                  title: Text('PayStack', style: TextStyle(fontSize: 14)),
                                ),
                                RadioListTile<String>(
                                  contentPadding: EdgeInsets.zero,
                                  value: 'paypal',
                                  title: Text('PayPal', style: TextStyle(fontSize: 14)),
                                ),
                              ],
                            ),
                          ),

                          if (_provider == 'payfast') ...[
                            const SizedBox(height: 12),
                            TextField(controller: _payfastMerchantIdCtrl, decoration: const InputDecoration(labelText: 'PayFast Merchant ID')),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _payfastMerchantKeyCtrl, obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'PayFast Merchant Key',
                                hintText: _hasExistingSecrets ? 'Already saved — leave blank to keep it' : null,
                              ),
                            ),
                          ],
                          if (_provider == 'paystack') ...[
                            const SizedBox(height: 12),
                            TextField(controller: _paystackPublicKeyCtrl, decoration: const InputDecoration(labelText: 'PayStack Public Key')),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _paystackSecretKeyCtrl, obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'PayStack Secret Key',
                                hintText: _hasExistingSecrets ? 'Already saved — leave blank to keep it' : null,
                              ),
                            ),
                          ],
                          if (_provider == 'paypal') ...[
                            const SizedBox(height: 12),
                            TextField(controller: _paypalClientIdCtrl, decoration: const InputDecoration(labelText: 'PayPal Client ID')),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _paypalClientSecretCtrl, obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'PayPal Client Secret',
                                hintText: _hasExistingSecrets ? 'Already saved — leave blank to keep it' : null,
                              ),
                            ),
                          ],

                          const SizedBox(height: 28),
                          const Text('Escrow', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone, letterSpacing: 0.4)),
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            color: AppColors.paperDark,
                            child: Row(
                              children: [
                                const Icon(Icons.lock_outline, size: 18, color: Colors.black45),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Hold funds until buyer confirms delivery', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Locked off for now. Holding money on behalf of someone else pending a condition is the kind of thing that needs a real legal answer '
                                        'in South Africa before it\'s switched on - this setting exists so it can be turned on later without rebuilding anything, not because it works today.',
                                        style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.5)),
                                      ),
                                    ],
                                  ),
                                ),
                                const Switch(value: false, onChanged: null, activeThumbColor: AppColors.brass),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.brass),
                              onPressed: _saving ? null : _save,
                              child: _saving
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Save'),
                            ),
                          ),

                          const SizedBox(height: 32),
                          const Text('Bank Deposit Details', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone, letterSpacing: 0.4)),
                          const SizedBox(height: 4),
                          const Text(
                            'Shown to buyers who choose to pay by bank deposit while online checkout isn\'t connected yet.',
                            style: TextStyle(fontSize: 11, color: Colors.black45),
                          ),
                          const SizedBox(height: 10),
                          TextField(controller: _bankAccountNameCtrl, decoration: const InputDecoration(labelText: 'Account Name')),
                          const SizedBox(height: 10),
                          TextField(controller: _bankNameCtrl, decoration: const InputDecoration(labelText: 'Bank')),
                          const SizedBox(height: 10),
                          TextField(controller: _bankAccountNumberCtrl, decoration: const InputDecoration(labelText: 'Account Number')),
                          const SizedBox(height: 10),
                          TextField(controller: _bankBranchCodeCtrl, decoration: const InputDecoration(labelText: 'Branch Code')),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.stone, side: const BorderSide(color: AppColors.stone)),
                              onPressed: _savingBankDetails ? null : _saveBankDetails,
                              child: _savingBankDetails
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Save Bank Details'),
                            ),
                          ),

                          const SizedBox(height: 32),
                          const Text('Coupons', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.stone, letterSpacing: 0.4)),
                          const SizedBox(height: 4),
                          const Text('Usable across any listing from this parish.', style: TextStyle(fontSize: 11, color: Colors.black45)),
                          const SizedBox(height: 10),
                          GenericAdminCrudSection(
                            spec: AdminCollectionSpec(
                              title: 'Coupon',
                              icon: Icons.local_offer_outlined,
                              fields: const [
                                AdminFieldSpec(key: 'code', label: 'Code', required: true, hint: 'e.g. WELCOME10'),
                                AdminFieldSpec(key: 'discountType', label: 'Discount type', type: AdminFieldType.dropdown, options: ['percent', 'fixed']),
                                AdminFieldSpec(key: 'discountValue', label: 'Discount value', required: true, hint: 'e.g. 10 for 10% or R10'),
                                AdminFieldSpec(key: 'expiresAt', label: 'Expires (YYYY-MM-DD, optional)', hint: 'Leave blank for no expiry'),
                                AdminFieldSpec(key: 'active', label: 'Active', type: AdminFieldType.switchBool, defaultValue: true),
                              ],
                              titleBuilder: (c) => c['code'] ?? '',
                              subtitleBuilder: (c) {
                                final type = c['discountType'] == 'fixed' ? 'R' : '';
                                final suffix = c['discountType'] == 'percent' ? '%' : '';
                                final active = c['active'] == true ? 'Active' : 'Inactive';
                                return '$type${c['discountValue'] ?? ''}$suffix off · $active';
                              },
                              fetchAll: () async {
                                final all = await FirestoreService().getCoupons(widget.parishId);
                                return all.where((c) => c['scope'] != 'product').toList();
                              },
                              onAdd: (data) {
                                data['code'] = (data['code'] as String).trim().toUpperCase();
                                data['scope'] = 'parish';
                                return FirestoreService().addCoupon(widget.parishId, data);
                              },
                              onEdit: (id, data) {
                                data['code'] = (data['code'] as String).trim().toUpperCase();
                                return FirestoreService().updateCoupon(widget.parishId, id, data);
                              },
                              onDelete: (id) => FirestoreService().deleteCoupon(widget.parishId, id),
                              idOf: (c) => c['id'],
                            ),
                          ),
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