enum SalesPeriod { today, thisWeek, thisMonth, custom }

class SalesPeriodRange {
  const SalesPeriodRange({
    required this.period,
    required this.start,
    required this.end,
  });

  final SalesPeriod period;
  final DateTime start;
  final DateTime end;

  factory SalesPeriodRange.fromPeriod(SalesPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case SalesPeriod.today:
        return SalesPeriodRange(period: period, start: today, end: today);
      case SalesPeriod.thisWeek:
        final start = today.subtract(Duration(days: today.weekday - 1));
        return SalesPeriodRange(period: period, start: start, end: today);
      case SalesPeriod.thisMonth:
        return SalesPeriodRange(
          period: period,
          start: DateTime(now.year, now.month),
          end: today,
        );
      case SalesPeriod.custom:
        return SalesPeriodRange(period: period, start: today, end: today);
    }
  }

  String get startDate => _date(start);
  String get endDate => _date(end);

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class SalesSummary {
  const SalesSummary({
    required this.grossRevenue,
    required this.netRevenue,
    required this.taxAmount,
    required this.transactionCount,
    required this.averageTicket,
  });

  final double grossRevenue;
  final double netRevenue;
  final double taxAmount;
  final int transactionCount;
  final double averageTicket;

  bool get hasSales => transactionCount > 0 || grossRevenue > 0;

  factory SalesSummary.empty() => const SalesSummary(
        grossRevenue: 0,
        netRevenue: 0,
        taxAmount: 0,
        transactionCount: 0,
        averageTicket: 0,
      );

  factory SalesSummary.fromRpc(Map<String, dynamic> json) {
    return SalesSummary(
      grossRevenue: _readDouble(json['gross_revenue']) ?? 0,
      netRevenue: _readDouble(json['net_revenue']) ?? 0,
      taxAmount: _readDouble(json['tax_amount']) ?? 0,
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
      averageTicket: _readDouble(json['average_ticket']) ?? 0,
    );
  }
}

double? _readDouble(Object? value) => value is num ? value.toDouble() : null;