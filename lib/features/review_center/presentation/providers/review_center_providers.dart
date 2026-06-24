import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/features/review_center/data/models/review_item.dart';
import 'package:hospi_dash/features/review_center/data/repositories/review_center_repository.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Duration reviewCenterRealtimeDebounce = Duration(milliseconds: 600);
const Duration reviewCenterAutoSyncCooldown = Duration(minutes: 2);

final reviewCenterRepositoryProvider = Provider<ReviewCenterRepository>(
  (ref) => ReviewCenterRepository(SupabaseService.client),
);

enum ReviewCenterFilter {
  all,
  documents,
  products,
  suppliers,
  categories,
  prices,
  sales,
  pos;

  String get label => switch (this) {
        ReviewCenterFilter.all => 'All',
        ReviewCenterFilter.documents => 'Documents',
        ReviewCenterFilter.products => 'Products',
        ReviewCenterFilter.suppliers => 'Suppliers',
        ReviewCenterFilter.categories => 'Categories',
        ReviewCenterFilter.prices => 'Prices',
        ReviewCenterFilter.sales => 'Sales',
        ReviewCenterFilter.pos => 'POS',
      };

  List<ReviewType>? get types => switch (this) {
        ReviewCenterFilter.all => null,
        ReviewCenterFilter.documents => const [
            ReviewType.duplicateDocument,
            ReviewType.documentNeedsReview,
            ReviewType.unknownDocumentType,
            ReviewType.lowConfidenceField,
          ],
        ReviewCenterFilter.products => const [ReviewType.productMatchReview],
        ReviewCenterFilter.suppliers => const [
            ReviewType.unknownSupplier,
            ReviewType.supplierMatchReview,
          ],
        ReviewCenterFilter.categories => const [ReviewType.missingCategory],
        ReviewCenterFilter.prices => const [
            ReviewType.priceAnomaly,
            ReviewType.priceVariation,
            ReviewType.baselineReview,
          ],
        ReviewCenterFilter.sales => const [
            ReviewType.failedSalesImport,
            ReviewType.lowConfidenceSalesReport,
            ReviewType.missingSalesPeriod,
          ],
        ReviewCenterFilter.pos => const [ReviewType.posConnectionIssue],
      };
}

final selectedReviewFilterProvider = StateProvider<ReviewCenterFilter>(
  (ref) => ReviewCenterFilter.all,
);

final reviewCenterLastAutoSyncAtProvider = StateProvider<DateTime?>(
  (ref) => null,
);

final reviewCenterRealtimeProvider =
    StreamProvider.autoDispose<void>((ref) async* {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return;

  final controller = StreamController<void>();
  Timer? debounceTimer;
  var pendingEvents = 0;

  void emit(PostgresChangePayload payload) {
    pendingEvents++;
    AppLogger.debug(
      '[ReviewCenter] realtime event table=${payload.table} '
      'event=${payload.eventType.name} pending=$pendingEvents',
    );
    if (debounceTimer?.isActive ?? false) return;

    debounceTimer = Timer(reviewCenterRealtimeDebounce, () {
      final events = pendingEvents;
      pendingEvents = 0;
      AppLogger.info('[ReviewCenter] realtime emit events=$events');
      if (!controller.isClosed) controller.add(null);
    });
  }

  final channel = SupabaseService.client
      .channel('review-items-live-$companyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'review_items',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId,
        ),
        callback: emit,
      )
      .subscribe();

  AppLogger.info('[ReviewCenter] realtime subscribed');

  ref.onDispose(() {
    debounceTimer?.cancel();
    AppLogger.info('[ReviewCenter] realtime disposed');
    channel.unsubscribe();
    controller.close();
  });

  yield* controller.stream;
});

final reviewItemsProvider =
    FutureProvider.autoDispose<List<ReviewItem>>((ref) async {
  ref.watch(reviewCenterRealtimeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return const [];

  final filter = ref.watch(selectedReviewFilterProvider);
  return ref.read(reviewCenterRepositoryProvider).fetchOpenItems(
        companyId: companyId,
        types: filter.types,
      );
});

final reviewItemCountsProvider =
    FutureProvider.autoDispose<ReviewItemCounts>((ref) async {
  ref.watch(reviewCenterRealtimeProvider);
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return const ReviewItemCounts.empty();

  return ref
      .read(reviewCenterRepositoryProvider)
      .fetchCounts(companyId: companyId);
});

final syncReviewItemsProvider = FutureProvider.autoDispose<int>((ref) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return 0;

  final count = await ref
      .read(reviewCenterRepositoryProvider)
      .syncCompanyReviewItems(companyId: companyId);
  ref.invalidate(reviewItemsProvider);
  ref.invalidate(reviewItemCountsProvider);
  return count;
});
