import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// LEGACY ALIAS — delegates to [EditorialTypography].
///
/// Existing files import `AppTypography.*`; this thin wrapper keeps them
/// compiling. The source-of-truth lives in `editorial_theme.dart`.
///
/// NOTE: All fields are `static final` (not `const`) because the underlying
/// `EditorialTypography` styles are now produced by `GoogleFonts.*()` at
/// runtime. Do NOT add new styles here.
abstract class AppTypography {
  // Display
  static final TextStyle displayLarge = EditorialTypography.displayLarge;
  static final TextStyle displayMedium = EditorialTypography.displayMedium;
  static final TextStyle displaySmall = EditorialTypography.displaySmall;

  // Headline
  static final TextStyle headlineLarge = EditorialTypography.headlineLarge;
  static final TextStyle headlineMedium = EditorialTypography.headlineMedium;
  static final TextStyle headlineSmall = EditorialTypography.headlineSmall;

  // Title
  static final TextStyle titleLarge = EditorialTypography.titleLarge;
  static final TextStyle titleMedium = EditorialTypography.titleMedium;
  static final TextStyle titleSmall = EditorialTypography.titleSmall;

  // Body
  static final TextStyle bodyLarge = EditorialTypography.bodyLarge;
  static final TextStyle bodyMedium = EditorialTypography.bodyMedium;
  static final TextStyle bodySmall = EditorialTypography.bodySmall;

  // Label
  static final TextStyle labelLarge = EditorialTypography.labelLarge;
  static final TextStyle labelMedium = EditorialTypography.labelMedium;
  static final TextStyle labelSmall = EditorialTypography.labelSmall;

  // Fintech-specific
  static final TextStyle currencyLarge = EditorialTypography.currencyLarge;
  static final TextStyle currencyMedium = EditorialTypography.currencyMedium;
  static final TextStyle currencySmall = EditorialTypography.currencySmall;
  static final TextStyle percentageChange = EditorialTypography.percentageChange;

  /// Build TextTheme — delegates to editorial system.
  static TextTheme buildTextTheme({required bool isDark}) =>
      EditorialTypography.buildTextTheme(isDark: isDark);
}
