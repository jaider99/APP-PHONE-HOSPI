import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Sizes for [MetricText] / [FinancialValue]. Map onto the mono currency
/// styles in [EditorialTypography] so all numbers share tabular figures.
enum MetricSize { small, medium, large }

/// Bare metric text. Renders numbers in Geist Mono with tabular figures so
/// columns line up. No icon, no chrome.
class MetricText extends StatelessWidget {
  const MetricText(
    this.value, {
    super.key,
    this.size = MetricSize.medium,
    this.color,
  });

  final String value;
  final MetricSize size;
  final Color? color;

  TextStyle _style() {
    switch (size) {
      case MetricSize.large:
        return EditorialTypography.currencyLarge;
      case MetricSize.medium:
        return EditorialTypography.currencyMedium;
      case MetricSize.small:
        return EditorialTypography.currencySmall;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: _style().copyWith(
        color: color ?? EditorialColors.onSurface,
      ),
    );
  }
}

/// Currency value with optional eyebrow caption. Hero metric primitive.
///
/// `amount` is rendered through [NumberFormat.currency] with the supplied
/// `locale` and `symbol`. Pass `negativeIsError = true` to tint losses with
/// the editorial error ink.
class FinancialValue extends StatelessWidget {
  const FinancialValue({
    super.key,
    required this.amount,
    this.caption,
    this.size = MetricSize.large,
    this.locale = 'pt_BR',
    this.symbol = r'R$ ',
    this.fractionDigits = 2,
    this.negativeIsError = false,
  });

  final num amount;
  final String? caption;
  final MetricSize size;
  final String locale;
  final String symbol;
  final int fractionDigits;
  final bool negativeIsError;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(
      locale: locale,
      symbol: symbol,
      decimalDigits: fractionDigits,
    );
    final formatted = formatter.format(amount);
    final color = (negativeIsError && amount < 0)
        ? EditorialColors.error
        : EditorialColors.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (caption != null) ...[
          Text(
            caption!.toLowerCase(),
            style: EditorialTypography.labelSmall.copyWith(
              color: EditorialColors.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
        ],
        MetricText(formatted, size: size, color: color),
      ],
    );
  }
}

/// Direction of a price/value trend. Drives the glyph + ink color used by
/// [PriceTrendIndicator].
enum TrendDirection { up, down, flat }

/// Quiet trend indicator: tiny glyph + signed percentage in mono. No filled
/// pill, no purple, no animated arrows.
class PriceTrendIndicator extends StatelessWidget {
  const PriceTrendIndicator({
    super.key,
    required this.deltaPercent,
    this.direction,
    this.upIsGood = true,
  });

  /// Signed percentage change (e.g. -3.2 for -3.2 %).
  final double deltaPercent;

  /// Optional explicit direction. When null it's inferred from [deltaPercent].
  final TrendDirection? direction;

  /// When false, downward movement is the positive outcome (e.g. costs).
  final bool upIsGood;

  TrendDirection get _dir {
    if (direction != null) return direction!;
    if (deltaPercent > 0) return TrendDirection.up;
    if (deltaPercent < 0) return TrendDirection.down;
    return TrendDirection.flat;
  }

  Color _colorFor(TrendDirection d) {
    switch (d) {
      case TrendDirection.flat:
        return EditorialColors.onSurfaceVariant;
      case TrendDirection.up:
        return upIsGood ? EditorialColors.success : EditorialColors.error;
      case TrendDirection.down:
        return upIsGood ? EditorialColors.error : EditorialColors.success;
    }
  }

  IconData _iconFor(TrendDirection d) {
    switch (d) {
      case TrendDirection.up:
        return Icons.north;
      case TrendDirection.down:
        return Icons.south;
      case TrendDirection.flat:
        return Icons.remove;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _dir;
    final color = _colorFor(d);
    final sign = deltaPercent > 0 ? '+' : '';
    final value = '$sign${deltaPercent.toStringAsFixed(1)}%';

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(_iconFor(d), size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: EditorialTypography.percentageChange.copyWith(color: color),
        ),
      ],
    );
  }
}
