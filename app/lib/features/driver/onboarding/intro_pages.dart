import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';

/// Categories a driver can register with. Bike/Auto/Car map straight onto
/// the backend's vehicle categories; "Commercial Car" (a bigger multi-seat
/// vehicle for hire, e.g. an SUV/van) maps onto 'suv', the closest real fit.
const _cities = [
  'Chennai', 'Coimbatore', 'Madurai', 'Tiruchirappalli', 'Salem',
  'Bengaluru', 'Hyderabad', 'Mumbai', 'Delhi', 'Pune',
];

const _vehicleChoices = [
  ('Bike', 'Motorcycle or scooter', Icons.two_wheeler_rounded, 'bike'),
  ('Auto Rickshaw', 'Auto rickshaw', Icons.electric_rickshaw_rounded, 'auto'),
  ('Car', 'Drive your car', Icons.directions_car_filled_rounded, 'hatchback'),
  ('Commercial Car', 'Drive or manage multiple cars', Icons.airport_shuttle_rounded, 'suv'),
];

/// Post-login intro: basic profile, then vehicle category. Lands on the
/// Registration Checklist once done. Skipped entirely for a driver who
/// already has a name/vehicle on file — see DriverOnboardingEntry.
class DriverIntroPages extends ConsumerStatefulWidget {
  const DriverIntroPages({super.key});
  @override
  ConsumerState<DriverIntroPages> createState() => _DriverIntroPagesState();
}

class _DriverIntroPagesState extends ConsumerState<DriverIntroPages> {
  final _pageCtrl = PageController();
  int _page = 0;

  final _name = TextEditingController();
  String? _city;
  DateTime? _dob;
  String _vehicleCategory = 'hatchback';
  bool _busy = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _name.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 1) {
      _finish();
      return;
    }
    _pageCtrl.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  bool get _canContinue => switch (_page) {
        0 => _name.text.trim().isNotEmpty,
        _ => true,
      };

  Future<void> _finish() async {
    setState(() => _busy = true);
    await DriverOnboardingStore.patch({
      if (_dob != null) 'dob': _dob!.toIso8601String(),
      if (_city != null) 'city': _city,
      'vehicleCategory': _vehicleCategory,
    });
    // Name is a real backend field — save it now so the rest of the wizard
    // (and the dashboard, if the driver backs out) already reflects it.
    final res = await ref.read(profileRepoProvider).updateDriver({'name': _name.text.trim()});
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (_) {
        ref.read(authControllerProvider.notifier).refreshName(_name.text.trim());
        ref.invalidate(driverProfileProvider);
        context.pushReplacement('/d/onboarding/checklist');
      },
      err: (e) => showError(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LoadingOverlay(
          busy: _busy,
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [_profilePage(), _vehiclePage()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  children: [
                    SmoothPageIndicator(
                      controller: _pageCtrl,
                      count: 2,
                      effect: const WormEffect(dotWidth: 8, dotHeight: 8, activeDotColor: AppColors.primary, dotColor: AppColors.line),
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(label: 'Continue', onPressed: _canContinue ? _next : null),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profilePage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      children: [
        const Text('Tell us about yourself', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime(2000, 1, 1),
              firstDate: DateTime(1950),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _dob = picked);
          },
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Date of birth', prefixIcon: Icon(Icons.calendar_today_outlined)),
            child: Text(_dob == null ? 'DD/MM/YYYY' : '${_dob!.day.toString().padLeft(2, '0')}/${_dob!.month.toString().padLeft(2, '0')}/${_dob!.year}'),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: _city,
          decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_on_outlined)),
          items: _cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => _city = v),
        ),
      ],
    );
  }

  Widget _vehiclePage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      children: [
        const Text('Choose your vehicle', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Select the vehicle you want to use for providing rides', style: TextStyle(color: AppColors.inkSoft)),
        const SizedBox(height: 24),
        ..._vehicleChoices.map((v) => _VehicleTile(
              title: v.$1,
              subtitle: v.$2,
              icon: v.$3,
              selected: _vehicleCategory == v.$4,
              onTap: () => setState(() => _vehicleCategory = v.$4),
            )),
      ],
    );
  }
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.primary : AppColors.line, width: selected ? 2 : 1),
            color: selected ? AppColors.cardSelectedBackground : null,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(subtitle, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? AppColors.primary : AppColors.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
