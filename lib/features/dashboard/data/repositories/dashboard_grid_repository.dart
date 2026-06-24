import 'package:hospi_dash/features/dashboard/data/models/dashboard_grid_metrics.dart';
import 'package:hospi_dash/models/chart_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardGridRepository {
  const DashboardGridRepository(this._client);

  final SupabaseClient _client;

  Future<DashboardGridMetrics> fetchDashboardGridMetrics({
    required String companyId,
    required ChartPeriod period,
  }) async {
    final today = _today();
    final current = _dateRangeFor(period, today);
    final priorDays = current.end.difference(current.start).inDays;
    final priorEnd = current.start.subtract(const Duration(days: 1));
    final priorStart = priorEnd.subtract(Duration(days: priorDays));

    final results = await Future.wait<Object>([
      _fetchExpenseRows(companyId: companyId, range: current),
      _fetchExpenseRows(
        companyId: companyId,
        range: _DateRange(start: priorStart, end: priorEnd),
      ),
      _fetchDocumentStatusRows(companyId: companyId, range: current),
      _fetchSalesSummary(companyId: companyId, range: current),
      _fetchReviewRows(companyId: companyId),
    ]);

    final currentExpenseRows = results[0] as List<dynamic>;
    final previousExpenseRows = results[1] as List<dynamic>;
    final documentRows = results[2] as List<dynamic>;
    final salesSummary = results[3] as _SalesSummary;
    final reviewRows = results[4] as List<dynamic>;

    double expensesTotal = 0;
    double expensesPreviousTotal = 0;
    double vatTotal = 0;

    for (final row in currentExpenseRows) {
      final data = row as Map<String, dynamic>;
      expensesTotal += (data['total_amount'] as num?)?.toDouble() ?? 0;
      vatTotal += (data['tax_amount'] as num?)?.toDouble() ?? 0;
    }

    for (final row in previousExpenseRows) {
      final data = row as Map<String, dynamic>;
      expensesPreviousTotal += (data['total_amount'] as num?)?.toDouble() ?? 0;
    }

    var processedDocumentsCount = 0;
    var pendingDocumentsCount = 0;
    var failedDocumentsCount = 0;
    var reviewCriticalCount = 0;

    for (final row in documentRows) {
      final data = row as Map<String, dynamic>;
      switch (data['status'] as String?) {
        case 'completed':
          processedDocumentsCount++;
        case 'processing':
          pendingDocumentsCount++;
        case 'failed':
        case 'flagged':
          failedDocumentsCount++;
      }
    }

    for (final row in reviewRows) {
      final data = row as Map<String, dynamic>;
      if (data['severity'] == 'critical') reviewCriticalCount++;
    }

    return DashboardGridMetrics(
      expensesTotal: expensesTotal,
      expensesPreviousTotal: expensesPreviousTotal,
      vatTotal: vatTotal,
      salesTotal: salesSummary.total,
      salesRecordCount: salesSummary.count,
      documentsCount: documentRows.length,
      processedDocumentsCount: processedDocumentsCount,
      pendingDocumentsCount: pendingDocumentsCount,
      failedDocumentsCount: failedDocumentsCount,
      reviewOpenCount: reviewRows.length,
      reviewCriticalCount: reviewCriticalCount,
      periodLabel: period.periodName,
      period: period,
      salesSource: salesSummary.source,
    );
  }

  Future<List<dynamic>> _fetchExpenseRows({
    required String companyId,
    required _DateRange range,
  }) {
    return _client
        .from('documents')
        .select('id, total_amount, tax_amount')
        .eq('company_id', companyId)
        .eq('status', 'completed')
        .eq('is_duplicate', false)
        .neq('merge_status', 'merged')
        .not('total_amount', 'is', null)
        .not('document_date', 'is', null)
        .isFilter('deleted_at', null)
        .gte('document_date', _dateStr(range.start))
        .lte('document_date', _dateStr(range.end));
  }

  Future<List<dynamic>> _fetchDocumentStatusRows({
    required String companyId,
    required _DateRange range,
  }) {
    return _client
        .from('documents')
        .select('id, status')
        .eq('company_id', companyId)
        .neq('merge_status', 'merged')
        .isFilter('deleted_at', null)
        .gte('created_at', range.start.toIso8601String())
        .lte(
          'created_at',
          range.end.add(const Duration(days: 1)).toIso8601String(),
        );
  }

  Future<List<dynamic>> _fetchReviewRows({required String companyId}) async {
    try {
      return await _client
          .from('review_items')
          .select('id, severity')
          .eq('company_id', companyId)
          .eq('status', 'open');
    } on PostgrestException catch (error) {
      if (_isMissingRelation(error)) return [];
      rethrow;
    }
  }

  Future<_SalesSummary> _fetchSalesSummary({
    required String companyId,
    required _DateRange range,
  }) async {
    final sales = await _tryFetchSalesRows(companyId: companyId, range: range);
    if (sales != null && sales.isNotEmpty) {
      return _sumSalesRows(sales, DashboardSalesSource.sales);
    }

    final orders = await _tryFetchOrderRows(companyId: companyId, range: range);
    if (orders != null && orders.isNotEmpty) {
      return _sumSalesRows(orders, DashboardSalesSource.orders);
    }

    return const _SalesSummary(
      total: 0,
      count: 0,
      source: DashboardSalesSource.none,
    );
  }

  Future<List<dynamic>?> _tryFetchSalesRows({
    required String companyId,
    required _DateRange range,
  }) async {
    try {
      return await _client
          .from('sales')
          .select('id, total_amount, transaction_count')
          .eq('company_id', companyId)
          .gte('sale_date', _dateStr(range.start))
          .lte('sale_date', _dateStr(range.end));
    } on PostgrestException catch (error) {
      if (_isMissingRelation(error)) return null;
      rethrow;
    }
  }

  Future<List<dynamic>?> _tryFetchOrderRows({
    required String companyId,
    required _DateRange range,
  }) async {
    try {
      return await _client
          .from('orders')
          .select('id, total_amount, tax_amount, discount_amount')
          .eq('company_id', companyId)
          .eq('status', 'completed')
          .gte('created_at', range.start.toIso8601String())
          .lte(
            'created_at',
            range.end.add(const Duration(days: 1)).toIso8601String(),
          );
    } on PostgrestException catch (error) {
      if (_isMissingRelation(error)) return null;
      rethrow;
    }
  }

  _SalesSummary _sumSalesRows(List<dynamic> rows, DashboardSalesSource source) {
    double total = 0;
    for (final row in rows) {
      final data = row as Map<String, dynamic>;
      final gross = (data['total_amount'] as num?)?.toDouble() ?? 0;
      final tax = source == DashboardSalesSource.orders
          ? (data['tax_amount'] as num?)?.toDouble() ?? 0
          : 0.0;
      final discount = source == DashboardSalesSource.orders
          ? (data['discount_amount'] as num?)?.toDouble() ?? 0
          : 0.0;
      total += gross - tax - discount;
    }
    final count = source == DashboardSalesSource.sales
        ? rows.fold<int>(0, (sum, row) {
            final data = row as Map<String, dynamic>;
            final count = (data['transaction_count'] as num?)?.toInt() ?? 1;
            return sum + (count < 1 ? 1 : count);
          })
        : rows.length;
    return _SalesSummary(total: total, count: count, source: source);
  }

  bool _isMissingRelation(PostgrestException error) {
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    return code == '42p01' ||
        code == 'pgrst205' ||
        message.contains('does not exist') ||
        message.contains('could not find the table');
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _dateStr(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  _DateRange _dateRangeFor(ChartPeriod period, DateTime today) {
    return switch (period) {
      ChartPeriod.oneWeek => _DateRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        ),
      ChartPeriod.oneMonth => _DateRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        ),
      ChartPeriod.threeMonths => _DateRange(
          start: today.subtract(const Duration(days: 89)),
          end: today,
        ),
      ChartPeriod.sixMonths => _DateRange(
          start: today.subtract(const Duration(days: 179)),
          end: today,
        ),
      ChartPeriod.oneYear => _DateRange(
          start: today.subtract(const Duration(days: 364)),
          end: today,
        ),
    };
  }
}

class _DateRange {
  const _DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _SalesSummary {
  const _SalesSummary({
    required this.total,
    required this.count,
    required this.source,
  });

  final double total;
  final int count;
  final DashboardSalesSource source;
}
