import 'package:flutter/material.dart';
import 'package:hospi_dash/models/chart_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _DateRange {
  const _DateRange({required this.start, required this.end});
  final DateTime start;
  final DateTime end;
}

/// Supabase-backed repository for the expense line chart data.
///
/// All queries are scoped to [companyId] — multi-tenant safe.
class ExpenseChartRepository {
  ExpenseChartRepository(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns a complete, cumulative daily series for the given [period].
  ///
  /// Every day in the range is represented (days with no expenses have value
  /// equal to the previous day's cumulative total).
  ///
  /// **Date semantics**: only `document_date` (the actual invoice/receipt date
  /// extracted by the AI) is used for time-bucketing. Documents where the AI
  /// did not parse a date are intentionally excluded — they show in the
  /// [fetchUndatedCount] warning banner so the user can review them.
  /// Using `created_at` as a fallback would place a January invoice uploaded
  /// in May into the wrong time bucket.
  Future<List<ChartDataPoint>> fetchChartData({
    required String companyId,
    required ChartPeriod period,
  }) async {
    final today = _today();
    final range = _dateRangeFor(period, today);

    final response = await _client
        .from('documents')
        .select('document_date, total_amount')
        .eq('company_id', companyId)
        .eq('status', 'completed')
        .eq('is_duplicate', false)
        .neq('merge_status', 'merged')
        .not('total_amount', 'is', null)
        .not('document_date', 'is', null)
        .isFilter('deleted_at', null)
        .gte('document_date', _dateStr(range.start))
        .lte('document_date', _dateStr(range.end));

    // Group raw rows by calendar date — accumulate amount + doc count.
    final dailyMap = <DateTime, ({double amount, int count})>{};

    for (final row in response as List) {
      final dateStr = row['document_date'] as String?;
      final amount = (row['total_amount'] as num?)?.toDouble() ?? 0;
      if (dateStr == null) continue;
      final raw = DateTime.parse(dateStr);
      final date = DateTime(raw.year, raw.month, raw.day);
      final existing = dailyMap[date];
      dailyMap[date] = (
        amount: (existing?.amount ?? 0) + amount,
        count: (existing?.count ?? 0) + 1,
      );
    }

    // Build a complete series with cumulative totals.
    final days = range.end.difference(range.start).inDays + 1;
    double cumulative = 0;
    return List.generate(days, (i) {
      final date = range.start.add(Duration(days: i));
      final entry = dailyMap[date];
      final daily = entry?.amount ?? 0;
      cumulative += daily;
      return ChartDataPoint(
        date: date,
        value: cumulative,
        dailyAmount: daily,
        documentCount: entry?.count ?? 0,
      );
    });
  }

  /// Returns KPI totals for the current [period] with a comparison to the
  /// immediately preceding equivalent period.
  ///
  /// Also returns [ChartKpi.undatedCount] — completed documents that lack a
  /// `document_date` and therefore do not appear in any chart period. The UI
  /// should surface a banner prompting the user to review those documents.
  Future<ChartKpi> fetchKpi({
    required String companyId,
    required ChartPeriod period,
  }) async {
    final today = _today();
    final current = _dateRangeFor(period, today);
    final periodDays = current.end.difference(current.start).inDays;

    // Prior period ends one day before current start.
    final priorEnd = current.start.subtract(const Duration(days: 1));
    final priorStart = priorEnd.subtract(Duration(days: periodDays));

    // Three parallel queries:
    //   [0] Current period — by document_date (authoritative invoice date)
    //   [1] Prior period   — by document_date
    //   [2] Undated completed documents (no document_date at all)
    final results = await Future.wait([
      _client
          .from('documents')
          .select('total_amount, tax_amount')
          .eq('company_id', companyId)
          .eq('status', 'completed')
          .eq('is_duplicate', false)
          .neq('merge_status', 'merged')
          .not('total_amount', 'is', null)
          .not('document_date', 'is', null)
          .isFilter('deleted_at', null)
          .gte('document_date', _dateStr(current.start))
          .lte('document_date', _dateStr(current.end)),
      _client
          .from('documents')
          .select('total_amount')
          .eq('company_id', companyId)
          .eq('status', 'completed')
          .eq('is_duplicate', false)
          .neq('merge_status', 'merged')
          .not('total_amount', 'is', null)
          .not('document_date', 'is', null)
          .isFilter('deleted_at', null)
          .gte('document_date', _dateStr(priorStart))
          .lte('document_date', _dateStr(priorEnd)),
      _client
          .from('documents')
          .select('id')
          .eq('company_id', companyId)
          .eq('status', 'completed')
          .neq('merge_status', 'merged')
          .isFilter('document_date', null)
          .isFilter('deleted_at', null),
    ]);

    double totalExpenses = 0;
    double totalTax = 0;
    for (final row in results[0] as List) {
      totalExpenses += (row['total_amount'] as num?)?.toDouble() ?? 0;
      totalTax += (row['tax_amount'] as num?)?.toDouble() ?? 0;
    }
    final documentCount = (results[0] as List).length;

    double priorExpenses = 0;
    for (final row in results[1] as List) {
      priorExpenses += (row['total_amount'] as num?)?.toDouble() ?? 0;
    }

    final undatedCount = (results[2] as List).length;

    final diff = totalExpenses - priorExpenses;
    final String comparisonLabel;
    final Color comparisonColor;

    if (priorExpenses == 0 || diff.abs() < 0.01) {
      comparisonLabel = 'Same as last period';
      comparisonColor = const Color(0xFF9CA3AF);
    } else {
      final pct = (diff / priorExpenses * 100).abs().toStringAsFixed(1);
      if (diff > 0) {
        // More expenses than before → red (bad)
        comparisonLabel = '+$pct% vs last period';
        comparisonColor = const Color(0xFFE5383B);
      } else {
        // Less expenses → green (good)
        comparisonLabel = '-$pct% vs last period';
        comparisonColor = const Color(0xFF1DB954);
      }
    }

    return ChartKpi(
      totalExpenses: totalExpenses,
      netProfit: -totalExpenses,
      totalTax: totalTax,
      comparisonLabel: comparisonLabel,
      comparisonColor: comparisonColor,
      undatedCount: undatedCount,
      documentCount: documentCount,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Returns a `YYYY-MM-DD` string safe for Postgres date comparisons.
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
