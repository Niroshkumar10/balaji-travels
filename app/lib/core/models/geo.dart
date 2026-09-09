import 'json.dart';

class LatLngPoint {
  const LatLngPoint({required this.lat, required this.lng, this.addr});

  final double lat;
  final double lng;
  final String? addr;

  factory LatLngPoint.fromJson(Map<String, dynamic> j) => LatLngPoint(
        lat: asDouble(j['lat']),
        lng: asDouble(j['lng']),
        addr: j['addr']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (addr != null) 'addr': addr,
      };

  LatLngPoint copyWith({double? lat, double? lng, String? addr}) => LatLngPoint(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        addr: addr ?? this.addr,
      );
}
