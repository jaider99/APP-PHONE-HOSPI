import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Primary action button for authentication screens.
/// Supports loading and disabled states.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Opacity(
        opacity: isEnabled && !isLoading ? 1.0 : 0.5,
        child: ElevatedButton(
          onPressed: isEnabled && !isLoading ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: EditorialColors.primary,
            foregroundColor: EditorialColors.onPrimary,
            disabledBackgroundColor: EditorialColors.primary,
            disabledForegroundColor: EditorialColors.onPrimary,
            elevation: 0,
            shape: const RoundedRectangleBorder(
              borderRadius: EditorialRadius.borderRadiusFull,
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: EditorialColors.onPrimary,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  text,
                  style: EditorialTypography.titleMedium.copyWith(
                    color: EditorialColors.onPrimary,
                  ),
                ),
        ),
      ),
    );
  }
}
