import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../../state/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.role});
  final AppRole role;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  bool get _valid => RegExp(r'^[6-9]\d{9}$').hasMatch(_ctrl.text.trim());

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final mobile = _ctrl.text.trim();
    final res = await ref.read(authControllerProvider.notifier).sendOtp(mobile, widget.role);
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (r) => context.push('/otp', extra: {
        'mobile': mobile,
        'role': widget.role,
        'devCode': r.devCode,
      }),
      err: (e) => showError(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.role == AppRole.driver;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (Navigator.of(context).canPop())
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(color: AppColors.cardSelectedBackground, shape: BoxShape.circle),
                  child: const Center(
                    child: _PinHomeIcon(size: 38),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Center(
                child: Text(
                  'Sri Balaji Travels',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isDriver ? 'Welcome, Driver!' : 'Welcome to Sri Balaji Travels',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                isDriver ? 'Sign in to start accepting rides.' : 'Your safe and reliable ride, always!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 32),
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _focus.hasFocus ? AppColors.primary : AppColors.inputBorder,
                    width: _focus.hasFocus ? 1.6 : 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text('🇮🇳', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    const Text('+91', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 15.5),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isCollapsed: true,
                          counterText: '',
                          hintText: 'Enter phone number',
                          hintStyle: TextStyle(color: AppColors.inkSoft),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Continue',
                busy: _busy,
                onPressed: _valid ? _send : null,
              ),
              const Spacer(),
              const Text(
                'By continuing, you agree to our Terms & Conditions and\nPrivacy Policy',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A location pin with a small home glyph inside — approximates the
/// reference's custom mark using stock Material icons (no image asset).
class _PinHomeIcon extends StatelessWidget {
  const _PinHomeIcon({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.location_on_outlined, size: size, color: AppColors.primary),
          Padding(
            padding: EdgeInsets.only(bottom: size * 0.38),
            child: Icon(Icons.home_rounded, size: size * 0.32, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
