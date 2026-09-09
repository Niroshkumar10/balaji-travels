import 'json.dart';

class RouteInfo {
  const RouteInfo({
    required this.distanceM,
    required this.durationS,
    this.polyline,
    this.source,
  });

  final int distanceM;
  final int durationS;
  final String? polyline;
  final String? source;

  double get km => distanceM / 1000;
  int get minutes => (durationS / 60).round();

  factory RouteInfo.fromJson(Map<String, dynamic> j) => RouteInfo(
        distanceM: asInt(j['distanceM']),
        durationS: asInt(j['durationS']),
        polyline: j['polyline']?.toString(),
        source: j['source']?.toString(),
      );
}

class FareOption {
  const FareOption({
    required this.category,
    required this.fare,
    this.currency = 'INR',
    this.breakdown = const {},
  });

  final String category;
  final double fare;
  final String currency;
  final Map<String, dynamic> breakdown;

  factory FareOption.fromJson(Map<String, dynamic> j) => FareOption(
        category: j['category']?.toString() ?? 'hatchback',
        fare: asDouble(j['fare']),
        currency: j['currency']?.toString() ?? 'INR',
        breakdown: asMap(j['breakdown']),
      );
}

class RideEstimate {
  const RideEstimate({required this.route, required this.options});

  final RouteInfo route;
  final List<FareOption> options;

  factory RideEstimate.fromJson(Map<String, dynamic> j) => RideEstimate(
        route: RouteInfo.fromJson(asMap(j['route'])),
        options: asList(j['options']).map(FareOption.fromJson).toList(),
      );
}
