import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/otp_input.dart';
import '../../state/providers.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    super.key,
    required this.mobile,
    required this.role,
    this.devCode,
  });

  final String mobile;
  final AppRole role;
  final String? devCode;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  String _code = '';
  bool _busy = false;
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _resendIn = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn == 0) {
        t.cancel();
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.length != 4) return;
    setState(() => _busy = true);
    final res = await ref
        .read(authControllerProvider.notifier)
        .verifyOtp(widget.mobile, widget.role, _code);
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (_) {
        // router redirect takes over once auth state flips
        context.go(widget.role == AppRole.driver ? '/d/dashboard' : '/c/home');
      },
      err: (e) => showError(context, e.message),
    );
  }

  Future<void> _resend() async {
    final res =
        await ref.read(authControllerProvider.notifier).sendOtp(widget.mobile, widget.role);
    if (!mounted) return;
    res.when(
      ok: (r) {
        _startTimer();
        showOk(context, r.devCode != null ? 'Code resent (dev: ${r.devCode})' : 'Code resent');
      },
      err: (e) => showError(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify number')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text('Enter the code', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text('Sent to +91 ${widget.mobile}',
                  style: const TextStyle(color: AppColors.inkSoft)),
              if (widget.devCode != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Dev code: ${widget.devCode}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
              const SizedBox(height: 32),
              OtpInput(
                onChanged: (v) => setState(() => _code = v),
                onCompleted: (_) => _verify(),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.center,
                child: _resendIn > 0
                    ? Text('Resend code in ${_resendIn}s',
                        style: const TextStyle(color: AppColors.inkSoft))
                    : TextButton(onPressed: _resend, child: const Text('Resend code')),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Verify',
                busy: _busy,
                onPressed: _code.length == 4 ? _verify : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
