import '../models/models.dart';
import '../net/api_client.dart';
import '../net/result.dart';

class PaymentRepository {
  PaymentRepository(this._api);
  final ApiClient _api;

  Future<Result<PaymentInfo?>> forRide(int rideId) async {
    final res = await _api.get('/payments/rides/$rideId');
    return res.when<Result<PaymentInfo?>>(
      ok: (j) => Ok(j['payment'] == null ? null : PaymentInfo.fromJson(asMap(j['payment']))),
      err: (e) => Err(e),
    );
  }

  /// Customer: create a gateway order to open Razorpay checkout.
  Future<Result<GatewayOrder>> createOrder(int rideId, {String? idempotencyKey}) async {
    final res = await _api.post(
      '/payments/rides/$rideId/order',
      headers: idempotencyKey == null ? null : {'idempotency-key': idempotencyKey},
    );
    return res.when<Result<GatewayOrder>>(
      ok: (j) => Ok(GatewayOrder.fromJson(j)),
      err: (e) => Err(e),
    );
  }

  /// Customer: confirm after checkout returns a signed payload.
  Future<Result<Map<String, dynamic>>> confirm(
    int rideId, {
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final res = await _api.post('/payments/rides/$rideId/confirm', body: {
      'orderId': orderId,
      'paymentId': paymentId,
      'signature': signature,
    });
    return res.when<Result<Map<String, dynamic>>>(ok: (j) => Ok(j), err: (e) => Err(e));
  }

  /// Driver: confirm cash received.
  Future<Result<Map<String, dynamic>>> settleCash(int rideId) async {
    final res = await _api.post('/payments/rides/$rideId/cash');
    return res.when<Result<Map<String, dynamic>>>(ok: (j) => Ok(j), err: (e) => Err(e));
  }
}
