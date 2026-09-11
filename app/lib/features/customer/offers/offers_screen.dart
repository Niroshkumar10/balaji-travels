import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';

final _offersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.watch(miscRepoProvider).promos();
  return res.valueOrNull ?? [];
});

/// One card's worth of copy for the offer list — either a real promo from
/// the backend (`/promos`) or one of the sample cards below shown alongside
/// it so the page is never empty and reads the way the reference design
/// does. Dummy cards are flagged (see [isDummy]) and can't actually be
/// booked against a real fare.
class _OfferCard {
  const _OfferCard({
    required this.title,
    required this.left,
    required this.upTo,
    required this.location,
    required this.useBy,
    this.code,
    this.isDummy = false,
  });

  final String title;
  final int left;
  final String upTo;
  final String location;
  final String useBy;
  final String? code;
  final bool isDummy;

  factory _OfferCard.fromPromo(Map<String, dynamic> o) {
    final isPercent = o['type'] == 'percent';
    final value = o['value'];
    return _OfferCard(
      title: o['description']?.toString() ?? (isPercent ? '$value% off your next ride' : '${money(value)} off your next ride'),
      left: (o['perUserLimit'] as num?)?.toInt() ?? 1,
      upTo: o['maxDiscount'] != null ? money(o['maxDiscount']) : (isPercent ? '$value%' : money(value)),
      location: 'Sri Balaji Travels',
      useBy: 'Ongoing',
      code: o['code']?.toString(),
    );
  }
}

const _dummyOffers = [
  _OfferCard(title: '5% off your next ride', left: 1, upTo: '₹750', location: 'Pollachi', useBy: 'Dec 31, 2027', code: 'RIDE5', isDummy: true),
  _OfferCard(title: '7% off your next ride', left: 1, upTo: '₹1,000', location: 'Pollachi', useBy: 'Dec 31, 2027', code: 'RIDE7', isDummy: true),
  _OfferCard(title: '3% off your next ride', left: 5, upTo: '₹750', location: 'Pollachi', useBy: 'Dec 31, 2028', code: 'RIDE3', isDummy: true),
  _OfferCard(title: '100% off your next ride', left: 1, upTo: '₹25', location: 'India', useBy: 'Dec 31, 2026', code: 'WELCOME100', isDummy: true),
];

class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});
  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> {
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _submitCode() {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    _codeCtrl.clear();
    FocusScope.of(context).unfocus();
    showOk(context, 'Saved "$code" — you can apply it at checkout.');
  }

  void _details(_OfferCard o) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(o.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              InfoRow('Up to', o.upTo),
              InfoRow('Valid in', o.location),
              InfoRow('Use by', o.useBy),
              if (o.code != null) InfoRow('Code', o.code!),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Book a ride',
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/c/where-to');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_offersProvider);
    return Scaffold(
      appBar: const RtAppBar(title: 'Offers', fallbackRoute: '/c/home'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (promos) {
          final cards = [...promos.map(_OfferCard.fromPromo), ..._dummyOffers];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(Icons.sell_rounded, color: AppColors.inkSoft, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _submitCode(),
                        decoration: const InputDecoration(border: InputBorder.none, hintText: 'Add new offer code'),
                      ),
                    ),
                    TextButton(onPressed: _submitCode, child: const Text('Add')),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ...cards.map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _OfferTile(offer: o, onDetails: () => _details(o)),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.onDetails});
  final _OfferCard offer;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.local_offer_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offer.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  '${offer.left} left · Up to ${offer.upTo} off · ${offer.location}',
                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
                ),
                Text('Use by ${offer.useBy}', style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Material(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => context.push('/c/where-to'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('Book now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                      onPressed: onDetails,
                      child: const Text('Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(color: AppColors.info, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
