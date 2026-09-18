import 'json.dart';
import 'vehicle.dart';

class CustomerProfile {
  const CustomerProfile({
    required this.id,
    required this.userId,
    required this.mobile,
    this.name,
    this.email,
    this.defaultPaymentMethod = 'cash',
    this.homeLabel,
    this.homeLat,
    this.homeLng,
    this.homeAddr,
    this.workLabel,
    this.workLat,
    this.workLng,
    this.workAddr,
  });

  final int id;
  final int userId;
  final String mobile;
  final String? name;
  final String? email;
  final String defaultPaymentMethod;
  final String? homeLabel;
  final double? homeLat;
  final double? homeLng;
  final String? homeAddr;
  final String? workLabel;
  final double? workLat;
  final double? workLng;
  final String? workAddr;

  /// Parses the `/customers/me` shape: `{ id, mobile, name, email, customer: {...} }`.
  factory CustomerProfile.fromProfileJson(Map<String, dynamic> j) {
    final c = asMap(j['customer']);
    return CustomerProfile(
      id: asInt(c['id']),
      userId: asInt(j['id']),
      mobile: j['mobile']?.toString() ?? '',
      name: j['name']?.toString(),
      email: j['email']?.toString(),
      defaultPaymentMethod: c['default_payment_method']?.toString() ?? 'cash',
      homeLabel: c['home_label']?.toString(),
      homeLat: asDoubleOrNull(c['home_lat']),
      homeLng: asDoubleOrNull(c['home_lng']),
      homeAddr: c['home_addr']?.toString(),
      workLabel: c['work_label']?.toString(),
      workLat: asDoubleOrNull(c['work_lat']),
      workLng: asDoubleOrNull(c['work_lng']),
      workAddr: c['work_addr']?.toString(),
    );
  }
}

class DriverProfile {
  const DriverProfile({
    required this.id,
    required this.userId,
    required this.mobile,
    this.name,
    this.email,
    this.kycStatus = 'pending',
    this.kycRejectReason,
    this.licenseNo,
    this.licenseExpiry,
    this.licenseDocPath,
    this.idProofType,
    this.idProofNumber,
    this.idProofDocPath,
    this.photoPath,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.isOnline = false,
    this.availability = 'offline',
    this.serviceTypes = const ['local'],
    this.currentVehicleId,
    this.vehicles = const [],
  });

  final int id;
  final int userId;
  final String mobile;
  final String? name;
  final String? email;
  final String kycStatus; // pending | approved | rejected | suspended
  final String? kycRejectReason;
  final String? licenseNo;
  final DateTime? licenseExpiry;
  final String? licenseDocPath;
  final String? idProofType;
  final String? idProofNumber;
  final String? idProofDocPath;
  final String? photoPath;
  final double ratingAvg;
  final int ratingCount;
  final bool isOnline;
  final String availability; // offline | available | on_trip
  /// Which bookings this driver receives — any of 'local'/'rental'/'outstation'.
  final List<String> serviceTypes;
  final int? currentVehicleId;
  final List<Vehicle> vehicles;

  bool get kycApproved => kycStatus == 'approved';
  Vehicle? get activeVehicle =>
      vehicles.where((v) => v.isActive).cast<Vehicle?>().firstWhere((_) => true, orElse: () => null);

  factory DriverProfile.fromProfileJson(Map<String, dynamic> j) {
    final d = asMap(j['driver']);
    return DriverProfile(
      id: asInt(d['id']),
      userId: asInt(j['id']),
      mobile: j['mobile']?.toString() ?? '',
      name: j['name']?.toString(),
      email: j['email']?.toString(),
      kycStatus: d['kyc_status']?.toString() ?? 'pending',
      kycRejectReason: d['kyc_reject_reason']?.toString(),
      licenseNo: d['license_no']?.toString(),
      licenseExpiry: asDate(d['license_expiry']),
      licenseDocPath: d['license_doc_path']?.toString(),
      idProofType: d['id_proof_type']?.toString(),
      idProofNumber: d['id_proof_number']?.toString(),
      idProofDocPath: d['id_proof_doc_path']?.toString(),
      photoPath: d['photo_path']?.toString(),
      ratingAvg: asDouble(d['rating_avg']),
      ratingCount: asInt(d['rating_count']),
      isOnline: asBool(d['is_online']),
      availability: d['availability']?.toString() ?? 'offline',
      serviceTypes: (d['service_types']?.toString() ?? 'local')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      currentVehicleId: asIntOrNull(d['current_vehicle_id']),
      vehicles: asList(j['vehicles']).map(Vehicle.fromJson).toList(),
    );
  }
}
