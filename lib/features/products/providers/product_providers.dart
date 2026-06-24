import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/services/step_up_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/providers/company_provider.dart';

import '../data/models/product_insights_model.dart';
import '../data/models/product_intelligence_summary_model.dart';
import '../data/models/product_linked_document_model.dart';
import '../data/models/product_model.dart';
import '../data/models/product_price_model.dart';
import '../data/models/product_price_stats_model.dart';
import '../data/models/product_supplier_breakdown_model.dart';
import '../data/models/price_anomaly_model.dart';
import '../data/repositories/product_repository.dart';

// ─── Repository ───────────────────────────────────────────────────────────────

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(SupabaseService.client);
});

// ─── Search / filter state ────────────────────────────────────────────────────

final productSearchQueryProvider = StateProvider<String>((ref) => '');
final productCategoryFilterProvider = StateProvider<String?>((ref) => null);
final productCatalogueFilterProvider = StateProvider<ProductCatalogueFilter>(
  (ref) => ProductCatalogueFilter.all,
);

final _productsRealtimeProvider =
    StreamProvider.autoDispose<void>((ref) async* {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return;

  final controller = StreamController<void>();

  final channel = SupabaseService.client
      .channel('products-live-$companyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'products',
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
        table: 'product_prices',
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
        table: 'document_items',
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
        table: 'price_anomalies',
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
        table: 'product_price_stats',
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

// ─── Product catalogue ────────────────────────────────────────────────────────

/// Fetches the active product list for the current company,
/// respecting the current search query and category filter.
final productsProvider =
    FutureProvider.autoDispose<List<ProductModel>>((ref) async {
  // Read all synchronous state BEFORE the first await (Riverpod 2 rule).
  final search = ref.watch(productSearchQueryProvider);
  final category = ref.watch(productCategoryFilterProvider);
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);

  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  return repo.fetchProducts(
    companyId,
    search: search.trim().isEmpty ? null : search.trim(),
    category: category,
  );
});

final productIntelligenceProvider =
    FutureProvider.autoDispose<List<ProductIntelligenceSummaryModel>>(
        (ref) async {
  final search = ref.watch(productSearchQueryProvider);
  final category = ref.watch(productCategoryFilterProvider);
  final filter = ref.watch(productCatalogueFilterProvider);
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);

  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  return repo.fetchProductIntelligence(
    companyId,
    search: search.trim().isEmpty ? null : search.trim(),
    category: category,
    filter: filter,
  );
});

// ─── Product detail ───────────────────────────────────────────────────────────

/// Fetches a single product by its ID.
final productDetailProvider = FutureProvider.autoDispose
    .family<ProductModel?, String>((ref, productId) async {
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return null;
  return repo.fetchProductById(productId, companyId);
});

// ─── Price history ────────────────────────────────────────────────────────────

/// Fetches price history for a given product, scoped to the current company.
final productPriceHistoryProvider =
    FutureProvider.autoDispose.family<List<ProductPriceModel>, String>(
  (ref, productId) async {
    // Read all synchronous state BEFORE the first await (Riverpod 2 rule).
    ref.watch(_productsRealtimeProvider);
    final repo = ref.watch(productRepositoryProvider);

    final companyId = await ref.watch(companyIdProvider.future);
    if (companyId == null) return [];
    return repo.fetchPriceHistory(productId, companyId);
  },
);

final productAliasesProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, productId) async {
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];
  return repo.fetchAliases(productId, companyId);
});

final productSupplierBreakdownProvider = FutureProvider.autoDispose
    .family<List<ProductSupplierBreakdownModel>, String>(
        (ref, productId) async {
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];
  return repo.buildSupplierBreakdown(productId, companyId);
});

final productInsightsProvider = FutureProvider.autoDispose
    .family<ProductInsightsModel?, String>((ref, productId) async {
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return null;
  return repo.buildInsights(productId, companyId);
});

final productLinkedDocumentsProvider = FutureProvider.autoDispose
    .family<List<ProductLinkedDocumentModel>, String>((ref, productId) async {
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];
  return repo.fetchLinkedDocuments(productId, companyId);
});

final productPriceStatsProvider = FutureProvider.autoDispose
    .family<ProductPriceStatsModel?, String>((ref, productId) async {
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return null;
  return repo.fetchPriceStats(productId, companyId);
});

final productPriceAnomaliesProvider = FutureProvider.autoDispose
    .family<List<PriceAnomalyModel>, String>((ref, productId) async {
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];
  return repo.fetchPriceAnomalies(productId, companyId);
});

final openProductPriceAnomaliesProvider = FutureProvider.autoDispose
    .family<List<PriceAnomalyModel>, String>((ref, productId) async {
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];
  return repo.fetchPriceAnomalies(
    productId,
    companyId,
    includeResolved: false,
    limit: 20,
  );
});

final priceAnomalyActionsProvider = Provider<PriceAnomalyActions>((ref) {
  return PriceAnomalyActions(ref);
});

class PriceAnomalyActions {
  PriceAnomalyActions(this._ref);

  final Ref _ref;

  Future<void> resolve({
    required String productId,
    required String anomalyId,
    required String status,
    String? note,
  }) async {
    await _ref.read(stepUpAuthServiceProvider).requireStepUp(
          action: status == 'baseline_approved'
              ? StepUpAction.approvePriceAnomalyBaseline
              : StepUpAction.resolvePriceAnomaly,
        );

    final companyId = await _ref.read(companyIdProvider.future);
    if (companyId == null) return;

    await _ref.read(productRepositoryProvider).resolvePriceAnomaly(
          companyId: companyId,
          anomalyId: anomalyId,
          resolutionStatus: status,
          note: note,
        );

    _ref.invalidate(productPriceAnomaliesProvider(productId));
    _ref.invalidate(openProductPriceAnomaliesProvider(productId));
    _ref.invalidate(productPriceStatsProvider(productId));
  }
}

// ─── Categories ───────────────────────────────────────────────────────────────

/// Fetches distinct categories used in the current company's catalogue.
final productCategoriesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  // Read all synchronous state BEFORE the first await (Riverpod 2 rule).
  ref.watch(_productsRealtimeProvider);
  final repo = ref.watch(productRepositoryProvider);

  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];
  return repo.fetchCategories(companyId);
});
