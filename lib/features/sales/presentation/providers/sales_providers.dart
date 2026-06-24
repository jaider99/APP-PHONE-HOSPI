import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/features/dashboard/presentation/providers/dashboard_grid_provider.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/services/storage_service.dart';

import '../../data/models/pos_connection.dart';
import '../../data/models/sale.dart';
import '../../data/models/sales_import.dart';
import '../../data/models/sales_item.dart';
import '../../data/models/sales_summary.dart';
import '../../data/repositories/sales_repository.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(
    supabase: SupabaseService.client,
    storageService: ref.watch(storageServiceProvider),
  );
});

final salesPeriodProvider = StateProvider<SalesPeriod>((ref) {
  return SalesPeriod.thisMonth;
});

final salesPeriodRangeProvider = Provider<SalesPeriodRange>((ref) {
  return SalesPeriodRange.fromPeriod(ref.watch(salesPeriodProvider));
});

final salesRealtimeProvider = StreamProvider.autoDispose<void>((ref) async* {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return;

  final controller = StreamController<void>();
  final channel = SupabaseService.client
      .channel('sales-live-$companyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sales_imports',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: (_) {
          if (!controller.isClosed) controller.add(null);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sales',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: (_) {
          if (!controller.isClosed) controller.add(null);
        },
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
        callback: (_) {
          if (!controller.isClosed) controller.add(null);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'pos_sync_jobs',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: (_) {
          if (!controller.isClosed) controller.add(null);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'pos_connections',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: (_) {
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

final salesSummaryProvider =
    FutureProvider.autoDispose<SalesSummary>((ref) async {
  ref.watch(salesRealtimeProvider);
  final range = ref.watch(salesPeriodRangeProvider);
  final repository = ref.watch(salesRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return SalesSummary.empty();

  return repository.fetchSummary(companyId: companyId, range: range);
});

final salesImportsProvider =
    FutureProvider.autoDispose<List<SalesImport>>((ref) async {
  ref.watch(salesRealtimeProvider);
  final repository = ref.watch(salesRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  return repository.fetchImports(companyId);
});

final posConnectionsProvider =
    FutureProvider.autoDispose<List<PosConnection>>((ref) async {
  ref.watch(salesRealtimeProvider);
  final repository = ref.watch(salesRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  return repository.fetchPosConnections(companyId);
});

final salesItemsProvider =
    FutureProvider.autoDispose<List<SalesItem>>((ref) async {
  ref.watch(salesRealtimeProvider);
  final range = ref.watch(salesPeriodRangeProvider);
  final repository = ref.watch(salesRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  return repository.fetchTopItems(companyId: companyId, range: range);
});

final importedSalesProvider = FutureProvider.autoDispose
    .family<List<Sale>, String>((ref, salesImportId) async {
  ref.watch(salesRealtimeProvider);
  final repository = ref.watch(salesRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  return repository.fetchImportedSales(
    companyId: companyId,
    salesImportId: salesImportId,
  );
});

void invalidateSalesSurfaces(WidgetRef ref, {String? salesImportId}) {
  ref.invalidate(salesSummaryProvider);
  ref.invalidate(salesImportsProvider);
  ref.invalidate(salesItemsProvider);
  ref.invalidate(posConnectionsProvider);
  ref.invalidate(dashboardGridMetricsProvider);
  if (salesImportId != null) {
    ref.invalidate(importedSalesProvider(salesImportId));
  }
}
