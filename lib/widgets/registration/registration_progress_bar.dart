import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/models/registration_models.dart';
import 'package:hospi_dash/providers/registration_provider.dart';

/// Progress bar widget for the 3-step registration flow.
///
/// Displays:
/// - Step indicators (1, 2, 3) with completion states
/// - Connecting lines showing progress
/// - Step labels ("Company ID", "Details", "Account")
/// - Animated transitions between steps
///
/// Progress percentages:
/// - Step 1 (Company ID): 0% → 33%
/// - Step 2 (Details): 33% → 66%
/// - Step 3 (Account): 66% → 100%
class RegistrationProgressBar extends ConsumerWidget {
  const RegistrationProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStep = ref.watch(currentRegistrationStepProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Step indicators with connecting lines
          SizedBox(
            height: 48,
            child: Row(
              children: [
                // Step 1
                _StepIndicator(
                  stepNumber: 1,
                  isActive: currentStep == RegistrationStep.companyId,
                  isCompleted:
                      currentStep.index > RegistrationStep.companyId.index,
                  colorScheme: colorScheme,
                ),

                // Line 1-2
                Expanded(
                  child: _ConnectingLine(
                    isCompleted:
                        currentStep.index > RegistrationStep.companyId.index,
                    colorScheme: colorScheme,
                  ),
                ),

                // Step 2
                _StepIndicator(
                  stepNumber: 2,
                  isActive: currentStep == RegistrationStep.companyDetails,
                  isCompleted:
                      currentStep.index > RegistrationStep.companyDetails.index,
                  colorScheme: colorScheme,
                ),

                // Line 2-3
                Expanded(
                  child: _ConnectingLine(
                    isCompleted: currentStep.index >
                        RegistrationStep.companyDetails.index,
                    colorScheme: colorScheme,
                  ),
                ),

                // Step 3
                _StepIndicator(
                  stepNumber: 3,
                  isActive: currentStep == RegistrationStep.userAccount ||
                      currentStep == RegistrationStep.emailVerification,
                  isCompleted: currentStep == RegistrationStep.complete ||
                      currentStep == RegistrationStep.pendingApproval,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Step labels
          Row(
            children: [
              Expanded(
                child: _StepLabel(
                  label: 'Company ID',
                  isActive: currentStep == RegistrationStep.companyId,
                  isCompleted:
                      currentStep.index > RegistrationStep.companyId.index,
                  colorScheme: colorScheme,
                ),
              ),
              Expanded(
                child: _StepLabel(
                  label: 'Details',
                  isActive: currentStep == RegistrationStep.companyDetails,
                  isCompleted:
                      currentStep.index > RegistrationStep.companyDetails.index,
                  colorScheme: colorScheme,
                ),
              ),
              Expanded(
                child: _StepLabel(
                  label: 'Account',
                  isActive: currentStep == RegistrationStep.userAccount ||
                      currentStep == RegistrationStep.emailVerification,
                  isCompleted: currentStep == RegistrationStep.complete ||
                      currentStep == RegistrationStep.pendingApproval,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Individual step indicator circle
class _StepIndicator extends StatelessWidget {
  final int stepNumber;
  final bool isActive;
  final bool isCompleted;
  final ColorScheme colorScheme;

  const _StepIndicator({
    required this.stepNumber,
    required this.isActive,
    required this.isCompleted,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor;
    final Color foregroundColor;
    final Widget child;

    if (isCompleted) {
      backgroundColor = colorScheme.primary;
      foregroundColor = colorScheme.onPrimary;
      child = Icon(
        Icons.check_rounded,
        size: 18,
        color: foregroundColor,
      );
    } else if (isActive) {
      backgroundColor = colorScheme.primary;
      foregroundColor = colorScheme.onPrimary;
      child = Text(
        '$stepNumber',
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      );
    } else {
      backgroundColor = colorScheme.surfaceContainerHighest;
      foregroundColor = colorScheme.onSurfaceVariant;
      child = Text(
        '$stepNumber',
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: isActive && !isCompleted
            ? Border.all(
                color: colorScheme.primary.withValues(alpha: 0.3),
                width: 3,
              )
            : null,
        boxShadow: isActive || isCompleted
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Center(child: child),
    ).animate(target: isCompleted ? 1 : 0).scale(
          begin: const Offset(1, 1),
          end: const Offset(1.1, 1.1),
          duration: 200.ms,
          curve: Curves.easeOut,
        );
  }
}

/// Connecting line between steps
class _ConnectingLine extends StatelessWidget {
  final bool isCompleted;
  final ColorScheme colorScheme;

  const _ConnectingLine({
    required this.isCompleted,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Stack(
        children: [
          // Background line
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Progress line
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            height: 3,
            width: isCompleted ? double.infinity : 0,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step label text
class _StepLabel extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isCompleted;
  final ColorScheme colorScheme;

  const _StepLabel({
    required this.label,
    required this.isActive,
    required this.isCompleted,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor;
    final FontWeight fontWeight;

    if (isActive) {
      textColor = colorScheme.primary;
      fontWeight = FontWeight.w600;
    } else if (isCompleted) {
      textColor = colorScheme.onSurface;
      fontWeight = FontWeight.w500;
    } else {
      textColor = colorScheme.onSurfaceVariant;
      fontWeight = FontWeight.w400;
    }

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 200),
      style: TextStyle(
        color: textColor,
        fontWeight: fontWeight,
        fontSize: 12,
      ),
      textAlign: TextAlign.center,
      child: Text(label),
    );
  }
}

/// Compact progress indicator for constrained spaces
/// Shows percentage and thin progress bar
class RegistrationProgressIndicator extends ConsumerWidget {
  const RegistrationProgressIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(registrationProgressProvider);
    final currentStep = ref.watch(currentRegistrationStepProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final stepName = switch (currentStep) {
      RegistrationStep.companyId => 'Company ID',
      RegistrationStep.companyDetails => 'Company Details',
      RegistrationStep.userAccount => 'Create Account',
      RegistrationStep.emailVerification => 'Verify Email',
      RegistrationStep.pendingApproval => 'Pending Approval',
      RegistrationStep.complete => 'Complete',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              stepName,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(colorScheme.primary),
          ),
        ),
      ],
    );
  }
}
