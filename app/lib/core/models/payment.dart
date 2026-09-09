import 'json.dart';

class PaymentInfo {
  const PaymentInfo({
    required this.id,
    required this.method,
    required this.amount,
    required this.status,
    this.gateway,
    this.paidAt,
  });

  final int id;
  final String method; // cash | upi | card | wallet
  final double amount;
  final String status; // pending | authorized | paid | failed | refunded
  final String? gateway;
  final DateTime? paidAt;

  bool get isPaid => status == 'paid';

  factory PaymentInfo.fromJson(Map<String, dynamic> j) => PaymentInfo(
        id: asInt(j['id']),
        method: j['method']?.toString() ?? 'cash',
        amount: asDouble(j['amount']),
        status: j['status']?.toString() ?? 'pending',
        gateway: j['gateway']?.toString(),
        paidAt: asDate(j['paid_at']),
      );
}

/// Response of `POST /payments/rides/:id/order`.
class GatewayOrder {
  const GatewayOrder({
    required this.paymentId,
    required this.orderId,
    required this.amountPaise,
    this.keyId,
    this.stub = false,
  });

  final int paymentId;
  final String orderId;
  final int amountPaise;
  final String? keyId;
  final bool stub;

  factory GatewayOrder.fromJson(Map<String, dynamic> j) {
    final o = asMap(j['order']);
    return GatewayOrder(
      paymentId: asInt(j['paymentId']),
      orderId: o['id']?.toString() ?? '',
      amountPaise: asInt(o['amount']),
      keyId: j['keyId']?.toString(),
      stub: asBool(j['stub']),
    );
  }
}
