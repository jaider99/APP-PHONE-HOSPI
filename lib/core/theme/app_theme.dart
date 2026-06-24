import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Main theme configuration — powered by the Editorial Design System.
///
/// All component themes derive from [EditorialColors], [EditorialTypography],
/// [EditorialRadius], and [EditorialShadows]. Individual files keep importing
/// the old `AppColors` / `AppTypography` / `AppRadius` names, which are now
/// thin aliases re-exporting the editorial tokens.
abstract class AppTheme {
  /// Light theme configuration
  static ThemeData get lightTheme {
    final textTheme = EditorialTypography.buildTextTheme(isDark: false);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: _lightColorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: EditorialColors.background,
      appBarTheme: _appBarTheme(isDark: false),
      cardTheme: _cardTheme(isDark: false),
      elevatedButtonTheme: _elevatedButtonTheme(isDark: false),
      outlinedButtonTheme: _outlinedButtonTheme(isDark: false),
      textButtonTheme: _textButtonTheme(isDark: false),
      inputDecorationTheme: _inputDecorationTheme(isDark: false),
      bottomNavigationBarTheme: _bottomNavTheme(isDark: false),
      navigationBarTheme: _navigationBarTheme(isDark: false),
      floatingActionButtonTheme: _fabTheme(isDark: false),
      dividerTheme: _dividerTheme(isDark: false),
      chipTheme: _chipTheme(isDark: false),
      dialogTheme: _dialogTheme(isDark: false),
      bottomSheetTheme: _bottomSheetTheme(isDark: false),
      snackBarTheme: _snackBarTheme(isDark: false),
    );
  }

  /// Dark theme configuration
  static ThemeData get darkTheme {
    final textTheme = EditorialTypography.buildTextTheme(isDark: true);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _darkColorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: EditorialColors.backgroundDark,
      appBarTheme: _appBarTheme(isDark: true),
      cardTheme: _cardTheme(isDark: true),
      elevatedButtonTheme: _elevatedButtonTheme(isDark: true),
      outlinedButtonTheme: _outlinedButtonTheme(isDark: true),
      textButtonTheme: _textButtonTheme(isDark: true),
      inputDecorationTheme: _inputDecorationTheme(isDark: true),
      bottomNavigationBarTheme: _bottomNavTheme(isDark: true),
      navigationBarTheme: _navigationBarTheme(isDark: true),
      floatingActionButtonTheme: _fabTheme(isDark: true),
      dividerTheme: _dividerTheme(isDark: true),
      chipTheme: _chipTheme(isDark: true),
      dialogTheme: _dialogTheme(isDark: true),
      bottomSheetTheme: _bottomSheetTheme(isDark: true),
      snackBarTheme: _snackBarTheme(isDark: true),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // COLOR SCHEMES — Editorial monochromatic + semantic accents
  // ══════════════════════════════════════════════════════════════

  static const ColorScheme _lightColorScheme = ColorScheme.light(
    primary: EditorialColors.primary,
    onPrimary: EditorialColors.onPrimary,
    primaryContainer: EditorialColors.primaryContainer,
    onPrimaryContainer: EditorialColors.onPrimaryContainer,
    secondary: EditorialColors.secondary,
    onSecondary: EditorialColors.onSecondary,
    secondaryContainer: EditorialColors.secondaryContainer,
    onSecondaryContainer: EditorialColors.onSecondaryContainer,
    tertiary: EditorialColors.tertiary,
    onTertiary: EditorialColors.onTertiary,
    tertiaryContainer: EditorialColors.tertiaryContainer,
    onTertiaryContainer: EditorialColors.onTertiaryContainer,
    surface: EditorialColors.surfaceContainerLowest,
    onSurface: EditorialColors.onSurface,
    surfaceContainerLowest: EditorialColors.surfaceContainerLowest,
    surfaceContainerLow: EditorialColors.surfaceContainerLow,
    surfaceContainer: EditorialColors.surfaceContainer,
    surfaceContainerHigh: EditorialColors.surfaceContainerHigh,
    surfaceContainerHighest: EditorialColors.surfaceContainerHighest,
    error: EditorialColors.error,
    onError: EditorialColors.onError,
    errorContainer: EditorialColors.errorContainer,
    onErrorContainer: EditorialColors.onErrorContainer,
    outline: EditorialColors.dividerLight,
    outlineVariant: EditorialColors.outlineVariant,
    inverseSurface: EditorialColors.inverseSurface,
    onInverseSurface: EditorialColors.inverseOnSurface,
    inversePrimary: EditorialColors.inversePrimary,
  );

  static const ColorScheme _darkColorScheme = ColorScheme.dark(
    primary: EditorialColors.inversePrimary,
    onPrimary: EditorialColors.onPrimary,
    primaryContainer: EditorialColors.primaryContainer,
    onPrimaryContainer: EditorialColors.onPrimaryContainer,
    secondary: EditorialColors.accentLight,
    onSecondary: Colors.white,
    secondaryContainer: EditorialColors.cardDark,
    onSecondaryContainer: EditorialColors.textPrimaryDark,
    surface: EditorialColors.surfaceDark,
    onSurface: EditorialColors.textPrimaryDark,
    error: EditorialColors.error,
    onError: EditorialColors.onError,
    errorContainer: EditorialColors.errorLight,
    onErrorContainer: EditorialColors.error,
    outline: EditorialColors.dividerDark,
    outlineVariant: EditorialColors.dividerDark,
  );

  // ══════════════════════════════════════════════════════════════
  // COMPONENT THEMES
  // ══════════════════════════════════════════════════════════════

  static AppBarTheme _appBarTheme({required bool isDark}) {
    return AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor:
          isDark ? EditorialColors.backgroundDark : EditorialColors.background,
      foregroundColor:
          isDark ? EditorialColors.textPrimaryDark : EditorialColors.onSurface,
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: EditorialTypography.titleLarge.copyWith(
        color: isDark
            ? EditorialColors.textPrimaryDark
            : EditorialColors.onSurface,
      ),
    );
  }

  static CardThemeData _cardTheme({required bool isDark}) {
    return CardThemeData(
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: EditorialRadius.borderRadiusStandard,
      ),
      color: isDark ? EditorialColors.cardDark : EditorialColors.cardLight,
      margin: EdgeInsets.zero,
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme({required bool isDark}) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const RoundedRectangleBorder(
          borderRadius: EditorialRadius.borderRadiusSm,
        ),
        backgroundColor: EditorialColors.primary,
        foregroundColor: EditorialColors.onPrimary,
        textStyle: EditorialTypography.labelLarge,
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme({required bool isDark}) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const RoundedRectangleBorder(
          borderRadius: EditorialRadius.borderRadiusSm,
        ),
        side: BorderSide(
          color: isDark
              ? EditorialColors.dividerDark
              : EditorialColors.outlineVariant.withOpacity(0.5),
        ),
        foregroundColor:
            isDark ? EditorialColors.textPrimaryDark : EditorialColors.onSurface,
        textStyle: EditorialTypography.labelLarge,
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme({required bool isDark}) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const RoundedRectangleBorder(
          borderRadius: EditorialRadius.borderRadiusSm,
        ),
        foregroundColor: EditorialColors.primary,
        textStyle: EditorialTypography.labelLarge,
      ),
    );
  }

  static InputDecorationTheme _inputDecorationTheme({required bool isDark}) {
    // Editorial: inputs are pure white on #F9F9F9 background.
    // No visible border — focus uses ghost border at 10% opacity.
    final fillColor = isDark
        ? EditorialColors.surfaceDark
        : EditorialColors.surfaceContainerLowest;

    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: EditorialRadius.borderRadiusSm,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: EditorialRadius.borderRadiusSm,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: EditorialRadius.borderRadiusSm,
        borderSide: BorderSide(
          color: EditorialColors.primary.withOpacity(0.20),
          width: 1.2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: EditorialRadius.borderRadiusSm,
        borderSide: BorderSide(
          color: EditorialColors.error.withOpacity(0.4),
        ),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: EditorialRadius.borderRadiusSm,
        borderSide: BorderSide(color: EditorialColors.error, width: 1.2),
      ),
      hintStyle: EditorialTypography.bodyMedium.copyWith(
        color: isDark
            ? EditorialColors.textTertiaryDark
            : EditorialColors.outline,
      ),
      labelStyle: EditorialTypography.bodyMedium.copyWith(
        color: isDark
            ? EditorialColors.textSecondaryDark
            : EditorialColors.onSurfaceVariant,
      ),
    );
  }

  static BottomNavigationBarThemeData _bottomNavTheme({required bool isDark}) {
    return BottomNavigationBarThemeData(
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      backgroundColor: isDark
          ? EditorialColors.surfaceDark
          : EditorialColors.surfaceContainerLowest,
      selectedItemColor: EditorialColors.primary,
      unselectedItemColor:
          isDark ? EditorialColors.textTertiaryDark : EditorialColors.outline,
      selectedLabelStyle: EditorialTypography.labelSmall,
      unselectedLabelStyle: EditorialTypography.labelSmall,
    );
  }

  static NavigationBarThemeData _navigationBarTheme({required bool isDark}) {
    return NavigationBarThemeData(
      elevation: 0,
      backgroundColor: isDark
          ? EditorialColors.surfaceDark
          : EditorialColors.surfaceContainerLowest,
      indicatorColor: EditorialColors.surfaceContainerHigh,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return EditorialTypography.labelSmall
              .copyWith(color: EditorialColors.primary);
        }
        return EditorialTypography.labelSmall.copyWith(
          color: isDark
              ? EditorialColors.textSecondaryDark
              : EditorialColors.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(
              color: EditorialColors.primary, size: 24);
        }
        return IconThemeData(
          color: isDark
              ? EditorialColors.textSecondaryDark
              : EditorialColors.onSurfaceVariant,
          size: 24,
        );
      }),
    );
  }

  static FloatingActionButtonThemeData _fabTheme({required bool isDark}) {
    return const FloatingActionButtonThemeData(
      elevation: 0,
      backgroundColor: EditorialColors.primary,
      foregroundColor: EditorialColors.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: EditorialRadius.borderRadiusMd,
      ),
    );
  }

  static DividerThemeData _dividerTheme({required bool isDark}) {
    return DividerThemeData(
      color: isDark ? EditorialColors.dividerDark : EditorialColors.dividerLight,
      thickness: 1,
      space: 1,
    );
  }

  static ChipThemeData _chipTheme({required bool isDark}) {
    return ChipThemeData(
      backgroundColor: isDark
          ? EditorialColors.surfaceDark
          : EditorialColors.surfaceContainerLow,
      labelStyle: EditorialTypography.labelMedium,
      shape: const RoundedRectangleBorder(
        borderRadius: EditorialRadius.borderRadiusFull,
      ),
      side: BorderSide.none,
    );
  }

  static DialogThemeData _dialogTheme({required bool isDark}) {
    return DialogThemeData(
      elevation: 0,
      backgroundColor: isDark
          ? EditorialColors.surfaceDark
          : EditorialColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: EditorialRadius.borderRadiusLg,
      ),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme({required bool isDark}) {
    return BottomSheetThemeData(
      elevation: 0,
      backgroundColor: isDark
          ? EditorialColors.surfaceDark
          : EditorialColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: EditorialRadius.borderRadiusTopLg,
      ),
    );
  }

  static SnackBarThemeData _snackBarTheme({required bool isDark}) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: EditorialColors.inverseSurface,
      contentTextStyle: EditorialTypography.bodyMedium.copyWith(
        color: EditorialColors.inverseOnSurface,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: EditorialRadius.borderRadiusStandard,
      ),
    );
  }
}
