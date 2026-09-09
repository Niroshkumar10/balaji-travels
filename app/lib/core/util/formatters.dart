import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _money2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

String money(num? v, {bool paise = false}) {
  if (v == null) return '—';
  return (paise ? _money2 : _money).format(v);
}

String distance(int? meters) {
  if (meters == null) return '—';
  return meters < 1000 ? '$meters m' : '${(meters / 1000).toStringAsFixed(1)} km';
}

String duration(int? seconds) {
  if (seconds == null) return '—';
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  return '${h}h ${m % 60}m';
}

String eta(int? seconds) {
  if (seconds == null) return '—';
  final m = (seconds / 60).ceil();
  return m <= 1 ? '1 min' : '$m min';
}

String timeAgo(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM').format(d);
}

String dateTimeLabel(DateTime? d) =>
    d == null ? '—' : DateFormat('d MMM, h:mm a').format(d);

String plate(String? p) => (p ?? '').replaceAllMapped(
      RegExp(r'^([A-Z]{2})(\d{1,2})([A-Z]{0,3})(\d{1,4})$'),
      (m) => '${m[1]} ${m[2]} ${m[3]} ${m[4]}'.replaceAll(RegExp(r'\s+'), ' ').trim(),
    );
