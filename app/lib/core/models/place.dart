import 'json.dart';

class PlacePrediction {
  const PlacePrediction({
    required this.description,
    this.placeId,
    this.mainText,
    this.secondaryText,
  });

  final String description;
  final String? placeId;
  final String? mainText;
  final String? secondaryText;

  factory PlacePrediction.fromJson(Map<String, dynamic> j) => PlacePrediction(
        description: j['description']?.toString() ?? '',
        placeId: j['placeId']?.toString(),
        mainText: j['mainText']?.toString(),
        secondaryText: j['secondaryText']?.toString(),
      );
}

class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.label,
    required this.lat,
    required this.lng,
    this.addr,
  });

  final int id;
  final String label;
  final double lat;
  final double lng;
  final String? addr;

  factory SavedPlace.fromJson(Map<String, dynamic> j) => SavedPlace(
        id: asInt(j['id']),
        label: j['label']?.toString() ?? '',
        lat: asDouble(j['lat']),
        lng: asDouble(j['lng']),
        addr: j['addr']?.toString(),
      );
}
