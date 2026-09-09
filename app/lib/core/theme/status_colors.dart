import 'package:flutter/material.dart';

import '../models/ride.dart';
import 'app_colors.dart';

/// Semantic colour for a ride/booking status — use for badges, chips,
/// timelines, status icons and status text. Not decorative.
Color rideStatusColor(RideStatus s) => switch (s) {
      RideStatus.requested || RideStatus.searchingDriver => AppColors.rideSearching,
      RideStatus.driverAssigned => AppColors.rideAssigned,
      RideStatus.driverArriving || RideStatus.driverArrived => AppColors.rideArriving,
      RideStatus.rideStarted || RideStatus.rideInProgress => AppColors.rideStarted,
      RideStatus.driverCompleted || RideStatus.paymentPending => AppColors.rideAssigned,
      RideStatus.completed => AppColors.rideCompleted,
      RideStatus.customerCancelled ||
      RideStatus.driverCancelled ||
      RideStatus.systemCancelled ||
      RideStatus.noDriversFound ||
      RideStatus.paymentFailed =>
        AppColors.rideCancelled,
      RideStatus.unknown => AppColors.textTertiary,
    };

/// Colour for a driver availability string ('available'|'on_trip'|'offline').
Color driverAvailabilityColor(String availability) => switch (availability) {
      'available' => AppColors.rideAvailable,
      'on_trip' => AppColors.rideStarted,
      _ => AppColors.textTertiary,
    };
