import 'json.dart';

class Vehicle {
  const Vehicle({
    required this.id,
    required this.category,
    required this.plateNo,
    this.make,
    this.model,
    this.color,
    this.year,
    this.docStatus = 'pending',
    this.isActive = true,
  });

  final int id;
  final String category; // bike | auto | hatchback | sedan | suv
  final String plateNo;
  final String? make;
  final String? model;
  final String? color;
  final int? year;
  final String docStatus;
  final bool isActive;

  String get label => [make, model].where((e) => e != null && e.isNotEmpty).join(' ');

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
        id: asInt(j['id']),
        category: j['category']?.toString() ?? 'hatchback',
        plateNo: j['plate_no']?.toString() ?? '',
        make: j['make']?.toString(),
        model: j['model']?.toString(),
        color: j['color']?.toString(),
        year: asIntOrNull(j['year']),
        docStatus: j['doc_status']?.toString() ?? 'pending',
        isActive: asBool(j['is_active']),
      );
}

/// UI metadata for a vehicle category (icon, display name, seat count).
class VehicleCategoryInfo {
  const VehicleCategoryInfo(this.id, this.name, this.seats, this.emoji);
  final String id;
  final String name;
  final int seats;
  final String emoji;

  static const all = [
    VehicleCategoryInfo('bike', 'Bike', 1, '🏍️'),
    VehicleCategoryInfo('auto', 'Auto', 3, '🛺'),
    VehicleCategoryInfo('hatchback', 'Mini', 4, '🚗'),
    VehicleCategoryInfo('sedan', 'Sedan', 4, '🚙'),
    VehicleCategoryInfo('suv', 'SUV', 6, '🚐'),
  ];

  static VehicleCategoryInfo of(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all[2]);
}
