import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/providers/expense_chart_provider.dart';
import 'package:hospi_dash/services/intelligence_models.dart';
import 'package:hospi_dash/services/intelligence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Service ──────────────────────────────────────────────────────────────────

final intelligenceServiceProvider = Provider<IntelligenceService>((ref) {
  return IntelligenceService(SupabaseService.client);
});

final dashboardIntelligenceRealtimeProvider =
    StreamProvider.autoDispose<void>((ref) async* {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return;

  final controller = StreamController<void>();

  void emit(PostgresChangePayload _) {
    if (!controller.isClosed) controller.add(null);
  }

  final channel = SupabaseService.client
      .channel('dashboard-intelligence-$companyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'documents',
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
        table: 'document_items',
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
        table: 'products',
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
        table: 'product_prices',
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
        table: 'categories',
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

// ─── Category intelligence ────────────────────────────────────────────────────

/// All categories with spend aggregates for the current company.
/// Used by the dashboard intelligence section and the expense tracker.
final categoryIntelligenceProvider =
    FutureProvider.autoDispose<List<CategoryIntelligence>>((ref) async {
  final period = ref.watch(chartPeriodProvider);
  ref.watch(dashboardIntelligenceRealtimeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];
  return ref
      .watch(intelligenceServiceProvider)
      .fetchCategoryIntelligence(companyId, period: period);
});

// ─── Top products (selected dashboard period) ────────────────────────────────

/// Top 8 products by selected-period spend for the dashboard summary card.
final topProductsDashboardProvider =
    FutureProvider.autoDispose<List<ProductIntelligenceSummary>>((ref) async {
  final period = ref.watch(chartPeriodProvider);
  ref.watch(dashboardIntelligenceRealtimeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];
  return ref
      .watch(intelligenceServiceProvider)
      .fetchTopProducts(companyId, limit: 8, period: period);
});

/// Top 20 products by all-time spend — used by the full products screen.
final topProductsAllTimeProvider =
    FutureProvider.autoDispose<List<ProductIntelligenceSummary>>((ref) async {
  ref.watch(dashboardIntelligenceRealtimeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];
  return ref
      .watch(intelligenceServiceProvider)
      .fetchTopProducts(companyId, limit: 20, includeAllTime: true);
});

// ─── Price variance alerts ────────────────────────────────────────────────────

/// Products with ≥ 20 % price variance — potential anomalies worth reviewing.
final priceVarianceAlertsProvider =
    FutureProvider.autoDispose<List<ProductIntelligenceSummary>>((ref) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];
  return ref
      .watch(intelligenceServiceProvider)
      .fetchPriceVarianceAlerts(companyId, limit: 5);
});
