import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/features/dashboard/data/models/dashboard_grid_metrics.dart';
import 'package:hospi_dash/features/dashboard/data/repositories/dashboard_grid_repository.dart';
import 'package:hospi_dash/features/review_center/presentation/providers/review_center_providers.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/providers/expense_chart_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final dashboardGridRepositoryProvider = Provider<DashboardGridRepository>(
  (ref) => DashboardGridRepository(SupabaseService.client),
);

final dashboardSalesRealtimeProvider =
    StreamProvider.autoDispose<void>((ref) async* {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return;

  final controller = StreamController<void>();

  void emit(PostgresChangePayload _) {
    if (!controller.isClosed) controller.add(null);
  }

  final channel = SupabaseService.client
      .channel('dashboard-sales-$companyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sales',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: emit,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sales_imports',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: emit,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sales_items',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: emit,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: emit,
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });

  yield* controller.stream;
});

final dashboardGridMetricsProvider =
    FutureProvider.autoDispose<DashboardGridMetrics?>((ref) async {
  final period = ref.watch(chartPeriodProvider);
  ref.watch(documentMetricRealtimeProvider);
  ref.watch(dashboardSalesRealtimeProvider);
  ref.watch(reviewCenterRealtimeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return null;

  return ref.read(dashboardGridRepositoryProvider).fetchDashboardGridMetrics(
        companyId: companyId,
        period: period,
      );
});
