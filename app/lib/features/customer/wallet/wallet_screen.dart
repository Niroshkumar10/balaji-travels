import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/store/wallet_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/rt_app_bar.dart';

/// Payment methods hub — the "Sri Balaji Travels Wallet" (a local, demo
/// balance; see [WalletStore]) plus Cash as the one real payment method the
/// booking flows use today.
class CustomerWalletScreen extends StatefulWidget {
  const CustomerWalletScreen({super.key});
  @override
  State<CustomerWalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<CustomerWalletScreen> {
  double _balance = 0;
  List<WalletTxn> _txns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await WalletStore.balance();
    final h = await WalletStore.history();
    if (!mounted) return;
    setState(() {
      _balance = b;
      _txns = h;
      _loading = false;
    });
  }

  Future<void> _addMoney() async {
    final ctrl = TextEditingController();
    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add money', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Amount'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [100, 200, 500].map((v) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    onPressed: () => ctrl.text = '$v',
                    child: Text('₹$v'),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Add money',
              onPressed: () {
                final v = double.tryParse(ctrl.text.trim());
                if (v != null && v > 0) Navigator.pop(ctx, v);
              },
            ),
          ],
        ),
      ),
    );
    if (amount == null) return;
    await WalletStore.addMoney(amount);
    await _load();
    if (mounted) showOk(context, 'Added ${money(amount)} to your wallet');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const RtAppBar(title: 'Payment Methods', fallbackRoute: '/c/home'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Container(
                  color: AppColors.canvas,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Sri Balaji Travels Wallet',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(money(_balance), style: const TextStyle(color: AppColors.inkSoft)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.info_outline_rounded, color: AppColors.inkSoft),
                        onPressed: () => showOk(
                          context,
                          'This is a demo balance stored on this device — it is not a real payment instrument yet.',
                        ),
                      ),
                    ],
                  ),
                ),
                AppTile(
                  icon: Icons.add_circle_outline_rounded,
                  title: 'Add Money',
                  onTap: _addMoney,
                ),
                const Divider(height: 1, indent: 70),
                AppTile(
                  icon: Icons.receipt_long_rounded,
                  title: 'Transaction History',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => _TxnHistoryScreen(txns: _txns)),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  color: AppColors.canvas,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: const Text('Payment Methods', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                ),
                AppTile(icon: Icons.payments_rounded, title: 'Cash'),
              ],
            ),
    );
  }
}

class _TxnHistoryScreen extends StatelessWidget {
  const _TxnHistoryScreen({required this.txns});
  final List<WalletTxn> txns;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const RtAppBar(title: 'Transaction History', fallbackRoute: '/c/home'),
      body: txns.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'No transactions yet',
              subtitle: 'Money you add to your wallet shows up here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: txns.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final t = txns[i];
                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.cardSelectedBackground,
                    child: Icon(Icons.add_rounded, color: AppColors.primary),
                  ),
                  title: Text(t.note),
                  subtitle: Text(DateFormat('d MMM yyyy, hh:mm a').format(t.at)),
                  trailing: Text('+${money(t.amount)}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
                );
              },
            ),
    );
  }
}
