import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Custom animated checkbox for "Remember me" functionality.
/// Does NOT use Flutter's default Checkbox widget.
class CustomCheckbox extends StatelessWidget {
  const CustomCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Remember me',
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: value ? EditorialColors.primary : EditorialColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(6),
              border: value
                  ? null
                  : Border.all(
                      color: EditorialColors.outlineVariant,
                      width: 2,
                    ),
            ),
            child: value
                ? const Center(
                    child: Icon(
                      Icons.check,
                      size: 14,
                      color: EditorialColors.onPrimary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: EditorialTypography.bodyMedium.copyWith(
              color: EditorialColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
