import 'json.dart';

enum RideStatus {
  requested,
  searchingDriver,
  driverAssigned,
  driverArriving,
  driverArrived,
  rideStarted,
  rideInProgress,
  driverCompleted,
  paymentPending,
  completed,
  customerCancelled,
  driverCancelled,
  systemCancelled,
  noDriversFound,
  paymentFailed,
  unknown;

  static RideStatus parse(String? s) => switch (s) {
        'REQUESTED' => RideStatus.requested,
        'SEARCHING_DRIVER' => RideStatus.searchingDriver,
        'DRIVER_ASSIGNED' => RideStatus.driverAssigned,
        'DRIVER_ARRIVING' => RideStatus.driverArriving,
        'DRIVER_ARRIVED' => RideStatus.driverArrived,
        'RIDE_STARTED' => RideStatus.rideStarted,
        'RIDE_IN_PROGRESS' => RideStatus.rideInProgress,
        'DRIVER_COMPLETED' => RideStatus.driverCompleted,
        'PAYMENT_PENDING' => RideStatus.paymentPending,
        'COMPLETED' => RideStatus.completed,
        'CUSTOMER_CANCELLED' => RideStatus.customerCancelled,
        'DRIVER_CANCELLED' => RideStatus.driverCancelled,
        'SYSTEM_CANCELLED' => RideStatus.systemCancelled,
        'NO_DRIVERS_FOUND' => RideStatus.noDriversFound,
        'PAYMENT_FAILED' => RideStatus.paymentFailed,
        _ => RideStatus.unknown,
      };

  bool get isTerminal => const {
        RideStatus.completed,
        RideStatus.customerCancelled,
        RideStatus.driverCancelled,
        RideStatus.systemCancelled,
        RideStatus.noDriversFound,
      }.contains(this);

  bool get isCancelled => const {
        RideStatus.customerCancelled,
        RideStatus.driverCancelled,
        RideStatus.systemCancelled,
      }.contains(this);

  bool get isActive => !isTerminal && this != RideStatus.paymentFailed;

  String get label => switch (this) {
        RideStatus.requested || RideStatus.searchingDriver => 'Finding a driver',
        RideStatus.driverAssigned || RideStatus.driverArriving => 'Driver on the way',
        RideStatus.driverArrived => 'Driver has arrived',
        RideStatus.rideStarted || RideStatus.rideInProgress => 'On the way to destination',
        RideStatus.driverCompleted || RideStatus.paymentPending => 'Payment',
        RideStatus.completed => 'Completed',
        RideStatus.noDriversFound => 'No drivers found',
        RideStatus.customerCancelled ||
        RideStatus.driverCancelled ||
        RideStatus.systemCancelled =>
          'Cancelled',
        RideStatus.paymentFailed => 'Payment failed',
        RideStatus.unknown => '—',
      };
}

class RideDriver {
  const RideDriver({required this.id, required this.name, this.rating = 0, this.phoneMasked});
  final int id;
  final String name;
  final double rating;
  final String? phoneMasked;

  factory RideDriver.fromJson(Map<String, dynamic> j) => RideDriver(
        id: asInt(j['id']),
        name: j['name']?.toString() ?? 'Driver',
        rating: asDouble(j['rating']),
        phoneMasked: j['phoneMasked']?.toString(),
      );
}

class RideVehicle {
  const RideVehicle({
    required this.category,
    required this.plateNo,
    this.make,
    this.model,
    this.color,
  });
  final String category;
  final String plateNo;
  final String? make;
  final String? model;
  final String? color;

  String get label =>
      [make, model].whereType<String>().where((e) => e.isNotEmpty).join(' ');

  factory RideVehicle.fromJson(Map<String, dynamic> j) => RideVehicle(
        category: j['category']?.toString() ?? '',
        plateNo: j['plateNo']?.toString() ?? j['plate_no']?.toString() ?? '',
        make: j['make']?.toString(),
        model: j['model']?.toString(),
        color: j['color']?.toString(),
      );
}

class Ride {
  Ride({
    required this.id,
    required this.ref,
    required this.status,
    required this.vehicleCategory,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropLat,
    required this.dropLng,
    this.pickupAddr,
    this.dropAddr,
    this.rideType = 'local',
    this.distanceM,
    this.durationS,
    this.estFare,
    this.finalFare,
    this.fareBreakdown = const {},
    this.paymentMethod,
    this.otp,
    this.polyline,
    this.driver,
    this.vehicle,
    this.driverLat,
    this.driverLng,
    this.driverBearing,
    this.cancelledBy,
    this.cancelReason,
    this.requestedAt,
    this.completedAt,
  });

  final int id;
  final String ref;
  final RideStatus status;
  final String vehicleCategory;
  final String rideType;
  final double pickupLat;
  final double pickupLng;
  final double dropLat;
  final double dropLng;
  final String? pickupAddr;
  final String? dropAddr;
  final int? distanceM;
  final int? durationS;
  final double? estFare;
  final double? finalFare;
  final Map<String, dynamic> fareBreakdown;
  final String? paymentMethod;
  final String? otp;
  final String? polyline;
  final RideDriver? driver;
  final RideVehicle? vehicle;
  final double? driverLat;
  final double? driverLng;
  final double? driverBearing;
  final String? cancelledBy;
  final String? cancelReason;
  final DateTime? requestedAt;
  final DateTime? completedAt;

  double get amountDue => finalFare ?? estFare ?? 0;
  double? get km => distanceM == null ? null : distanceM! / 1000;

  factory Ride.fromJson(Map<String, dynamic> j) {
    final dl = asMap(j['driverLocation']);
    return Ride(
      id: asInt(j['id']),
      ref: j['ride_ref']?.toString() ?? '',
      status: RideStatus.parse(j['status']?.toString()),
      vehicleCategory: j['vehicle_category']?.toString() ?? 'hatchback',
      rideType: j['ride_type']?.toString() ?? 'local',
      pickupLat: asDouble(j['pickup_lat']),
      pickupLng: asDouble(j['pickup_lng']),
      dropLat: asDouble(j['drop_lat']),
      dropLng: asDouble(j['drop_lng']),
      pickupAddr: j['pickup_addr']?.toString(),
      dropAddr: j['drop_addr']?.toString(),
      distanceM: asIntOrNull(j['distance_m']),
      durationS: asIntOrNull(j['duration_s']),
      estFare: asDoubleOrNull(j['est_fare']),
      finalFare: asDoubleOrNull(j['final_fare']),
      fareBreakdown: asMap(j['fare_breakdown']),
      paymentMethod: j['payment_method']?.toString(),
      otp: j['otp']?.toString(),
      polyline: j['route_polyline']?.toString(),
      driver: j['driver'] is Map ? RideDriver.fromJson(asMap(j['driver'])) : null,
      vehicle: j['vehicle'] is Map ? RideVehicle.fromJson(asMap(j['vehicle'])) : null,
      driverLat: asDoubleOrNull(dl['lat']),
      driverLng: asDoubleOrNull(dl['lng']),
      driverBearing: asDoubleOrNull(dl['bearing']),
      cancelledBy: j['cancelled_by']?.toString(),
      cancelReason: j['cancel_reason']?.toString(),
      requestedAt: asDate(j['requested_at']),
      completedAt: asDate(j['completed_at']),
    );
  }
}
