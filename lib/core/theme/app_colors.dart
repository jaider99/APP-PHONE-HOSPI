import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// LEGACY ALIAS — delegates to [EditorialColors].
///
/// Existing files import `AppColors.*` everywhere; this thin wrapper
/// keeps them compiling while the source-of-truth lives in
/// `editorial_theme.dart`.  Do NOT add new tokens here.
abstract class AppColors {
  // PRIMARY PALETTE
  static const Color primary = EditorialColors.primary;
  static const Color onSurface = EditorialColors.onSurface;
  static const Color secondary = EditorialColors.accent;
  static const Color secondaryContainer = EditorialColors.accentContainer;
  static const Color secondaryLight = EditorialColors.accentLight;

  // PRIMARY VARIANTS
  static const Color primaryContainer = EditorialColors.surfaceContainerHigh;
  static const Color primaryDark = EditorialColors.onSurface;
  static const Color primaryLight = EditorialColors.outline;

  // SURFACE HIERARCHY
  static const Color background = EditorialColors.background;
  static const Color surfaceContainerLow = EditorialColors.surfaceContainerLow;
  static const Color surfaceContainerLowest = EditorialColors.surfaceContainerLowest;
  static const Color surfaceContainerHigh = EditorialColors.surfaceContainerHigh;

  // OUTLINES
  static const Color outline = EditorialColors.outline;
  static const Color outlineVariant = EditorialColors.outlineVariant;

  // SEMANTIC
  static const Color success = EditorialColors.accent;
  static const Color successLight = EditorialColors.successLight;
  static const Color warning = EditorialColors.warning;
  static const Color warningLight = EditorialColors.warningLight;
  static const Color error = EditorialColors.error;
  static const Color errorLight = EditorialColors.errorLight;
  static const Color errorContainer = EditorialColors.errorContainer;
  static const Color onErrorContainer = EditorialColors.onErrorContainer;
  static const Color info = EditorialColors.info;
  static const Color infoLight = EditorialColors.infoLight;

  // LIGHT THEME
  static const Color backgroundLight = EditorialColors.backgroundLight;
  static const Color surfaceLight = EditorialColors.surfaceLight;
  static const Color cardLight = EditorialColors.cardLight;
  static const Color dividerLight = EditorialColors.dividerLight;
  static const Color textPrimaryLight = EditorialColors.textPrimaryLight;
  static const Color textSecondaryLight = EditorialColors.textSecondaryLight;
  static const Color textTertiaryLight = EditorialColors.textTertiaryLight;

  // DARK THEME
  static const Color backgroundDark = EditorialColors.backgroundDark;
  static const Color surfaceDark = EditorialColors.surfaceDark;
  static const Color cardDark = EditorialColors.cardDark;
  static const Color dividerDark = EditorialColors.dividerDark;
  static const Color textPrimaryDark = EditorialColors.textPrimaryDark;
  static const Color textSecondaryDark = EditorialColors.textSecondaryDark;
  static const Color textTertiaryDark = EditorialColors.textTertiaryDark;

  // CHARTS
  static const Color chartPrimary = EditorialColors.chartPrimary;
  static const Color chartSecondary = EditorialColors.chartSecondary;
  static const Color chartBlue = EditorialColors.chartBlue;
  static const Color chartGreen = EditorialColors.chartGreen;
  static const Color chartOrange = EditorialColors.chartOrange;
  static const Color chartPurple = EditorialColors.chartPurple;
  static const Color chartPink = EditorialColors.chartPink;
  static const Color chartYellow = EditorialColors.chartYellow;
  static const List<Color> chartPalette = EditorialColors.chartPalette;

  // GRADIENTS
  static const LinearGradient primaryGradient = EditorialColors.accentGradient;
  static const LinearGradient cardGradient = EditorialColors.cardGradient;
}
