import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/models/chart_models.dart';
import 'package:hospi_dash/providers/expense_chart_provider.dart';

/// Period pill selector. Selected period = charcoal pill, unselected = ghost.
class ChartPeriodSelector extends ConsumerStatefulWidget {
  const ChartPeriodSelector({super.key});

  @override
  ConsumerState<ChartPeriodSelector> createState() => _ChartPeriodSelectorState();
}

class _ChartPeriodSelectorState extends ConsumerState<ChartPeriodSelector> {
  ChartPeriod? _tapped;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(chartPeriodProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        children: ChartPeriod.values.map((period) {
          final isSelected = period == selected;
          return GestureDetector(
            onTapDown: (_) => setState(() => _tapped = period),
            onTapCancel: () => setState(() => _tapped = null),
            onTap: () {
              setState(() => _tapped = null);
              ref.read(chartPeriodProvider.notifier).state = period;
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 1.0,
                end: _tapped == period ? 0.94 : 1.0,
              ),
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? EditorialColors.surfaceContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  period.label,
                  style: EditorialTypography.labelMedium.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: isSelected
                        ? EditorialColors.onSurface
                        : EditorialColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
