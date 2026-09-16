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
    this.rcNumber,
    this.rcExpiry,
    this.rcDocPath,
    this.insuranceNumber,
    this.insuranceExpiry,
    this.insuranceDocPath,
    this.permitNumber,
    this.permitExpiry,
    this.permitDocPath,
    this.fitnessNumber,
    this.fitnessExpiry,
    this.fitnessDocPath,
    this.pucNumber,
    this.pucExpiry,
    this.pucDocPath,
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
  final String? rcNumber;
  final DateTime? rcExpiry;
  final String? rcDocPath;
  final String? insuranceNumber;
  final DateTime? insuranceExpiry;
  final String? insuranceDocPath;
  final String? permitNumber;
  final DateTime? permitExpiry;
  final String? permitDocPath;
  final String? fitnessNumber;
  final DateTime? fitnessExpiry;
  final String? fitnessDocPath;
  final String? pucNumber;
  final DateTime? pucExpiry;
  final String? pucDocPath;

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
        rcNumber: j['rc_number']?.toString(),
        rcExpiry: asDate(j['rc_expiry']),
        rcDocPath: j['rc_doc_path']?.toString(),
        insuranceNumber: j['insurance_number']?.toString(),
        insuranceExpiry: asDate(j['insurance_expiry']),
        insuranceDocPath: j['insurance_doc_path']?.toString(),
        permitNumber: j['permit_number']?.toString(),
        permitExpiry: asDate(j['permit_expiry']),
        permitDocPath: j['permit_doc_path']?.toString(),
        fitnessNumber: j['fitness_number']?.toString(),
        fitnessExpiry: asDate(j['fitness_expiry']),
        fitnessDocPath: j['fitness_doc_path']?.toString(),
        pucNumber: j['puc_number']?.toString(),
        pucExpiry: asDate(j['puc_expiry']),
        pucDocPath: j['puc_doc_path']?.toString(),
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
