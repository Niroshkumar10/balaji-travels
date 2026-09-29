import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The "Sri Balaji Travels" wordmark — a rounded red taxi badge plus
/// two-weight text (bold red "Sri Balaji", regular ink "Travels"). Single
/// source so the mark looks identical on the role picker, login, OTP and the
/// customer home top bar.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.iconSize = 30,
    this.fontSize = 20,
    this.stacked = false,
    this.compact = false,
    this.light = false,
    this.useImage = false,
  });

  /// Size of the taxi badge.
  final double iconSize;

  /// Base font size of the wordmark.
  final double fontSize;

  /// Puts "Travels" on its own line under "Sri Balaji" (role picker style).
  /// When false, both words sit on one line (compact headers).
  final bool stacked;

  /// Icon badge only, no wordmark — used in tight spaces.
  final bool compact;

  /// Use white text for the wordmark (dark backgrounds).
  final bool light;

  /// Show the real temple emblem (the app icon artwork) instead of the
  /// generic taxi glyph — used on the role picker's hero logo where there's
  /// room for the actual mark. Other call sites (login, OTP, home top bar)
  /// keep the compact taxi badge unchanged.
  final bool useImage;

  @override
  Widget build(BuildContext context) {
    final badge = useImage
        ? Image.asset('assets/icon/app_icon.png', width: iconSize, height: iconSize, fit: BoxFit.contain)
        : Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(iconSize * 0.3),
            ),
            child: Icon(Icons.local_taxi_rounded, color: Colors.white, size: iconSize * 0.6),
          );
    if (compact) return badge;

    final travelsColor = light ? Colors.white70 : AppColors.textPrimary;
    final wordmark = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sri Balaji',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  height: 1.05,
                ),
              ),
              Text(
                'Travels',
                style: TextStyle(
                  fontSize: fontSize * 0.7,
                  fontWeight: FontWeight.w500,
                  color: travelsColor,
                  height: 1.1,
                ),
              ),
            ],
          )
        : Text.rich(
            TextSpan(children: [
              TextSpan(
                text: 'Sri Balaji ',
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
              TextSpan(
                text: 'Travels',
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500, color: travelsColor),
              ),
            ]),
          );

    return Row(mainAxisSize: MainAxisSize.min, children: [badge, const SizedBox(width: 10), wordmark]);
  }
}
