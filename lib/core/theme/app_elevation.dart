import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Elevation tokens — "Quiet Hospitality".
///
/// The system has exactly two elevation expressions:
///
///   - **hairline** — a 1 px line at 6 % ink. Used as the universal
///     visual separator (dividers, section edges, card outlines).
///   - **whisper** — a single near-imperceptible drop shadow used for
///     elements that genuinely float (sheets, the FAB, snackbars).
///
/// Anything else is forbidden. Heavy stacked shadows, glow effects, and
/// gradient lifts are not part of the system.
abstract class AppElevation {
  /// 1 px hairline at 6 % ink.
  static const Color hairlineColor = EditorialColors.hairline;

  /// `BorderSide` form of [hairlineColor] for `Border`, `OutlinedBorder`, etc.
  static const BorderSide hairlineSide = BorderSide(
    color: hairlineColor,
    width: 1,
  );

  /// `Border.all` equivalent of [hairlineSide] (use for cards/inputs).
  static const Border hairlineBorder = Border.fromBorderSide(hairlineSide);

  /// The only drop shadow allowed in the system.
  static const List<BoxShadow> whisper = EditorialShadows.whisper;
}
