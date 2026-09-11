import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// N-box OTP entry (default 6). Emits the full string via [onCompleted] and
/// every change via [onChanged]. Boxes flex to fit any width.
///
/// When [readOnly] is true the boxes never raise the OS keyboard — digits
/// only arrive via [OtpInputState.appendDigit]/[OtpInputState.backspace],
/// meant to be driven by an in-app numeric keypad (see otp_screen.dart).
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.autofocus = true,
    this.readOnly = false,
  });

  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool autofocus;
  final bool readOnly;

  @override
  State<OtpInput> createState() => OtpInputState();
}

class OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _c;
  late final List<FocusNode> _f;
  int _current = 0;

  /// Programmatically fill the boxes (e.g. the dev "Use code" shortcut).
  void setCode(String code) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    for (var k = 0; k < widget.length; k++) {
      _c[k].text = k < digits.length ? digits[k] : '';
    }
    _current = digits.length.clamp(0, widget.length - 1);
    FocusScope.of(context).unfocus();
    widget.onChanged?.call(_value);
    if (_value.length == widget.length) widget.onCompleted?.call(_value);
    setState(() {});
  }

  /// Appends one digit at the current box — used by an external numeric
  /// keypad when [OtpInput.readOnly] is true.
  void appendDigit(String d) {
    if (_current >= widget.length) return;
    _c[_current].text = d;
    if (_current < widget.length - 1) _current++;
    widget.onChanged?.call(_value);
    if (_value.length == widget.length) widget.onCompleted?.call(_value);
    setState(() {});
  }

  /// Clears the current box, or the previous one if the current is already
  /// empty — used by an external numeric keypad.
  void backspace() {
    if (_c[_current].text.isNotEmpty) {
      _c[_current].text = '';
    } else if (_current > 0) {
      _current--;
      _c[_current].text = '';
    }
    widget.onChanged?.call(_value);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _c = List.generate(widget.length, (_) => TextEditingController());
    _f = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    for (final f in _f) {
      f.dispose();
    }
    super.dispose();
  }

  String get _value => _c.map((c) => c.text).join();

  void _onChanged(int i, String v) {
    if (v.length > 1) {
      // paste
      final digits = v.replaceAll(RegExp(r'\D'), '');
      for (var k = 0; k < widget.length; k++) {
        _c[k].text = k < digits.length ? digits[k] : '';
      }
      FocusScope.of(context).unfocus();
    } else if (v.isNotEmpty && i < widget.length - 1) {
      _f[i + 1].requestFocus();
    } else if (v.isEmpty && i > 0) {
      _f[i - 1].requestFocus();
    }
    widget.onChanged?.call(_value);
    if (_value.length == widget.length) widget.onCompleted?.call(_value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(widget.length, (i) {
        final active = widget.readOnly && i == _current && _c[i].text.isEmpty;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: i == 0 ? 0 : 4,
              right: i == widget.length - 1 ? 0 : 4,
            ),
            child: widget.readOnly
                ? Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: active ? AppColors.primary : AppColors.line, width: active ? 1.6 : 1),
                    ),
                    child: active
                        ? const _BlinkingCursor()
                        : Text(_c[i].text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  )
                : TextField(
                    controller: _c[i],
                    focusNode: _f[i],
                    autofocus: widget.autofocus && i == 0,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _onChanged(i, v),
                  ),
          ),
        );
      }),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(width: 2, height: 20, color: AppColors.primary),
    );
  }
}
