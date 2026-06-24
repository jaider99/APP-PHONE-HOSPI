import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/models/chart_models.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/repositories/expense_chart_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository instance provider — purely for DI/testability.
final expenseChartRepositoryProvider = Provider<ExpenseChartRepository>(
  (ref) => ExpenseChartRepository(SupabaseService.client),
);

/// Currently selected period in the expense chart.
///
/// Not autoDispose so the period is preserved across navigation.
final chartPeriodProvider = StateProvider<ChartPeriod>(
  (ref) => ChartPeriod.oneMonth,
);

// ---------------------------------------------------------------------------
// Realtime: auto-invalidate document metrics when relevant documents change
// ---------------------------------------------------------------------------

/// A stream that emits whenever a document for the current company
/// changes in a way that can affect dashboard document metrics.
///
/// Watched by [chartDataProvider], [chartKpiProvider], and dashboard widgets so
/// OCR completion, deletes, and status changes refresh without pull-to-refresh.
final documentMetricRealtimeProvider =
    StreamProvider.autoDispose<void>((ref) async* {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return;

  final controller = StreamController<void>();

  final channel = SupabaseService.client
      .channel('document-metrics-$companyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'documents',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: (payload) {
          if (!controller.isClosed) controller.add(null);
        },
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });

  yield* controller.stream;
});

// ---------------------------------------------------------------------------
// Chart data providers
// ---------------------------------------------------------------------------

/// Cumulative daily expense series for the selected period.
final chartDataProvider = FutureProvider.autoDispose<List<ChartDataPoint>>(
  (ref) async {
    // All ref.watch calls BEFORE the first await (Riverpod 2 rule).
    final period = ref.watch(chartPeriodProvider);
    // Trigger re-fetch whenever document metrics change.
    ref.watch(documentMetricRealtimeProvider);
    final companyId = await ref.watch(companyIdProvider.future);
    if (companyId == null) return [];
    return ref.read(expenseChartRepositoryProvider).fetchChartData(
          companyId: companyId,
          period: period,
        );
  },
);

/// KPI totals + comparison label for the selected period.
final chartKpiProvider = FutureProvider.autoDispose<ChartKpi?>(
  (ref) async {
    // All ref.watch calls BEFORE the first await (Riverpod 2 rule).
    final period = ref.watch(chartPeriodProvider);
    // Trigger re-fetch whenever document metrics change.
    ref.watch(documentMetricRealtimeProvider);
    final companyId = await ref.watch(companyIdProvider.future);
    if (companyId == null) return null;
    return ref.read(expenseChartRepositoryProvider).fetchKpi(
          companyId: companyId,
          period: period,
        );
  },
);
