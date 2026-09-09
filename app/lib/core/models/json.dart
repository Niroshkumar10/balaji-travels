/// Tolerant JSON coercers — the backend returns numbers as strings in a few
/// places (mysql2 dateStrings / DECIMAL), so parse defensively everywhere.
double? asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

double asDouble(Object? v, [double fallback = 0]) => asDoubleOrNull(v) ?? fallback;

int? asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

int asInt(Object? v, [int fallback = 0]) => asIntOrNull(v) ?? fallback;

bool asBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v?.toString().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

DateTime? asDate(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  // backend datetimes are UTC wall-clock without a marker
  final withZ = RegExp(r'[zZ]$|[+-]\d\d:?\d\d$').hasMatch(s)
      ? s
      : '${s.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(withZ)?.toLocal();
}

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

List<Map<String, dynamic>> asList(Object? v) =>
    v is List ? v.map((e) => asMap(e)).toList() : const [];
