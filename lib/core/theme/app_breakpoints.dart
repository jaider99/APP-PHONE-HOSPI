import 'package:flutter/widgets.dart';

/// Layout breakpoints.
///
/// Mobile-first. The app is primarily a phone experience; the larger
/// breakpoints exist so foldables and tablets get sensible max-widths
/// instead of stretched single-column layouts.
abstract class AppBreakpoints {
  /// Compact phones.
  static const double sm = 360;

  /// Standard phones.
  static const double md = 480;

  /// Large phones / small foldables.
  static const double lg = 640;

  /// Tablets / unfolded foldables.
  static const double xl = 840;

  /// Desktop / web preview.
  static const double xxl = 1200;

  /// Maximum content width on any device.
  static const double contentMax = 720;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < md;

  static bool isMedium(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= md && w < lg;
  }

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= lg;
}
