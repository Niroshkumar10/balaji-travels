import 'package:flutter/material.dart';

/// One selectable vehicle-type group in the Rental/Outstation picker
/// (Urbania, Tempo Traveller, Car, Bus), each with its own seater/model
/// variants.
class VehicleCategory {
  const VehicleCategory({required this.icon, required this.label, required this.variants});
  final IconData icon;
  final String label;
  final List<String> variants;
}

/// Maps a Rental vehicle pick to the closest real backend fare category —
/// same honest tradeoff already used for Outstation's fleet list (see
/// trip_review_screen.dart's `_Fleet`): the backend only has fare configs
/// for bike/auto/hatchback/sedan/suv, so it has no per-vehicle-name pricing
/// for "Urbania" or "Jaguar" to quote. Vehicles mapped to the same category
/// necessarily show the same package price — honest given what the backend
/// can actually price, rather than an invented per-vehicle number that
/// would silently diverge from what booking actually charges.
String rentalBookingCategory(String categoryLabel, String variant) {
  switch (categoryLabel) {
    case 'Car':
      if (variant.contains('Dzire') || variant.contains('Etios')) return 'hatchback';
      if (variant.contains('Ciaz') || variant.contains('Jaguar')) return 'sedan';
      return 'suv'; // Ertiga, Innova/Crysta/Hycross, Fortuner
    case 'Urbania':
    case 'Tempo Traveller':
    case 'Bus':
    default:
      return 'suv'; // the largest existing category — closest fit for group/fleet vehicles
  }
}

class VehicleCatalog {
  const VehicleCatalog._();

  static const List<VehicleCategory> categories = [
    VehicleCategory(
      icon: Icons.airport_shuttle_rounded,
      label: 'Urbania',
      variants: [
        '7-seater Urbania',
        '8-seater Urbania',
        '10-seater Urbania',
        '12-seater Urbania',
        '14-seater Urbania',
        '16-seater Urbania',
        '17-seater Urbania',
        'Caravan',
      ],
    ),
    VehicleCategory(
      icon: Icons.directions_bus_filled_rounded,
      label: 'Tempo Traveller',
      variants: [
        '7-seater Tempo Traveller',
        '12-seater Tempo Traveller',
        '13-seater Tempo Traveller',
        '14-seater Tempo Traveller',
        '15-seater Tempo Traveller',
        '16-seater Tempo Traveller',
        '17-seater Tempo Traveller',
        '18-seater Tempo Traveller',
        '19-seater Tempo Traveller',
        '22-seater Tempo Traveller',
        '23-seater Tempo Traveller',
        'Minivan',
      ],
    ),
    VehicleCategory(
      icon: Icons.directions_car_filled_rounded,
      label: 'Car',
      variants: [
        'Swift Dzire / Toyota Etios',
        'Maruti Suzuki Ciaz',
        'Maruti Suzuki Ertiga',
        'Toyota Innova',
        'Toyota Innova Crysta',
        'Toyota Innova Hycross',
        'Toyota Fortuner',
        'Jaguar',
      ],
    ),
    VehicleCategory(
      icon: Icons.directions_bus_rounded,
      label: 'Bus',
      variants: [
        '25-seater Minibus',
        '30-seater Minibus',
        '34-seater Minibus',
        '40-seater Bus',
        '55-seater Bus',
      ],
    ),
  ];
}
