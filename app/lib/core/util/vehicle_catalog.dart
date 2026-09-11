import 'package:flutter/material.dart';

/// One selectable vehicle-type group in the Rental/Outstation picker
/// (Urbania, Tempo Traveller, Car, Bus), each with its own seater/model
/// variants. This taxonomy is specific to group/outstation travel and is
/// separate from the bike/auto/hatchback/sedan/suv categories the local-ride
/// fare engine already knows — there is no backend pricing for it yet, so
/// picking one carries a label forward for the rider/ops team rather than
/// driving an automated fare quote.
class VehicleCategory {
  const VehicleCategory({required this.icon, required this.label, required this.variants});
  final IconData icon;
  final String label;
  final List<String> variants;
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
