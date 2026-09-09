import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Builds the app's light + dark [ThemeData] from [AppColors].
///
/// Dark mode is fully defined but not auto-enabled — `app.dart` sets
/// `themeMode: ThemeMode.light`. Flip it to `ThemeMode.system` (or add a
/// toggle) to turn dark on without any redesign.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;

    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final card = isDark ? AppColors.darkSurface : AppColors.card;
    final border = isDark ? AppColors.darkBorder : AppColors.cardBorder;
    final inputBorder = isDark ? AppColors.darkBorder : AppColors.inputBorder;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final primary = isDark ? AppColors.darkPrimary : AppColors.primary;
    final secondary = isDark ? AppColors.darkSecondary : AppColors.secondary;

    final scheme = ColorScheme(
      brightness: b,
      primary: primary,
      onPrimary: AppColors.textInverse,
      primaryContainer: isDark ? AppColors.primaryDark : AppColors.cardSelectedBackground,
      onPrimaryContainer: isDark ? AppColors.textInverse : AppColors.primaryDark,
      secondary: secondary,
      onSecondary: AppColors.textPrimary,
      secondaryContainer: AppColors.secondaryLight,
      onSecondaryContainer: AppColors.secondaryDark,
      tertiary: AppColors.info,
      onTertiary: AppColors.textInverse,
      error: isDark ? AppColors.error : AppColors.error,
      onError: AppColors.textInverse,
      errorContainer: AppColors.notifUnread,
      onErrorContainer: AppColors.errorDark,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: border,
      shadow: Colors.black,
      scrim: AppColors.overlay,
      inverseSurface: isDark ? AppColors.background : AppColors.darkBackground,
      onInverseSurface: isDark ? AppColors.textPrimary : AppColors.darkTextPrimary,
      inversePrimary: isDark ? AppColors.primary : AppColors.primaryLight,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);

    final textTheme = base.textTheme.apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: border,
      textTheme: textTheme,
      primaryColor: primary,
      hintColor: AppColors.inputPlaceholder,

      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),

      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shadowColor: AppColors.cardShadow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.inputBackground,
        hintStyle: const TextStyle(color: AppColors.inputPlaceholder),
        prefixIconColor: AppColors.inputIcon,
        suffixIconColor: AppColors.inputIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.inputFocusedBorder, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.inputErrorBorder),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.inputErrorBorder, width: 1.6),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.btnPrimaryBg,
          foregroundColor: AppColors.btnPrimaryText,
          disabledBackgroundColor: AppColors.btnDisabledBg,
          disabledForegroundColor: AppColors.textDisabled,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.pressed)
                ? AppColors.btnPrimaryPressed.withValues(alpha: 0.9)
                : null,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.btnPrimaryBg,
          foregroundColor: AppColors.btnPrimaryText,
          disabledBackgroundColor: AppColors.btnDisabledBg,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.btnOutlineText,
          side: const BorderSide(color: AppColors.btnOutlineBorder),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: textPrimary),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        selectedColor: AppColors.cardSelectedBackground,
        secondarySelectedColor: AppColors.cardSelectedBackground,
        checkmarkColor: AppColors.primary,
        labelStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
        contentTextStyle: TextStyle(fontSize: 14, color: textSecondary, height: 1.4),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
        dragHandleColor: border,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: primary,
        unselectedItemColor: AppColors.textTertiary,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: AppColors.cardSelectedBackground,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? primary : AppColors.textTertiary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? primary : AppColors.textTertiary,
          ),
        ),
      ),

      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: AppColors.inputIcon,
        textColor: textPrimary,
        titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
        subtitleTextStyle: TextStyle(fontSize: 13, color: textSecondary),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary.withValues(alpha: 0.4) : null,
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        circularTrackColor: Color(0x1FC83228),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: AppColors.textInverse),
        actionTextColor: AppColors.secondaryLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.cardSelectedBackground : card,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : textSecondary,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: AppColors.textTertiary,
        indicatorColor: primary,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: AppColors.textInverse, fontSize: 12),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textInverse,
      ),
    );
  }
}
