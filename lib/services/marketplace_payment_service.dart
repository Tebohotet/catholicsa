import 'package:cloud_functions/cloud_functions.dart';
import 'firestore_service.dart';

/// Real online checkout for parishes that have configured PayFast in
/// Payment Gateway Settings (see payment_gateway_settings_screen.dart) -
/// everything else (bank deposit, PayStack, PayPal) is untouched and
/// still goes through the existing manual flow in PurchaseDialog.
///
/// The actual signature-building, PayFast redirect, and ITN (webhook)
/// verification all live server-side in functions/index.js
/// (createPayfastPayment, payfastNotify) - never in the app. That's not
/// just tidiness: PayFast's passphrase (if a parish sets one) has to
/// stay out of the client entirely for the webhook signature check to
/// mean anything, so this file is deliberately a thin wrapper around one
/// callable, not where any of the real logic happens.
extension MarketplacePaymentService on FirestoreService {
  /// Returns a ready-to-open PayFast checkout URL for [orderId] (an
  /// order already created via createOrder(), still 'awaiting_payment').
  /// Throws if the signed-in user isn't that order's buyer, the order's
  /// already past awaiting_payment, or the parish hasn't set up PayFast -
  /// see createPayfastPayment in functions/index.js for the exact checks.
  Future<String> createPayfastPayment({
    required String parishId,
    required String churchId,
    required String productId,
    required String orderId,
  }) async {
    final result = await FirebaseFunctions.instance.httpsCallable('createPayfastPayment').call({
      'parishId': parishId, 'churchId': churchId, 'productId': productId, 'orderId': orderId,
    });
    return result.data['url'] as String;
  }
}
