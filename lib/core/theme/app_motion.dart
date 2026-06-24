import 'package:flutter/animation.dart';

/// Motion tokens — "Quiet Hospitality".
///
/// Motion exists to clarify state changes, never to decorate. Two curves,
/// three durations, one press scale. No bounce. No parallax. No shimmer.
abstract class AppMotion {
  // ─────────────────────────────────────────────
  // Durations
  // ─────────────────────────────────────────────

  /// 90 ms — micro feedback (button press, ripple substitute).
  static const Duration micro = Duration(milliseconds: 90);

  /// 120 ms — exits (dismissals, fade-outs).
  static const Duration fast = Duration(milliseconds: 120);

  /// 180 ms — default enter (fade + small Y translation).
  static const Duration standard = Duration(milliseconds: 180);

  /// 240 ms — emphasised enter (modal sheet, page transition).
  static const Duration emphasised = Duration(milliseconds: 240);

  /// 1200 ms — skeleton pulse cycle.
  static const Duration skeletonPulse = Duration(milliseconds: 1200);

  // ─────────────────────────────────────────────
  // Curves
  // ─────────────────────────────────────────────

  /// The only enter curve.
  static const Curve enter = Curves.easeOutCubic;

  /// The only exit curve.
  static const Curve exit = Curves.easeInCubic;

  /// Press / release.
  static const Curve press = Curves.easeOut;

  // ─────────────────────────────────────────────
  // Geometry
  // ─────────────────────────────────────────────

  /// Default press scale for interactive elements.
  static const double pressScale = 0.98;

  /// Y-translation (in logical px) used for "rise on enter" animations.
  static const double enterTranslateY = 8;
}
