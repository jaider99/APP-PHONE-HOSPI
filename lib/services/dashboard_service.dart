// ignore_for_file: avoid_dynamic_calls

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/data/models/sale.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// =============================================================================
// MODELS
// =============================================================================

/// Aggregated financial metrics derived from the `documents` table.
/// Plain Dart class — no code generation required.
class DashboardMetrics {
  final double totalExpenses;
  final double previousPeriodExpenses;
  final double expensesPercentageChange;

  /// Daily expense totals for the last 30 days (for the chart).
  final List<DailyRevenue> dailyExpenses;

  const DashboardMetrics({
    required this.totalExpenses,
    required this.previousPeriodExpenses,
    required this.expensesPercentageChange,
    required this.dailyExpenses,
  });

  factory DashboardMetrics.empty() => const DashboardMetrics(
        totalExpenses: 0,
        previousPeriodExpenses: 0,
        expensesPercentageChange: 0,
        dailyExpenses: [],
      );

  /// For expenses, a decrease is "positive" (spending less is good).
  bool get expensesDecreasing => expensesPercentageChange <= 0;
}

// =============================================================================
// SERVICE
// =============================================================================

/// Fetches and aggregates financial data from the `documents` table.
///
/// Uses the CORRECT column names for the actual Supabase schema:
///   - `status = 'completed'`   (NOT payment_status)
///   - `deleted_at IS NULL`     (NOT is_archived)
///   - Explicit `company_id`    (multi-tenant safety — never rely on RLS alone)
class DashboardService {
  final SupabaseClient _supabase;

  const DashboardService(this._supabase);

  /// Fetch all dashboard financial metrics scoped to [companyId].
  ///
  /// Single Supabase round-trip: fetches documents from the previous month
  /// start through today, then aggregates in Dart.
  Future<DashboardMetrics> fetchMetrics(String companyId) async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final startOfPrevMonth = DateTime(now.year, now.month - 1, 1);

      // One query covers both current month AND previous month for comparison,
      // plus the rolling 30-day window for the chart.
      final response = await _supabase
          .from('documents')
          .select('total_amount, document_date')
          .eq('company_id', companyId)
          .eq('status', 'completed')
          .neq('merge_status', 'merged')
          .not('total_amount', 'is', null)
          .isFilter('deleted_at', null)
          .gte(
            'document_date',
            startOfPrevMonth.toIso8601String().split('T')[0],
          )
          .order('document_date', ascending: true);

      final docs = response as List;
      if (docs.isEmpty) return DashboardMetrics.empty();

      double currentTotal = 0;
      double previousTotal = 0;
      final Map<DateTime, double> dailyMap = {};

      // Earliest date to include in the rolling 30-day chart window.
      final chartWindowStart = DateTime(
        now.subtract(const Duration(days: 29)).year,
        now.subtract(const Duration(days: 29)).month,
        now.subtract(const Duration(days: 29)).day,
      );

      for (final doc in docs) {
        final rawAmount = doc['total_amount'];
        if (rawAmount == null) continue;
        final amount = (rawAmount as num).toDouble();

        final rawDate = doc['document_date'];
        if (rawDate == null) continue;

        DateTime date;
        try {
          date = DateTime.parse(rawDate.toString());
        } catch (_) {
          continue;
        }

        final day = DateTime(date.year, date.month, date.day);

        // Current month (from 1st of this month onwards).
        if (!day.isBefore(startOfMonth)) {
          currentTotal += amount;
        } else {
          // Previous month (before start of current month but >= start of prev month).
          previousTotal += amount;
        }

        // Rolling 30-day chart window.
        if (!day.isBefore(chartWindowStart)) {
          dailyMap[day] = (dailyMap[day] ?? 0) + amount;
        }
      }

      // Sort daily entries chronologically.
      final dailyExpenses = dailyMap.entries
          .map((e) => DailyRevenue(date: e.key, amount: e.value))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      double pctChange = 0;
      if (previousTotal > 0) {
        pctChange =
            ((currentTotal - previousTotal) / previousTotal) * 100;
      }

      return DashboardMetrics(
        totalExpenses: currentTotal,
        previousPeriodExpenses: previousTotal,
        expensesPercentageChange: pctChange,
        dailyExpenses: dailyExpenses,
      );
    } catch (e, st) {
      debugPrint('[DashboardService] fetchMetrics error: $e\n$st');
      return DashboardMetrics.empty();
    }
  }
}

// =============================================================================
// PROVIDERS
// =============================================================================

/// Provider for [DashboardService].
final dashboardServiceProvider = Provider<DashboardService>((ref) {
  return DashboardService(SupabaseService.client);
});
