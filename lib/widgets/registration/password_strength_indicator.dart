import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Password strength level
enum PasswordStrength {
  none,
  weak,
  fair,
  good,
  strong;

  String get label => switch (this) {
        PasswordStrength.none => '',
        PasswordStrength.weak => 'Weak',
        PasswordStrength.fair => 'Fair',
        PasswordStrength.good => 'Good',
        PasswordStrength.strong => 'Strong',
      };

  Color getColor(ColorScheme colorScheme) => switch (this) {
        PasswordStrength.none => colorScheme.surfaceContainerHighest,
        PasswordStrength.weak => colorScheme.error,
        PasswordStrength.fair => EditorialColors.warning,
        PasswordStrength.good => EditorialColors.accentLight,
        PasswordStrength.strong => EditorialColors.success,
      };

  int get segmentCount => switch (this) {
        PasswordStrength.none => 0,
        PasswordStrength.weak => 1,
        PasswordStrength.fair => 2,
        PasswordStrength.good => 3,
        PasswordStrength.strong => 4,
      };
}

/// Visual password strength indicator with animated bars.
/// 
/// Shows 4 segments that fill based on password strength:
/// - Red (1/4): Weak - less than 6 chars
/// - Orange (2/4): Fair - 6+ chars, some requirements
/// - Amber (3/4): Good - 8+ chars, mixed case OR numbers
/// - Green (4/4): Strong - 8+ chars, mixed case, numbers, symbols
/// 
/// Requirements checked:
/// - Minimum length (6 chars)
/// - Uppercase letter
/// - Lowercase letter
/// - Number
/// - Special character
class PasswordStrengthIndicator extends StatelessWidget {
  final String password;
  final bool showRequirements;

  const PasswordStrengthIndicator({
    super.key,
    required this.password,
    this.showRequirements = true,
  });

  @override
  Widget build(BuildContext context) {
    final strength = calculateStrength(password);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Strength bar
        Row(
          children: List.generate(4, (index) {
            final isActive = index < strength.segmentCount;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                height: 4,
                margin: EdgeInsets.only(right: index < 3 ? 4 : 0),
                decoration: BoxDecoration(
                  color: isActive
                      ? strength.getColor(colorScheme)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),

        if (password.isNotEmpty) ...[
          const SizedBox(height: 8),
          // Strength label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strength.label,
                style: TextStyle(
                  color: strength.getColor(colorScheme),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ).animate().fadeIn(duration: 150.ms),
              if (strength == PasswordStrength.strong)
                Icon(
                  Icons.check_circle_rounded,
                  color: EditorialColors.success,
                  size: 16,
                ).animate().scale(
                      begin: const Offset(0.5, 0.5),
                      end: const Offset(1, 1),
                      duration: 200.ms,
                      curve: Curves.elasticOut,
                    ),
            ],
          ),
        ],

        if (showRequirements && password.isNotEmpty && strength != PasswordStrength.strong) ...[
          const SizedBox(height: 12),
          _PasswordRequirements(password: password),
        ],
      ],
    );
  }

  /// Calculate password strength based on various criteria
  static PasswordStrength calculateStrength(String password) {
    if (password.isEmpty) return PasswordStrength.none;
    if (password.length < 6) return PasswordStrength.weak;

    int score = 0;

    // Length checks
    if (password.length >= 6) score++;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;

    // Character type checks
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) score++;

    // Map score to strength
    if (score <= 2) return PasswordStrength.weak;
    if (score <= 4) return PasswordStrength.fair;
    if (score <= 6) return PasswordStrength.good;
    return PasswordStrength.strong;
  }

  /// Validate password meets minimum requirements
  static bool isPasswordValid(String password) {
    return password.length >= 8 &&
        RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password);
  }

  /// Get validation error message if password is invalid
  static String? getValidationError(String password) {
    if (password.isEmpty) return 'Password is required';
    if (password.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must include a lowercase letter';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must include an uppercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must include a number';
    }
    return null;
  }
}

/// Password requirement checklist
class _PasswordRequirements extends StatelessWidget {
  final String password;

  const _PasswordRequirements({required this.password});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RequirementRow(
          text: 'At least 8 characters',
          isMet: password.length >= 8,
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 4),
        _RequirementRow(
          text: 'Uppercase letter (A-Z)',
          isMet: RegExp(r'[A-Z]').hasMatch(password),
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 4),
        _RequirementRow(
          text: 'Lowercase letter (a-z)',
          isMet: RegExp(r'[a-z]').hasMatch(password),
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 4),
        _RequirementRow(
          text: 'Number (0-9)',
          isMet: RegExp(r'[0-9]').hasMatch(password),
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 4),
        _RequirementRow(
          text: 'Special character (!@#\$...)',
          isMet: RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password),
          colorScheme: colorScheme,
          isOptional: true,
        ),
      ],
    );
  }
}

/// Single requirement row with check/cross icon
class _RequirementRow extends StatelessWidget {
  final String text;
  final bool isMet;
  final bool isOptional;
  final ColorScheme colorScheme;

  const _RequirementRow({
    required this.text,
    required this.isMet,
    required this.colorScheme,
    this.isOptional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            isMet ? Icons.check_circle_rounded : Icons.circle_outlined,
            key: ValueKey(isMet),
            size: 14,
            color: isMet
                ? EditorialColors.success
                : isOptional
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          isOptional ? '$text (optional)' : text,
          style: TextStyle(
            fontSize: 12,
            color: isMet
                ? EditorialColors.success
                : isOptional
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Compact password strength bar without requirements list
/// For use in constrained spaces
class PasswordStrengthBar extends StatelessWidget {
  final String password;

  const PasswordStrengthBar({
    super.key,
    required this.password,
  });

  @override
  Widget build(BuildContext context) {
    final strength = PasswordStrengthIndicator.calculateStrength(password);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(4, (index) {
              final isActive = index < strength.segmentCount;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  height: 3,
                  margin: EdgeInsets.only(right: index < 3 ? 2 : 0),
                  decoration: BoxDecoration(
                    color: isActive
                        ? strength.getColor(colorScheme)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              );
            }),
          ),
        ),
        if (password.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            strength.label,
            style: TextStyle(
              color: strength.getColor(colorScheme),
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}
