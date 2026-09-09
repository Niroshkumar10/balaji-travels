import 'package:flutter/material.dart';

/// Centralised colour system — the single source of truth for the whole app.
///
/// Nothing outside this file should declare a `Color(0x...)`. Screens use either
/// these constants or (preferably) `Theme.of(context)` values, which
/// `AppTheme` builds from these.
///
/// Visual balance target: ~60% white/light surfaces, ~25% dark/neutral text,
/// ~10% brand red (#C83228), ~5% yellow + status colours. Red is for primary
/// actions, active nav, selected states, brand marks and the map route — not
/// for every button/card/icon.
class AppColors {
  const AppColors._();

  // ── brand ──────────────────────────────────────────────────────────────
  static const primary = Color(0xFFC83228);
  static const primaryLight = Color(0xFFE05A52);
  static const primaryDark = Color(0xFFA5221A);
  static const secondary = Color(0xFFEAA828);
  static const secondaryLight = Color(0xFFF3C45D);
  static const secondaryDark = Color(0xFFC98B18);

  // ── background & surface ───────────────────────────────────────────────
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF8F9FA);
  static const surfaceVariant = Color(0xFFF1F3F5);
  static const card = Color(0xFFFFFFFF);
  static const overlay = Color(0x80000000);

  // ── text ──────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFF1E1E1E);
  static const textSecondary = Color(0xFF666666);
  static const textTertiary = Color(0xFF8A8A8A);
  static const textDisabled = Color(0xFFBDBDBD);
  static const textInverse = Color(0xFFFFFFFF);
  static const link = Color(0xFFC83228);

  // ── status ────────────────────────────────────────────────────────────
  static const success = Color(0xFF25D366);
  static const successDark = Color(0xFF1DA851);
  static const warning = Color(0xFFEAA828);
  static const warningDark = Color(0xFFC98B18);
  static const error = Color(0xFFD93025);
  static const errorDark = Color(0xFFB3261E);
  static const info = Color(0xFF1976D2);
  static const infoDark = Color(0xFF1259A6);

  // ── ride / booking status (semantic — use via statusColors.dart) ──────
  static const rideAvailable = Color(0xFF25D366);
  static const rideSearching = Color(0xFFEAA828);
  static const rideAssigned = Color(0xFF1976D2);
  static const rideArriving = Color(0xFFF57C00);
  static const rideStarted = Color(0xFFC83228);
  static const rideCompleted = Color(0xFF25D366);
  static const rideCancelled = Color(0xFFD93025);

  // ── map ───────────────────────────────────────────────────────────────
  static const mapRoute = Color(0xFFC83228);
  static const mapRouteSecondary = Color(0xFFEAA828);
  static const mapPickup = Color(0xFF25D366);
  static const mapDrop = Color(0xFFD93025);
  static const mapDriver = Color(0xFF1976D2);
  static const mapUser = Color(0xFF4285F4);

  // ── inputs ────────────────────────────────────────────────────────────
  static const inputBackground = Color(0xFFF8F9FA);
  static const inputBorder = Color(0xFFD9D9D9);
  static const inputFocusedBorder = Color(0xFFC83228);
  static const inputErrorBorder = Color(0xFFD93025);
  static const inputText = Color(0xFF1E1E1E);
  static const inputPlaceholder = Color(0xFF8A8A8A);
  static const inputIcon = Color(0xFF666666);

  // ── cards ─────────────────────────────────────────────────────────────
  static const cardBackground = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFEEEEEE);
  static const cardShadow = Color(0x14000000);
  static const cardSelectedBackground = Color(0xFFFFF3F2);
  static const cardSelectedBorder = Color(0xFFC83228);

  // ── buttons ───────────────────────────────────────────────────────────
  static const btnPrimaryBg = Color(0xFFC83228);
  static const btnPrimaryText = Color(0xFFFFFFFF);
  static const btnPrimaryPressed = Color(0xFFA5221A);
  static const btnDisabledBg = Color(0xFFE0E0E0);
  static const btnSecondaryBg = Color(0xFFEAA828);
  static const btnSecondaryText = Color(0xFF1E1E1E);
  static const btnSecondaryPressed = Color(0xFFC98B18);
  static const btnOutlineBorder = Color(0xFFC83228);
  static const btnOutlineText = Color(0xFFC83228);
  static const btnSuccessBg = Color(0xFF25D366);
  static const btnSuccessText = Color(0xFFFFFFFF);

  // ── notifications ─────────────────────────────────────────────────────
  static const notifBackground = Color(0xFFFFFFFF);
  static const notifUnread = Color(0xFFFFF3F2);
  static const notifIcon = Color(0xFFC83228);

  // ── dark mode ─────────────────────────────────────────────────────────
  static const darkBackground = Color(0xFF121212);
  static const darkSurface = Color(0xFF1E1E1E);
  static const darkSurfaceVariant = Color(0xFF2A2A2A);
  static const darkTextPrimary = Color(0xFFFFFFFF);
  static const darkTextSecondary = Color(0xFFBDBDBD);
  static const darkTextTertiary = Color(0xFF8A8A8A);
  static const darkPrimary = Color(0xFFE05A52);
  static const darkSecondary = Color(0xFFF3C45D);
  static const darkBorder = Color(0xFF383838);

  // ─────────────────────────────────────────────────────────────────────
  //  Back-compat aliases — existing screens use these short names. Kept so
  //  the theme update doesn't touch every widget. Prefer the names above
  //  (or Theme.of(context)) for new code.
  // ─────────────────────────────────────────────────────────────────────
  static const brand = primary;
  static const brandLight = primaryLight;
  static const accent = secondary;
  static const accentBright = secondaryLight;
  static const ink = textPrimary;
  static const inkSoft = textSecondary;
  static const canvas = surface;
  static const line = cardBorder;
  static const danger = error;
  static const darkCanvas = darkBackground;
  static const darkLine = darkBorder;
  static const darkInk = darkTextPrimary;
}
