import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/otp_input.dart';
import '../../state/providers.dart';

const _otpLength = 6;
const _resendCooldown = 45;

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
  final _fieldKey = GlobalKey<OtpInputState>();
  String _code = '';
  String? _devCode;
  bool _busy = false;
  int _resendIn = _resendCooldown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _devCode = widget.devCode;
    _startTimer();
  }

  void _startTimer() {
    _resendIn = _resendCooldown;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 0) {
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
    if (_code.length != _otpLength || _busy) return;
    setState(() => _busy = true);
    final res = await ref
        .read(authControllerProvider.notifier)
        .verifyOtp(widget.mobile, widget.role, _code);
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      // The router redirect takes over once auth state flips; this is a
      // belt-and-braces nudge for the common case.
      ok: (_) => context.go(
        widget.role == AppRole.driver ? '/d/dashboard' : '/c/home',
      ),
      err: (e) => showError(context, e.message),
    );
  }

  Future<void> _resend() async {
    if (_resendIn > 0) return;
    final res = await ref
        .read(authControllerProvider.notifier)
        .sendOtp(widget.mobile, widget.role);
    if (!mounted) return;
    res.when(
      ok: (r) {
        setState(() => _devCode = r.devCode);
        _startTimer();
        showOk(context, 'A new code has been sent');
      },
      err: (e) => showError(context, e.message),
    );
  }

  void _key(String d) {
    _fieldKey.currentState?.appendDigit(d);
  }

  void _backspace() {
    _fieldKey.currentState?.backspace();
  }

  String get _resendLabel {
    final m = (_resendIn ~/ 60).toString().padLeft(2, '0');
    final s = (_resendIn % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).canPop() ? Navigator.of(context).pop() : context.go('/role'),
                ),
              ),
              const SizedBox(height: 4),
              Text('Verify your number',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text("We've sent a 6-digit code to +91 ${widget.mobile}",
                  style: const TextStyle(color: AppColors.inkSoft)),
              if (_devCode != null) ...[
                const SizedBox(height: 16),
                _DevCodeCard(
                  code: _devCode!,
                  onUse: () {
                    _fieldKey.currentState?.setCode(_devCode!);
                    setState(() => _code = _devCode!);
                    _verify();
                  },
                ),
              ],
              const SizedBox(height: 28),
              OtpInput(
                key: _fieldKey,
                length: _otpLength,
                readOnly: true,
                onChanged: (v) => setState(() => _code = v),
                onCompleted: (_) => _verify(),
              ),
              const SizedBox(height: 20),
              Center(
                child: _resendIn > 0
                    ? Text('Resend in $_resendLabel', style: const TextStyle(color: AppColors.inkSoft))
                    : TextButton(
                        onPressed: _resend,
                        child: const Text('Resend code'),
                      ),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              ],
              const Spacer(),
              _Keypad(onDigit: _key, onBackspace: _backspace),
            ],
          ),
        ),
      ),
    );
  }
}

/// In-app numeric keypad — the reference uses this instead of the OS
/// keyboard so the OTP boxes stay visible above it at all times.
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: <Widget>[
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: _Key(label: row[i], onTap: () => onDigit(row[i]))),
                ],
              ],
            ),
          ),
        Row(
          children: [
            const Expanded(child: SizedBox()),
            const SizedBox(width: 10),
            Expanded(child: _Key(label: '0', onTap: () => onDigit('0'))),
            const SizedBox(width: 10),
            Expanded(child: _Key(icon: Icons.backspace_outlined, onTap: onBackspace)),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap});
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Center(
            child: label != null
                ? Text(label!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))
                : Icon(icon, size: 20, color: AppColors.inkSoft),
          ),
        ),
      ),
    );
  }
}

/// Development-only helper: shows the OTP the backend generated (returned as
/// `devCode` when the server is not in production) and lets you fill it in with
/// one tap. Never rendered in production because `devCode` is null there.
class _DevCodeCard extends StatelessWidget {
  const _DevCodeCard({required this.code, required this.onUse});
  final String code;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.construction_rounded,
              size: 18, color: AppColors.secondaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DEVELOPMENT OTP',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.secondaryDark)),
                const SizedBox(height: 2),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onUse, child: const Text('Use')),
        ],
      ),
    );
  }
}
