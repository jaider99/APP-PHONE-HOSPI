import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// LEGACY ALIAS — delegates to [EditorialRadius].
///
/// Existing files import `AppRadius.*`; this thin wrapper
/// keeps them compiling. Do NOT add new tokens here.
abstract class AppRadius {
  static const double xs = EditorialRadius.xs;
  static const double sm = EditorialRadius.sm;
  static const double md = EditorialRadius.md;
  static const double lg = EditorialRadius.standard;
  static const double xl = EditorialSpacing.xl; // 24 (legacy)
  static const double xxl = EditorialRadius.lg;  // 32
  static const double xxxl = EditorialRadius.xl; // 48
  static const double full = EditorialRadius.full;

  static const BorderRadius borderRadiusXs = EditorialRadius.borderRadiusXs;
  static const BorderRadius borderRadiusSm = EditorialRadius.borderRadiusSm;
  static const BorderRadius borderRadiusMd = EditorialRadius.borderRadiusMd;
  static const BorderRadius borderRadiusLg = EditorialRadius.borderRadiusStandard;
  static const BorderRadius borderRadiusXl = BorderRadius.all(Radius.circular(24));
  static const BorderRadius borderRadiusXxl = EditorialRadius.borderRadiusLg;
  static const BorderRadius borderRadiusXxxl = EditorialRadius.borderRadiusXl;
  static const BorderRadius borderRadiusFull = EditorialRadius.borderRadiusFull;

  static const BorderRadius borderRadiusTopLg = EditorialRadius.borderRadiusTopStandard;
  static const BorderRadius borderRadiusTopXl = BorderRadius.only(
    topLeft: Radius.circular(24),
    topRight: Radius.circular(24),
  );
  static const BorderRadius borderRadiusTopXxl = EditorialRadius.borderRadiusTopLg;
}

/// LEGACY ALIAS — delegates to [EditorialShadows].
abstract class AppShadows {
  static List<BoxShadow> get ambient => EditorialShadows.ambient;
  static List<BoxShadow> get ambientHigh => EditorialShadows.ambientHigh;

  static const List<BoxShadow> shadowSm = EditorialShadows.shadowSm;
  static const List<BoxShadow> shadowMd = EditorialShadows.shadowMd;
  static const List<BoxShadow> shadowLg = EditorialShadows.shadowLg;
  static const List<BoxShadow> shadowXl = EditorialShadows.shadowXl;
}
