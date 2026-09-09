import 'checkout_types.dart';

/// Web / no-dart:io build: no native Razorpay SDK.
class Checkout {
  const Checkout._();

  static bool get isSupported => false;

  static void open({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String name,
    required String description,
    required void Function(CheckoutResult result) onSuccess,
    required void Function(String message) onError,
  }) {
    onError('Card/UPI checkout is not available in this build. '
        'Use a mobile build, or pay by cash.');
  }

  static void dispose() {}
}
