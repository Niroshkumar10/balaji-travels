import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'checkout_types.dart';

/// Native Razorpay checkout.
class Checkout {
  const Checkout._();

  static Razorpay? _rz;

  static bool get isSupported => true;

  static void open({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String name,
    required String description,
    required void Function(CheckoutResult result) onSuccess,
    required void Function(String message) onError,
  }) {
    _rz?.clear();
    _rz = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
        onSuccess(CheckoutResult(
          orderId: r.orderId ?? orderId,
          paymentId: r.paymentId ?? '',
          signature: r.signature ?? '',
        ));
      })
      ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
        onError(r.message ?? 'Payment failed');
      });

    _rz!.open({
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': name,
      'description': description,
    });
  }

  static void dispose() {
    _rz?.clear();
    _rz = null;
  }
}
