import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/payments/checkout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../ride_session_controller.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, required this.rideId});
  final int rideId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rideSessionProvider.notifier).attach(widget.rideId);
    });
  }

  @override
  void dispose() {
    Checkout.dispose();
    super.dispose();
  }

  Future<void> _payByUpi(double amount) async {
    setState(() => _busy = true);
    final res = await ref.read(paymentRepoProvider).createOrder(
          widget.rideId,
          idempotencyKey: 'ride-${widget.rideId}-pay',
        );
    if (!mounted) return;
    setState(() => _busy = false);

    res.when(
      ok: (order) {
        // No real gateway keys (dev/sandbox) OR no native SDK (web) → settle
        // through the backend's stub-confirm path directly.
        if (order.stub || order.keyId == null || !Checkout.isSupported) {
          _confirm(order.orderId, 'pay_sandbox_${DateTime.now().millisecondsSinceEpoch}', '');
          return;
        }
        Checkout.open(
          keyId: order.keyId!,
          orderId: order.orderId,
          amountPaise: order.amountPaise,
          name: 'Sri Balaji Travels',
          description: 'Ride ${widget.rideId}',
          onSuccess: (r) => _confirm(r.orderId, r.paymentId, r.signature),
          onError: (msg) {
            if (mounted) showError(context, msg);
          },
        );
      },
      err: (e) => showError(context, e.message),
    );
  }

  Future<void> _confirm(String orderId, String paymentId, String signature) async {
    setState(() => _busy = true);
    final res = await ref.read(paymentRepoProvider).confirm(
          widget.rideId,
          orderId: orderId,
          paymentId: paymentId,
          signature: signature,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (_) => context.go('/c/rate/${widget.rideId}'),
      err: (e) => showError(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(rideSessionProvider, (prev, next) {
      if (next.ride?.status == RideStatus.completed) {
        context.go('/c/rate/${widget.rideId}');
      }
    });

    final ride = ref.watch(rideSessionProvider).ride;
    if (ride == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isCash = (ride.paymentMethod ?? 'cash') == 'cash';
    final bd = ride.fareBreakdown;

    return Scaffold(
      appBar: AppBar(title: const Text('Payment'), automaticallyImplyLeading: false),
      body: LoadingOverlay(
        busy: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 56, color: AppColors.success),
                  const SizedBox(height: 8),
                  Text('Ride complete', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(ride.ref, style: const TextStyle(color: AppColors.inkSoft)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SectionCard(
              child: Column(
                children: [
                  if (bd['base'] != null) InfoRow('Base fare', money(bd['base'])),
                  if (bd['distance_charge'] != null)
                    InfoRow('Distance (${bd['distance_km']} km)', money(bd['distance_charge'])),
                  if (bd['time_charge'] != null)
                    InfoRow('Time (${bd['time_min']} min)', money(bd['time_charge'])),
                  if (bd['waiting_charge'] != null && (bd['waiting_charge'] as num) > 0)
                    InfoRow('Waiting', money(bd['waiting_charge'])),
                  if (bd['promo_discount'] != null && (bd['promo_discount'] as num) > 0)
                    InfoRow('Promo discount', '- ${money(bd['promo_discount'])}'),
                  const Divider(),
                  InfoRow('Total', money(ride.finalFare ?? ride.amountDue), strong: true),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (isCash)
              _CashPanel(amount: ride.finalFare ?? ride.amountDue)
            else
              PrimaryButton(
                label: 'Pay ${money(ride.finalFare ?? ride.amountDue)} by UPI',
                icon: Icons.qr_code_rounded,
                onPressed: () => _payByUpi(ride.finalFare ?? ride.amountDue),
              ),
          ],
        ),
      ),
    );
  }
}

class _CashPanel extends StatelessWidget {
  const _CashPanel({required this.amount});
  final double amount;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          const Icon(Icons.payments_rounded, size: 40, color: AppColors.brand),
          const SizedBox(height: 10),
          Text('Pay ${money(amount)} in cash',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            'Hand the cash to your driver. This screen updates automatically once '
            'the driver confirms it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Waiting for driver confirmation…'),
            ],
          ),
        ],
      ),
    );
  }
}
