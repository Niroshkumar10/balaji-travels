import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// N-box OTP entry (default 6). Emits the full string via [onCompleted] and
/// every change via [onChanged]. Boxes flex to fit any width.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool autofocus;

  @override
  State<OtpInput> createState() => OtpInputState();
}

class OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _c;
  late final List<FocusNode> _f;

  /// Programmatically fill the boxes (e.g. the dev "Use code" shortcut).
  void setCode(String code) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    for (var k = 0; k < widget.length; k++) {
      _c[k].text = k < digits.length ? digits[k] : '';
    }
    FocusScope.of(context).unfocus();
    widget.onChanged?.call(_value);
    if (_value.length == widget.length) widget.onCompleted?.call(_value);
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
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: i == 0 ? 0 : 4,
              right: i == widget.length - 1 ? 0 : 4,
            ),
            child: TextField(
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
