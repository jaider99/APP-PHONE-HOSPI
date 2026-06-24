import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/features/review_center/data/models/review_item.dart';
import 'package:hospi_dash/features/review_center/presentation/providers/review_center_providers.dart';
import 'package:intl/intl.dart';

class ReviewCenterScreen extends ConsumerStatefulWidget {
  const ReviewCenterScreen({super.key});

  @override
  ConsumerState<ReviewCenterScreen> createState() => _ReviewCenterScreenState();
}

class _ReviewCenterScreenState extends ConsumerState<ReviewCenterScreen> {
  final _busyItems = <String>{};
  Object? _syncError;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncReviewItems(force: false).ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(reviewItemsProvider);
    final counts = ref.watch(reviewItemCountsProvider);

    return Scaffold(
      backgroundColor: EditorialColors.background,
      body: SafeArea(
        child: RefreshIndicator.adaptive(
          color: EditorialColors.primary,
          onRefresh: () async {
            await _syncReviewItems(force: true);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  18,
                  AppSpacing.screenPadding,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _ReviewHeader(counts: counts),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              const SliverToBoxAdapter(child: _ReviewFilterBar()),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              items.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ReviewLoadingState(),
                ),
                error: (error, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ReviewErrorState(
                    error: error,
                    onRetry: () => ref.invalidate(reviewItemsProvider),
                  ),
                ),
                data: (data) {
                  if (data.isEmpty) {
                    if (_syncError != null) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _ReviewErrorState(
                          error: _syncError!,
                          onRetry: () => _syncReviewItems(force: true).ignore(),
                        ),
                      );
                    }

                    if (_isSyncing) {
                      return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _ReviewLoadingState(),
                      );
                    }

                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ReviewEmptyState(),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding,
                      0,
                      AppSpacing.screenPadding,
                      120,
                    ),
                    sliver: SliverList.separated(
                      itemCount: data.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = data[index];
                        return _ReviewItemCard(
                          item: item,
                          isBusy: _busyItems.contains(item.id),
                          onPrimary: () => _handlePrimary(item),
                          onResolve: () => _setResolved(item),
                          onIgnore: () => _ignore(item),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _syncReviewItems({required bool force}) async {
    if (_isSyncing) return;

    final now = DateTime.now();
    if (!force) {
      final lastAutoSync = ref.read(reviewCenterLastAutoSyncAtProvider);
      if (lastAutoSync != null &&
          now.difference(lastAutoSync) < reviewCenterAutoSyncCooldown) {
        AppLogger.debug('[ReviewCenter] auto sync skipped within cooldown');
        return;
      }
    }

    setState(() {
      _isSyncing = true;
      _syncError = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      if (!force) {
        ref.read(reviewCenterLastAutoSyncAtProvider.notifier).state = now;
      }
      ref.invalidate(syncReviewItemsProvider);
      await ref.read(syncReviewItemsProvider.future);
      ref.read(reviewCenterLastAutoSyncAtProvider.notifier).state =
          DateTime.now();
      AppLogger.info(
        '[ReviewCenter] ${force ? 'manual' : 'auto'} sync complete '
        'ms=${stopwatch.elapsedMilliseconds}',
      );
    } catch (error) {
      if (!force) {
        ref.read(reviewCenterLastAutoSyncAtProvider.notifier).state = null;
      }
      AppLogger.warning(
        '[ReviewCenter] ${force ? 'manual' : 'auto'} sync failed',
        error: error,
      );
      if (mounted) {
        setState(() => _syncError = error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _withBusy(
    ReviewItem item,
    Future<void> Function() action,
  ) async {
    if (_busyItems.contains(item.id)) return;
    setState(() => _busyItems.add(item.id));
    try {
      await action();
      if (!mounted) return;
      HapticFeedback.selectionClick();
      ref.invalidate(reviewItemsProvider);
      ref.invalidate(reviewItemCountsProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Action failed: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyItems.remove(item.id));
    }
  }

  Future<void> _handlePrimary(ReviewItem item) async {
    switch (item.type) {
      case ReviewType.failedExtraction:
        await _withBusy(item, () async {
          await ref.read(reviewCenterRepositoryProvider).retryItem(item: item);
        });
      case ReviewType.priceAnomaly:
      case ReviewType.priceVariation:
      case ReviewType.baselineReview:
      case ReviewType.failedSalesImport:
      case ReviewType.lowConfidenceSalesReport:
      case ReviewType.missingSalesPeriod:
      case ReviewType.posConnectionIssue:
        _openSource(item);
      case ReviewType.duplicateDocument:
        context.go('${AppRoutes.documents}/review-queue');
      case ReviewType.missingCategory:
      case ReviewType.lowConfidenceField:
      case ReviewType.unknownDocumentType:
      case ReviewType.unknownSupplier:
      case ReviewType.productMatchReview:
      case ReviewType.supplierMatchReview:
      case ReviewType.documentNeedsReview:
      case ReviewType.unknown:
        _openSource(item);
    }
  }

  Future<void> _setResolved(ReviewItem item) async {
    await _withBusy(item, () async {
      final repository = ref.read(reviewCenterRepositoryProvider);
      if (item.type == ReviewType.priceAnomaly) {
        await repository.resolvePriceAnomaly(item: item);
      } else {
        await repository.resolveItem(reviewItemId: item.id);
      }
    });
  }

  Future<void> _ignore(ReviewItem item) async {
    await _withBusy(item, () async {
      await ref.read(reviewCenterRepositoryProvider).ignoreItem(item: item);
    });
  }

  void _openSource(ReviewItem item) {
    final documentId = _documentIdFor(item);
    if (documentId != null && documentId.isNotEmpty) {
      context.go('${AppRoutes.documents}/$documentId');
      return;
    }

    if (item.type == ReviewType.failedSalesImport ||
        item.type == ReviewType.lowConfidenceSalesReport ||
        item.type == ReviewType.missingSalesPeriod) {
      context.go(AppRoutes.sales);
      return;
    }

    if (item.type == ReviewType.posConnectionIssue) {
      context.go(AppRoutes.salesConnectPos);
      return;
    }

    if (item.isPriceReview || item.type == ReviewType.productMatchReview) {
      context.go(AppRoutes.products);
      return;
    }

    if (item.type == ReviewType.unknownSupplier ||
        item.type == ReviewType.supplierMatchReview) {
      context.go(AppRoutes.providers);
      return;
    }
  }

  String? _documentIdFor(ReviewItem item) {
    if (item.sourceTable == 'documents') return item.sourceId;
    final value = item.metadata['document_id'];
    return value is String ? value : null;
  }
}

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({required this.counts});

  final AsyncValue<ReviewItemCounts> counts;

  @override
  Widget build(BuildContext context) {
    final value = counts.valueOrNull ?? const ReviewItemCounts.empty();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review Center',
          style: GoogleFonts.plusJakartaSans(
            color: EditorialColors.onSurface,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Items that need your attention',
          style: GoogleFonts.manrope(
            color: EditorialColors.onSurfaceVariant,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        _SummaryStrip(counts: value),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.counts});

  final ReviewItemCounts counts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          _SummaryPill(label: 'Open', value: counts.open.toString()),
          _SummaryPill(label: 'Critical', value: counts.critical.toString()),
          _SummaryPill(label: 'AI review', value: counts.aiReview.toString()),
          _SummaryPill(label: 'Prices', value: counts.priceAlerts.toString()),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.manrope(
              color: EditorialColors.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              color: EditorialColors.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewFilterBar extends ConsumerWidget {
  const _ReviewFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedReviewFilterProvider);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
        scrollDirection: Axis.horizontal,
        itemCount: ReviewCenterFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = ReviewCenterFilter.values[index];
          final active = filter == selected;
          return ChoiceChip(
            selected: active,
            label: Text(filter.label),
            onSelected: (_) {
              ref.read(selectedReviewFilterProvider.notifier).state = filter;
            },
            selectedColor: EditorialColors.primary,
            backgroundColor: EditorialColors.surfaceContainerLowest,
            labelStyle: GoogleFonts.manrope(
              color: active
                  ? EditorialColors.onPrimary
                  : EditorialColors.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: const BorderSide(color: Colors.transparent),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}

class _ReviewItemCard extends StatelessWidget {
  const _ReviewItemCard({
    required this.item,
    required this.isBusy,
    required this.onPrimary,
    required this.onResolve,
    required this.onIgnore,
  });

  final ReviewItem item;
  final bool isBusy;
  final VoidCallback onPrimary;
  final VoidCallback onResolve;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final tone = _severityColor(item.severity);
    final formatter = DateFormat('d MMM, HH:mm');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1C1C).withValues(alpha: 0.045),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(_iconFor(item.type), size: 20, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.type.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              color: tone,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.severity.value.toUpperCase(),
                          style: GoogleFonts.manrope(
                            color: EditorialColors.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.title,
                      style: GoogleFonts.plusJakartaSans(
                        color: EditorialColors.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.description != null &&
              item.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              item.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                color: EditorialColors.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 14,
                color: EditorialColors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                formatter.format(item.createdAt),
                style: GoogleFonts.manrope(
                  color: EditorialColors.onSurfaceVariant,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                item.sourceTable.replaceAll('_', ' '),
                style: GoogleFonts.manrope(
                  color: EditorialColors.onSurfaceVariant,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: isBusy ? null : onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: EditorialColors.primary,
                    foregroundColor: EditorialColors.onPrimary,
                    disabledBackgroundColor:
                        EditorialColors.surfaceContainerHigh,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: isBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_primaryLabel(item)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Resolve',
                onPressed: isBusy ? null : onResolve,
                icon: const Icon(Icons.check_rounded),
              ),
              IconButton(
                tooltip: 'Ignore',
                onPressed: isBusy ? null : onIgnore,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _severityColor(ReviewSeverity severity) => switch (severity) {
        ReviewSeverity.critical => EditorialColors.error,
        ReviewSeverity.high => EditorialColors.warning,
        ReviewSeverity.medium => EditorialColors.info,
        ReviewSeverity.low => EditorialColors.success,
        ReviewSeverity.unknown => EditorialColors.onSurfaceVariant,
      };

  static IconData _iconFor(ReviewType type) => switch (type) {
        ReviewType.failedExtraction => Icons.error_outline_rounded,
        ReviewType.duplicateDocument => Icons.content_copy_rounded,
        ReviewType.missingCategory => Icons.category_outlined,
        ReviewType.productMatchReview => Icons.inventory_2_outlined,
        ReviewType.supplierMatchReview ||
        ReviewType.unknownSupplier =>
          Icons.storefront_outlined,
        ReviewType.priceAnomaly ||
        ReviewType.priceVariation ||
        ReviewType.baselineReview =>
          Icons.trending_up_rounded,
        ReviewType.failedSalesImport ||
        ReviewType.lowConfidenceSalesReport ||
        ReviewType.missingSalesPeriod =>
          Icons.point_of_sale_rounded,
        ReviewType.posConnectionIssue => Icons.wifi_tethering_error_rounded,
        ReviewType.unknownDocumentType ||
        ReviewType.lowConfidenceField =>
          Icons.fact_check_outlined,
        ReviewType.documentNeedsReview => Icons.rate_review_outlined,
        ReviewType.unknown => Icons.inbox_outlined,
      };

  static String _primaryLabel(ReviewItem item) => switch (item.type) {
        ReviewType.failedExtraction => 'Retry',
        ReviewType.missingCategory => 'Assign',
        ReviewType.duplicateDocument => 'Review',
        ReviewType.priceAnomaly ||
        ReviewType.priceVariation ||
        ReviewType.baselineReview =>
          'Open',
        ReviewType.productMatchReview => 'Match',
        ReviewType.supplierMatchReview || ReviewType.unknownSupplier => 'Match',
        ReviewType.failedSalesImport ||
        ReviewType.lowConfidenceSalesReport ||
        ReviewType.missingSalesPeriod =>
          'Open',
        ReviewType.posConnectionIssue => 'Open',
        ReviewType.lowConfidenceField ||
        ReviewType.unknownDocumentType =>
          'Review',
        ReviewType.documentNeedsReview => 'Review',
        ReviewType.unknown => 'Open',
      };
}

class _ReviewLoadingState extends StatelessWidget {
  const _ReviewLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator.adaptive());
  }
}

class _ReviewErrorState extends StatelessWidget {
  const _ReviewErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 36),
            const SizedBox(height: 12),
            Text(
              'Could not load review items',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style:
                  GoogleFonts.manrope(color: EditorialColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ReviewEmptyState extends StatelessWidget {
  const _ReviewEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: EditorialColors.successLight,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.done_all_rounded,
                color: EditorialColors.success,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'All clear',
              style: GoogleFonts.plusJakartaSans(
                color: EditorialColors.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nothing needs review right now.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: EditorialColors.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
