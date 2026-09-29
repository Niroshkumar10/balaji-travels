import 'json.dart';

enum RideStatus {
  requested,
  searchingDriver,
  pendingAdminAssignment,
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
        'PENDING_ADMIN_ASSIGNMENT' => RideStatus.pendingAdminAssignment,
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

  /// Once a driver is genuinely on the way (or later) — used to decide
  /// whether it's still meaningful to show driver/vehicle details at all.
  bool get isPastAssignment => const {
        RideStatus.driverAssigned,
        RideStatus.driverArriving,
        RideStatus.driverArrived,
        RideStatus.rideStarted,
        RideStatus.rideInProgress,
        RideStatus.driverCompleted,
        RideStatus.paymentPending,
        RideStatus.completed,
      }.contains(this);

  String get label => switch (this) {
        RideStatus.requested || RideStatus.searchingDriver => 'Finding a driver',
        RideStatus.pendingAdminAssignment => 'Driver will be assigned shortly',
        RideStatus.driverAssigned || RideStatus.driverArriving => 'Driver assigned',
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

/// The single predicate both the rider's "Upcoming Trips" cards (Case 1-3,
/// see the backend's assignmentGateService.js) and the driver's "Reserved"
/// pill are derived from — computed on the model so neither surface can
/// drift from the other's logic. Local rides never sit in
/// [awaitingDriverConfirmation] or [reserved] — they skip straight from
/// [notAssigned] to [live] (driverAcceptance is always 'not_required').
enum RideAssignmentStage { notAssigned, awaitingDriverConfirmation, reserved, live, finished }

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
    this.cancelledAt,
    this.scheduledAt,
    this.rentalPackageHours,
    this.driverAcceptance = 'not_required',
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
  final DateTime? cancelledAt;
  final DateTime? scheduledAt;
  final int? rentalPackageHours;
  /// 'not_required' (Local) | 'pending' | 'accepted' — see the backend's
  /// assignmentGateService.js. Drives [assignmentStage] below.
  final String driverAcceptance;

  double get amountDue => finalFare ?? estFare ?? 0;
  double? get km => distanceM == null ? null : distanceM! / 1000;

  bool get isLocal => rideType == 'local';
  /// 'rental' | 'trip' | 'local' — outstation and round_trip both read as
  /// "Trip" everywhere in the UI (matches the backend's serviceFor()).
  String get serviceKind => switch (rideType) {
        'local' => 'local',
        'rental' => 'rental',
        _ => 'trip',
      };

  RideAssignmentStage get assignmentStage {
    if (status.isTerminal || status == RideStatus.paymentFailed) return RideAssignmentStage.finished;
    if (!status.isPastAssignment) return RideAssignmentStage.notAssigned;
    if (status == RideStatus.driverAssigned) {
      if (driverAcceptance == 'pending') return RideAssignmentStage.awaitingDriverConfirmation;
      if (driverAcceptance == 'accepted') return RideAssignmentStage.reserved;
    }
    return RideAssignmentStage.live;
  }

  /// The rider-facing label for Cases 1-3 (see assignmentGateService.js's
  /// doc comment); everything else falls back to the existing status label.
  String get riderStageLabel => switch (assignmentStage) {
        RideAssignmentStage.notAssigned => 'Still driver is not assigned',
        RideAssignmentStage.awaitingDriverConfirmation => 'Waiting for driver confirmation',
        RideAssignmentStage.reserved => 'Driver assigned',
        RideAssignmentStage.live || RideAssignmentStage.finished => status.label,
      };

  /// The date/time that actually matters for a HISTORY view (trip lists,
  /// filtering by day/week) — as opposed to [scheduledAt], which is a
  /// future target pickup time that can be completely unrelated to when a
  /// ride was actually driven (a rental's scheduled slot and its real
  /// completion time can land on different days). A completed ride is
  /// dated by when it finished, a cancelled one by when it was cancelled;
  /// anything still active/reserved is dated by when it was requested —
  /// never by scheduledAt, which would misfile a same-day-completed trip
  /// under some unrelated future date, or a merely-reserved future booking
  /// under "today" just because its target slot happens to fall today.
  DateTime? get historyAt {
    if (status == RideStatus.completed) return completedAt ?? requestedAt;
    if (status.isCancelled) return cancelledAt ?? requestedAt;
    return requestedAt;
  }

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
      cancelledAt: asDate(j['cancelled_at']),
      scheduledAt: asDate(j['scheduled_at']),
      rentalPackageHours: asIntOrNull(j['rental_package_hours']),
      driverAcceptance: j['driverAcceptance']?.toString() ?? 'not_required',
    );
  }
}
