import 'package:hospi_dash/models/chart_models.dart';

class DashboardGridMetrics {
  const DashboardGridMetrics({
    required this.expensesTotal,
    required this.expensesPreviousTotal,
    required this.vatTotal,
    required this.salesTotal,
    required this.salesRecordCount,
    required this.documentsCount,
    required this.processedDocumentsCount,
    required this.pendingDocumentsCount,
    required this.failedDocumentsCount,
    required this.reviewOpenCount,
    required this.reviewCriticalCount,
    required this.periodLabel,
    required this.period,
    this.salesSource = DashboardSalesSource.none,
  });

  final double expensesTotal;
  final double expensesPreviousTotal;
  final double vatTotal;
  final double salesTotal;
  final int salesRecordCount;
  final int documentsCount;
  final int processedDocumentsCount;
  final int pendingDocumentsCount;
  final int failedDocumentsCount;
  final int reviewOpenCount;
  final int reviewCriticalCount;
  final String periodLabel;
  final ChartPeriod period;
  final DashboardSalesSource salesSource;

  double get resultTotal => salesTotal - expensesTotal;

  bool get hasSales => salesRecordCount > 0 || salesTotal > 0;

  bool get hasAnyData =>
      expensesTotal > 0 ||
      salesTotal > 0 ||
      documentsCount > 0 ||
      pendingDocumentsCount > 0 ||
      failedDocumentsCount > 0 ||
      reviewOpenCount > 0;

  double? get expensesChangePercent {
    if (expensesPreviousTotal <= 0) return null;
    return ((expensesTotal - expensesPreviousTotal) / expensesPreviousTotal) *
        100;
  }
}

enum DashboardSalesSource {
  none,
  sales,
  orders,
}
