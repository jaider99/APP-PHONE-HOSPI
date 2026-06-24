import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Quiet Hospitality" Design System — single source of truth.
///
/// This file deliberately keeps every public symbol from the previous
/// `editorial_theme.dart` so that ~200 existing call sites continue to
/// compile while inheriting the new warm-monochrome look.
///
/// Naming legend (mapping old name → new intent):
///   primary              → ink (#1A1A1A, deep charcoal)
///   onPrimary            → bone (text on ink CTA)
///   background / surface → bone (#F7F6F3, warm canvas)
///   surfaceContainer*    → paper / sand (tonal layering)
///   outline              → inkSubtle (#807A73)
///   outlineVariant       → near-hairline grey
///   accent / secondary   → deep teal (#2F4A43) — used sparingly
///   success / error / warning / info → muted ink-on-soft pairs
///   *Gradient            → degenerated to solid colour (gradients banned)
///   *Shadow              → near-imperceptible whisper (heavy shadows banned)
abstract class EditorialColors {
  // ============================================
  // CORE PALETTE — Neobank monochrome + soft green accent
  // ============================================

  /// Hero action / primary text — deep ink (never pure black).
  static const Color primary = Color(0xFF151515);

  /// Text/icon colour on primary CTA — pure white reads cleanly on ink.
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Used for elevated containers historically.
  static const Color primaryContainer = Color(0xFFF1F1EE);

  /// Foreground on primaryContainer.
  static const Color onPrimaryContainer = Color(0xFF151515);

  // ============================================
  // SURFACE HIERARCHY (clean warm-neutral layering)
  // ============================================

  /// Base canvas — soft warm off-white.
  static const Color background = Color(0xFFFAFAF8);

  /// Main surface (alias of background).
  static const Color surface = Color(0xFFFAFAF8);

  /// Elevated paper — pure white for cards & sheets.
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);

  /// Quiet section grouping.
  static const Color surfaceContainerLow = Color(0xFFF5F4F1);

  /// Standard container.
  static const Color surfaceContainer = Color(0xFFF1F0EC);

  /// Elevated surface tier.
  static const Color surfaceContainerHigh = Color(0xFFEDECE8);

  /// Highest elevation tier.
  static const Color surfaceContainerHighest = Color(0xFFE7E5E0);

  /// Bright (same as background).
  static const Color surfaceBright = background;

  /// Dim surface.
  static const Color surfaceDim = Color(0xFFE1DFDA);

  // ============================================
  // TEXT COLOURS
  // ============================================

  /// Primary text — deep ink.
  static const Color onSurface = Color(0xFF151515);

  /// Secondary text — muted neutral.
  static const Color onSurfaceVariant = Color(0xFF8C8C89);

  /// Tertiary text role (kept for back-compat with Material colour scheme).
  static const Color tertiary = Color(0xFF8C8C89);

  /// Foreground on tertiary fills.
  static const Color onTertiary = Color(0xFFFFFFFF);

  // ============================================
  // OUTLINES (hairlines only — never visible borders)
  // ============================================

  /// Primary outline / placeholder text.
  static const Color outline = Color(0xFFA8A8A4);

  /// Hairline-grade outline (use at low opacity).
  static const Color outlineVariant = Color(0xFFE2E1DD);

  /// Authoritative hairline used for dividers (≈ ink @ 6%).
  static const Color hairline = Color(0x0F000000);

  // ============================================
  // SECONDARY ROLE — quiet, neutral
  // ============================================

  static const Color secondary = Color(0xFF323230);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFF1F1EE);
  static const Color onSecondaryContainer = Color(0xFF151515);

  // ============================================
  // TERTIARY ROLE
  // ============================================

  static const Color tertiaryContainer = Color(0xFFF1F0EC);
  static const Color onTertiaryContainer = Color(0xFF151515);

  // ============================================
  // SEMANTIC: ERROR / SUCCESS / WARNING / INFO
  //
  // Muted, neobank-grade financial reds, greens, ambers, blues.
  // ============================================

  static const Color error = Color(0xFFB23A3A);              // negInk
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFCEAEA);     // negSoft
  static const Color onErrorContainer = Color(0xFF7A2828);
  static const Color errorLight = Color(0xFFFCEAEA);

  static const Color success = Color(0xFF1F8F5C);            // financial green
  static const Color onSuccess = Color(0xFFFFFFFF);
  static const Color successContainer = Color(0xFFE6F4EC);   // posSoft
  static const Color successLight = Color(0xFFE6F4EC);

  static const Color warning = Color(0xFFB07A1A);            // muted amber
  static const Color warningLight = Color(0xFFFBF1DD);       // warnSoft

  static const Color info = Color(0xFF2F6BB0);               // muted blue
  static const Color infoLight = Color(0xFFE6EEF8);          // infoSoft

  // ============================================
  // ACCENT — single brand accent (soft financial green)
  // Use sparingly: focus rings, single chart series, key links.
  // ============================================

  static const Color accent = Color(0xFF1F8F5C);
  static const Color accentLight = Color(0xFFE6F4EC);
  static const Color accentContainer = Color(0xFFE6F4EC);

  // ============================================
  // INVERSE COLOURS (snackbars, tooltips on dark)
  // ============================================

  static const Color inverseSurface = Color(0xFF1A1A1A);
  static const Color inverseOnSurface = Color(0xFFF7F6F3);
  static const Color inversePrimary = Color(0xFFEFEDE7);

  // ============================================
  // CHART PALETTE
  // Single accent + neutral inks + muted semantic pairs.
  // No saturated orange/purple/pink/yellow.
  // ============================================

  static const Color chartPrimary = accent;
  static const Color chartSecondary = onSurfaceVariant;
  static const Color chartBlue = info;
  static const Color chartGreen = success;
  static const Color chartOrange = warning;
  static const Color chartPurple = onSurfaceVariant;
  static const Color chartPink = error;
  static const Color chartYellow = warning;

  static const List<Color> chartPalette = <Color>[
    accent,
    onSurfaceVariant,
    success,
    error,
    warning,
    info,
  ];

  // ============================================
  // GRADIENTS — KILLED.
  // Kept as named constants for back-compat; both stops are the same
  // colour so nothing actually renders a gradient on screen.
  // ============================================

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[primary, primary],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[surfaceContainerLowest, surfaceContainerLowest],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[accent, accent],
  );

  // ============================================
  // DARK THEME MAPPINGS
  // Warm dark variant — left lightly tuned in P1, polished in P9.
  // ============================================

  static const Color backgroundDark = Color(0xFF14130F);
  static const Color surfaceDark = Color(0xFF1B1A16);
  static const Color cardDark = Color(0xFF22211C);
  static const Color dividerDark = Color(0xFF2E2C26);
  static const Color textPrimaryDark = Color(0xFFEFEDE7);
  static const Color textSecondaryDark = Color(0xFFB5B0A6);
  static const Color textTertiaryDark = Color(0xFF807A73);

  // ============================================
  // LIGHT THEME CONVENIENCE ALIASES
  // ============================================

  static const Color backgroundLight = background;
  static const Color surfaceLight = surfaceContainerLowest;
  static const Color cardLight = surfaceContainerLowest;
  static const Color dividerLight = Color(0xFFE2E1DD);
  static const Color textPrimaryLight = onSurface;
  static const Color textSecondaryLight = onSurfaceVariant;
  static const Color textTertiaryLight = outline;
}

/// Quiet Hospitality Typography.
///
/// Three roles:
///   - **display** — Fraunces (serif), for screen titles and large hero values.
///   - **sans**    — Geist, for everything UI: titles, body, labels.
///   - **mono**    — Geist Mono, for every numeric value (tabular figures).
///
/// All numeric styles enable `FontFeature.tabularFigures()` so columns of
/// currency line up correctly.
///
/// NOTE: TextStyles are `static final` (not `const`) because they originate
/// from `GoogleFonts.*()`, which loads fonts at runtime. Consumers who used
/// these styles as runtime values (`style: EditorialTypography.bodyMedium`)
/// continue to work unchanged.
abstract class EditorialTypography {
  // Family names exposed for any consumer that needs the raw string.
  static const String displayFontName = 'Fraunces';
  static const String sansFontName = 'Sora';
  static const String monoFontName = 'DM Mono';

  // Legacy aliases — kept for back-compat.
  static const String headlineFont = displayFontName;
  static const String bodyFont = sansFontName;

  // ============================================
  // Internal factory helpers
  // ============================================

  // Display tier now uses Sora sans (neobank direction). Fraunces serif is
  // retired from product UI — kept reachable only via [GoogleFonts.fraunces]
  // if a marketing surface ever needs an editorial moment.
  static TextStyle _display({
    required double size,
    required double height,
    double letterSpacing = -1,
    FontWeight weight = FontWeight.w600,
    Color color = EditorialColors.onSurface,
  }) {
    return GoogleFonts.sora(
      fontSize: size,
      height: height / size,
      letterSpacing: letterSpacing,
      fontWeight: weight,
      color: color,
    );
  }

  static TextStyle _sans({
    required double size,
    required double height,
    double letterSpacing = 0,
    FontWeight weight = FontWeight.w400,
    Color color = EditorialColors.onSurface,
  }) {
    return GoogleFonts.sora(
      fontSize: size,
      height: height / size,
      letterSpacing: letterSpacing,
      fontWeight: weight,
      color: color,
    );
  }

  static TextStyle _mono({
    required double size,
    required double height,
    double letterSpacing = 0,
    FontWeight weight = FontWeight.w500,
    Color color = EditorialColors.onSurface,
  }) {
    return GoogleFonts.dmMono(
      fontSize: size,
      height: height / size,
      letterSpacing: letterSpacing,
      fontWeight: weight,
      color: color,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }

  // ============================================
  // DISPLAY — Sora sans, screen heroes
  // ============================================

  static final TextStyle displayLarge = _display(
    size: 40,
    height: 44,
    letterSpacing: -1.2,
    weight: FontWeight.w600,
  );

  static final TextStyle displayMedium = _display(
    size: 32,
    height: 36,
    letterSpacing: -0.9,
    weight: FontWeight.w600,
  );

  static final TextStyle displaySmall = _display(
    size: 26,
    height: 30,
    letterSpacing: -0.6,
    weight: FontWeight.w600,
  );

  // ============================================
  // HEADLINE — Sora sans, section heroes
  // ============================================

  static final TextStyle headlineLarge = _display(
    size: 26,
    height: 30,
    letterSpacing: -0.6,
    weight: FontWeight.w600,
  );

  static final TextStyle headlineMedium = _display(
    size: 22,
    height: 26,
    letterSpacing: -0.4,
    weight: FontWeight.w600,
  );

  static final TextStyle headlineSmall = _display(
    size: 18,
    height: 24,
    letterSpacing: -0.2,
    weight: FontWeight.w600,
  );

  // ============================================
  // TITLE — Geist sans, card/section headers
  // ============================================

  static final TextStyle titleLarge = _sans(
    size: 18,
    height: 24,
    letterSpacing: -0.2,
    weight: FontWeight.w600,
  );

  static final TextStyle titleMedium = _sans(
    size: 16,
    height: 22,
    letterSpacing: -0.1,
    weight: FontWeight.w600,
  );

  static final TextStyle titleSmall = _sans(
    size: 14,
    height: 20,
    letterSpacing: 0,
    weight: FontWeight.w600,
  );

  // ============================================
  // BODY — Geist sans, prose & UI text
  // ============================================

  static final TextStyle bodyLarge = _sans(
    size: 16,
    height: 24,
    weight: FontWeight.w400,
  );

  static final TextStyle bodyMedium = _sans(
    size: 14,
    height: 20,
    weight: FontWeight.w400,
  );

  static final TextStyle bodySmall = _sans(
    size: 12,
    height: 16,
    weight: FontWeight.w400,
    color: EditorialColors.onSurfaceVariant,
  );

  // ============================================
  // LABEL — Geist sans, button & control text
  // ============================================

  static final TextStyle labelLarge = _sans(
    size: 14,
    height: 18,
    letterSpacing: 0.1,
    weight: FontWeight.w600,
  );

  static final TextStyle labelMedium = _sans(
    size: 12,
    height: 16,
    letterSpacing: 0.2,
    weight: FontWeight.w600,
  );

  static final TextStyle labelSmall = _sans(
    size: 11,
    height: 14,
    letterSpacing: 0.4,
    weight: FontWeight.w600,
    color: EditorialColors.onSurfaceVariant,
  );

  // ============================================
  // FINTECH — every numeric value uses Geist Mono w/ tabular figures
  // ============================================

  /// Hero currency on dashboard.
  static final TextStyle currencyLarge = _mono(
    size: 38,
    height: 42,
    letterSpacing: -1.0,
    weight: FontWeight.w500,
  );

  /// Section-level currency.
  static final TextStyle currencyMedium = _mono(
    size: 22,
    height: 26,
    letterSpacing: -0.3,
    weight: FontWeight.w500,
  );

  /// In-row currency.
  static final TextStyle currencySmall = _mono(
    size: 15,
    height: 22,
    weight: FontWeight.w500,
  );

  /// Δ% indicator.
  static final TextStyle percentageChange = _mono(
    size: 12,
    height: 16,
    letterSpacing: 0.2,
    weight: FontWeight.w500,
  );

  /// Build a Material [TextTheme] wired to the type scale.
  static TextTheme buildTextTheme({required bool isDark}) {
    final Color textColor = isDark
        ? EditorialColors.textPrimaryDark
        : EditorialColors.textPrimaryLight;

    return TextTheme(
      displayLarge: displayLarge.copyWith(color: textColor),
      displayMedium: displayMedium.copyWith(color: textColor),
      displaySmall: displaySmall.copyWith(color: textColor),
      headlineLarge: headlineLarge.copyWith(color: textColor),
      headlineMedium: headlineMedium.copyWith(color: textColor),
      headlineSmall: headlineSmall.copyWith(color: textColor),
      titleLarge: titleLarge.copyWith(color: textColor),
      titleMedium: titleMedium.copyWith(color: textColor),
      titleSmall: titleSmall.copyWith(color: textColor),
      bodyLarge: bodyLarge.copyWith(color: textColor),
      bodyMedium: bodyMedium.copyWith(color: textColor),
      bodySmall: bodySmall.copyWith(
        color: isDark
            ? EditorialColors.textSecondaryDark
            : EditorialColors.onSurfaceVariant,
      ),
      labelLarge: labelLarge.copyWith(color: textColor),
      labelMedium: labelMedium.copyWith(color: textColor),
      labelSmall: labelSmall.copyWith(
        color: isDark
            ? EditorialColors.textSecondaryDark
            : EditorialColors.onSurfaceVariant,
      ),
    );
  }
}

/// Spacing tokens — 4 / 8 / 12 / 16 / 24 / 32 / 48.
abstract class EditorialSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;

  static const double screenPadding = xl;
  static const double sectionSpacing = xxl;
  static const double ctaClearance = xxl;
}

/// Radius tokens — 6 / 10 / 14 / 20. Pill radii removed from primary CTAs;
/// `full` is preserved for chips and the OAuth button row.
abstract class EditorialRadius {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;

  /// Standard card / sheet corner radius.
  static const double standard = 14;

  /// Large radius (full-bleed sheets only).
  static const double lg = 20;

  /// XL — kept for back-compat; clamped to 20.
  static const double xl = 20;

  /// Circular — used only for pills, chips, OAuth buttons.
  static const double full = 9999;

  // Pre-built BorderRadius
  static const BorderRadius borderRadiusXs =
      BorderRadius.all(Radius.circular(xs));
  static const BorderRadius borderRadiusSm =
      BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderRadiusMd =
      BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderRadiusStandard =
      BorderRadius.all(Radius.circular(standard));
  static const BorderRadius borderRadiusLg =
      BorderRadius.all(Radius.circular(lg));
  static const BorderRadius borderRadiusXl =
      BorderRadius.all(Radius.circular(xl));
  static const BorderRadius borderRadiusFull =
      BorderRadius.all(Radius.circular(full));

  static const BorderRadius borderRadiusTopStandard = BorderRadius.only(
    topLeft: Radius.circular(standard),
    topRight: Radius.circular(standard),
  );
  static const BorderRadius borderRadiusTopLg = BorderRadius.only(
    topLeft: Radius.circular(lg),
    topRight: Radius.circular(lg),
  );
  static const BorderRadius borderRadiusTopXl = BorderRadius.only(
    topLeft: Radius.circular(xl),
    topRight: Radius.circular(xl),
  );
}

/// Elevation tokens.
///
/// Depth is felt, not seen. Every public name from the old `EditorialShadows`
/// resolves to either a one-pixel hairline or a barely-perceptible whisper
/// (≤4 px blur, ≤4% opacity). Heavy multi-stop shadows are gone.
abstract class EditorialShadows {
  /// 1 px hairline at 6% — the default "border" of the whole system.
  static const List<BoxShadow> hairline = <BoxShadow>[
    BoxShadow(color: EditorialColors.hairline, blurRadius: 0, offset: Offset(0, 1)),
  ];

  /// A single near-imperceptible whisper for cards and floating chrome.
  static const List<BoxShadow> whisper = <BoxShadow>[
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  // ---- Back-compat aliases (all now map to `whisper`/`hairline`) ----

  static const List<BoxShadow> cardShadow = whisper;
  static List<BoxShadow> get ambient => whisper;
  static List<BoxShadow> get ambientHigh => whisper;
  static const List<BoxShadow> inputShadow = whisper;
  static const List<BoxShadow> ctaShadow = whisper;
  static const List<BoxShadow> buttonShadow = whisper;
  static const List<BoxShadow> shadowSm = whisper;
  static const List<BoxShadow> shadowMd = whisper;
  static const List<BoxShadow> shadowLg = whisper;
  static const List<BoxShadow> shadowXl = whisper;
}
