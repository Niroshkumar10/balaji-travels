import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One wallet transaction — a top-up (+) shown in history.
class WalletTxn {
  const WalletTxn({required this.amount, required this.at, required this.note});
  final double amount;
  final DateTime at;
  final String note;

  factory WalletTxn.fromJson(Map<String, dynamic> j) => WalletTxn(
        amount: (j['amount'] as num).toDouble(),
        at: DateTime.parse(j['at'] as String),
        note: j['note'] as String? ?? 'Added money',
      );

  Map<String, dynamic> toJson() => {'amount': amount, 'at': at.toIso8601String(), 'note': note};
}

/// A demo wallet ("Sri Balaji Travels Wallet") — there is no backend wallet
/// for customers yet (only driver earnings/payouts exist server-side), so
/// this is a local, per-device balance backed by SharedPreferences, same
/// pattern as [Session] and [RecentSearchStore]. Good enough to show the
/// add-money + transaction-history UX end to end; not a real payment
/// instrument.
class WalletStore {
  const WalletStore._();

  static const _kBalance = 'rt.wallet.balance';
  static const _kTxns = 'rt.wallet.txns';

  static Future<double> balance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kBalance) ?? 0;
  }

  static Future<List<WalletTxn>> history() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kTxns) ?? const [];
    return raw
        .map((s) {
          try {
            return WalletTxn.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<WalletTxn>()
        .toList();
  }

  static Future<double> addMoney(double amount, {String note = 'Added money'}) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (await balance()) + amount;
    await prefs.setDouble(_kBalance, next);
    final txns = [WalletTxn(amount: amount, at: DateTime.now(), note: note), ...await history()];
    await prefs.setStringList(_kTxns, txns.map((t) => jsonEncode(t.toJson())).toList());
    return next;
  }
}
