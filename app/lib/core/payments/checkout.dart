/// Razorpay checkout wrapper.
///
/// Native uses the `razorpay_flutter` plugin; web gets a stub whose
/// [Checkout.isSupported] is false, so the payment screen routes UPI payments
/// through the backend's sandbox-confirm path instead of opening a checkout UI.
library;

export 'checkout_types.dart';
export 'checkout_stub.dart' if (dart.library.io) 'checkout_io.dart';
