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
  bool _busy = false;

  bool get _valid => RegExp(r'^[6-9]\d{9}$').hasMatch(_ctrl.text.trim());

  @override
  void dispose() {
    _ctrl.dispose();
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
      appBar: AppBar(title: Text(isDriver ? 'Driver sign in' : 'Sign in')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text('Enter your mobile number',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              const Text(
                "We'll send a 6-digit code to verify it.",
                style: TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  prefixText: '+91  ',
                  counterText: '',
                  hintText: '10-digit number',
                ),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Send code',
                busy: _busy,
                onPressed: _valid ? _send : null,
              ),
              const SizedBox(height: 12),
              const Text(
                'By continuing you agree to our Terms & Privacy Policy.',
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
