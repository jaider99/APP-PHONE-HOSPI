import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/models/chart_models.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/providers/expense_chart_provider.dart';
import 'package:intl/intl.dart';

/// Dynamic header above the expense chart.
///
/// While the user drags across the chart it shows the touched data point's
/// cumulative value + date. On release it snaps back to the KPI total.
class ChartDynamicHeader extends ConsumerWidget {
  const ChartDynamicHeader({
    super.key,
    required this.touchNotifier,
  });

  final ValueNotifier<TouchedData?> touchNotifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpi = ref.watch(chartKpiProvider).valueOrNull;
    final period = ref.watch(chartPeriodProvider);
    final currency = ref.watch(currencySymbolProvider).valueOrNull ?? '€';

    return ValueListenableBuilder<TouchedData?>(
      valueListenable: touchNotifier,
      builder: (context, touch, _) {
        final displayValue = touch?.point.value ?? kpi?.totalExpenses ?? 0;
        final displaySub =
            touch != null ? _formatDate(touch.point.date, period) : period.periodName;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EXPENSES',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _AmountDisplay(
                key: ValueKey(displayValue.toStringAsFixed(2)),
                value: displayValue,
                currency: currency,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Text(
                displaySub,
                key: ValueKey(displaySub),
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  color: Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime date, ChartPeriod period) {
    return switch (period) {
      ChartPeriod.oneWeek => DateFormat('EEE, d MMM').format(date),
      ChartPeriod.oneMonth ||
      ChartPeriod.threeMonths =>
        DateFormat('d MMM yyyy').format(date),
      ChartPeriod.sixMonths || ChartPeriod.oneYear => DateFormat('MMM yyyy').format(date),
    };
  }
}

// -----------------------------------------------------------------------------
// Amount row with large headline number + currency symbol
// -----------------------------------------------------------------------------

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({
    super.key,
    required this.value,
    required this.currency,
  });

  final double value;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final formatted = NumberFormat.currency(
      locale: 'de_DE',
      symbol: '',
      decimalDigits: 2,
    ).format(value);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatted,
          style: const TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1C1C),
            letterSpacing: -1.5,
            height: 1,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          currency,
          style: const TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1C1C),
            height: 1,
          ),
        ),
      ],
    );
  }
}
