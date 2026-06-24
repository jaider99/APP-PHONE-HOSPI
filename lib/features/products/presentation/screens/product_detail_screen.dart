import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/documents/presentation/widgets/document_detail_sheet.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/services/step_up_auth_service.dart';
import 'package:hospi_dash/shared/widgets/app_back_button.dart';

import '../../data/models/price_anomaly_model.dart';
import '../../data/models/product_insights_model.dart';
import '../../data/models/product_linked_document_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/product_price_model.dart';
import '../../data/models/product_price_stats_model.dart';
import '../../data/models/product_supplier_breakdown_model.dart';
import '../../providers/product_providers.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({required this.productId, super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productDetailProvider(productId));
    final priceHistoryAsync = ref.watch(productPriceHistoryProvider(productId));
    final aliasesAsync = ref.watch(productAliasesProvider(productId));
    final supplierBreakdownAsync =
        ref.watch(productSupplierBreakdownProvider(productId));
    final insightsAsync = ref.watch(productInsightsProvider(productId));
    final statsAsync = ref.watch(productPriceStatsProvider(productId));
    final anomaliesAsync = ref.watch(productPriceAnomaliesProvider(productId));
    final openAnomaliesAsync =
        ref.watch(openProductPriceAnomaliesProvider(productId));
    final linkedDocumentsAsync =
        ref.watch(productLinkedDocumentsProvider(productId));
    final currencySymbol = ref.watch(currencySymbolProvider).valueOrNull ?? '€';

    return Scaffold(
      backgroundColor: EditorialColors.background,
      body: productAsync.when(
        loading: () => const _ProductDetailSkeleton(),
        error: (error, _) => _ProductNotFound(message: error.toString()),
        data: (product) {
          if (product == null) {
            return const _ProductNotFound(message: 'Product not found');
          }
          return _ProductDetailContent(
            product: product,
            priceHistoryAsync: priceHistoryAsync,
            aliasesAsync: aliasesAsync,
            supplierBreakdownAsync: supplierBreakdownAsync,
            insightsAsync: insightsAsync,
            statsAsync: statsAsync,
            anomaliesAsync: anomaliesAsync,
            openAnomaliesAsync: openAnomaliesAsync,
            linkedDocumentsAsync: linkedDocumentsAsync,
            currencySymbol: currencySymbol,
            ref: ref,
          );
        },
      ),
    );
  }
}

class _ProductDetailContent extends StatelessWidget {
  const _ProductDetailContent({
    required this.product,
    required this.priceHistoryAsync,
    required this.aliasesAsync,
    required this.supplierBreakdownAsync,
    required this.insightsAsync,
    required this.statsAsync,
    required this.anomaliesAsync,
    required this.openAnomaliesAsync,
    required this.linkedDocumentsAsync,
    required this.currencySymbol,
    required this.ref,
  });

  final ProductModel product;
  final AsyncValue<List<ProductPriceModel>> priceHistoryAsync;
  final AsyncValue<List<String>> aliasesAsync;
  final AsyncValue<List<ProductSupplierBreakdownModel>> supplierBreakdownAsync;
  final AsyncValue<ProductInsightsModel?> insightsAsync;
  final AsyncValue<ProductPriceStatsModel?> statsAsync;
  final AsyncValue<List<PriceAnomalyModel>> anomaliesAsync;
  final AsyncValue<List<PriceAnomalyModel>> openAnomaliesAsync;
  final AsyncValue<List<ProductLinkedDocumentModel>> linkedDocumentsAsync;
  final String currencySymbol;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final prices = priceHistoryAsync.valueOrNull ?? const <ProductPriceModel>[];
    final detail = _ProductDetailIntelligence.from(
      product: product,
      prices: prices,
      insights: insightsAsync.valueOrNull,
      stats: statsAsync.valueOrNull,
      openAnomalies:
          openAnomaliesAsync.valueOrNull ?? const <PriceAnomalyModel>[],
    );
    final anomalies = anomaliesAsync.valueOrNull ?? const <PriceAnomalyModel>[];
    final openAnomalies =
        openAnomaliesAsync.valueOrNull ?? const <PriceAnomalyModel>[];

    Future<void> resolveAnomaly(
      PriceAnomalyModel anomaly,
      String status,
    ) async {
      try {
        await ref.read(priceAnomalyActionsProvider).resolve(
              productId: product.id,
              anomalyId: anomaly.id,
              status: status,
            );
      } on StepUpAuthException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${anomaly.title} updated')),
        );
      }
    }

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = width < 360
              ? 16.0
              : width >= 768
                  ? 32.0
                  : 20.0;
          final maxWidth = width >= 768 ? 720.0 : double.infinity;
          final disableAnimations = MediaQuery.of(context).disableAnimations;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              112,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Reveal(
                      index: 0,
                      disabled: disableAnimations,
                      child: const AppBackButton(
                        fallbackRoute: AppRoutes.products,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _Reveal(
                      index: 1,
                      disabled: disableAnimations,
                      child: _ProductHeader(product: product, detail: detail),
                    ),
                    const SizedBox(height: 22),
                    _Reveal(
                      index: 2,
                      disabled: disableAnimations,
                      child: _ProductIdentityCard(
                        product: product,
                        detail: detail,
                        currencySymbol: currencySymbol,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Reveal(
                      index: 3,
                      disabled: disableAnimations,
                      child: _CoreMetricsGrid(
                        product: product,
                        detail: detail,
                        currencySymbol: currencySymbol,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Reveal(
                      index: 4,
                      disabled: disableAnimations,
                      child: _PriceIntelligenceSection(
                        detail: detail,
                        pricesAsync: priceHistoryAsync,
                        anomalies: anomalies,
                        currencySymbol: currencySymbol,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Reveal(
                      index: 5,
                      disabled: disableAnimations,
                      child: _AiReasoningSection(
                        product: product,
                        detail: detail,
                        openAnomaliesAsync: openAnomaliesAsync,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Reveal(
                      index: 6,
                      disabled: disableAnimations,
                      child: _SupplierBreakdownSection(
                        breakdownAsync: supplierBreakdownAsync,
                        currencySymbol: currencySymbol,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Reveal(
                      index: 7,
                      disabled: disableAnimations,
                      child: _LinkedDocumentsSection(
                        documentsAsync: linkedDocumentsAsync,
                        currencySymbol: currencySymbol,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Reveal(
                      index: 8,
                      disabled: disableAnimations,
                      child: _AliasesSection(aliasesAsync: aliasesAsync),
                    ),
                    if (openAnomalies.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _Reveal(
                        index: 9,
                        disabled: disableAnimations,
                        child: _AnomalyActionsSection(
                          anomalies: openAnomalies,
                          onResolve: resolveAnomaly,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductDetailIntelligence {
  const _ProductDetailIntelligence({
    required this.latestPrice,
    required this.previousPrice,
    required this.averagePrice,
    required this.average30d,
    required this.average90d,
    required this.variationVsPrevious,
    required this.variationVsAverage,
    required this.purchaseCount,
    required this.supplierCount,
    required this.lastPurchaseDate,
    required this.severity,
  });

  final double? latestPrice;
  final double? previousPrice;
  final double? averagePrice;
  final double? average30d;
  final double? average90d;
  final double? variationVsPrevious;
  final double? variationVsAverage;
  final int purchaseCount;
  final int supplierCount;
  final DateTime? lastPurchaseDate;
  final _PriceSeverity severity;

  bool get hasEnoughHistory => purchaseCount >= 2 && latestPrice != null;

  static _ProductDetailIntelligence from({
    required ProductModel product,
    required List<ProductPriceModel> prices,
    required ProductInsightsModel? insights,
    required ProductPriceStatsModel? stats,
    required List<PriceAnomalyModel> openAnomalies,
  }) {
    final sorted = [...prices]
      ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    final latest = sorted.isEmpty ? null : sorted.first;
    final previous = sorted.length > 1 ? sorted[1] : null;
    final latestPrice = latest?.price ?? stats?.lastPrice ?? insights?.latestPrice;
    final previousPrice = previous?.price;
    final averagePrice = insights?.averagePrice ?? stats?.averagePrice;
    final average90d = _averageSince(
          sorted,
          DateTime.now().subtract(const Duration(days: 90)),
        ) ??
        averagePrice;
    final average30d = stats?.thirtyDayAverage ??
        _averageSince(
          sorted,
          DateTime.now().subtract(const Duration(days: 30)),
        );
    final variationVsPrevious =
        insights?.changePercentFromPrevious ?? _variation(latestPrice, previousPrice);
    final variationVsAverage = _variation(latestPrice, averagePrice);
    final anomalySeverity = openAnomalies.isEmpty
        ? null
        : _severityFromAnomaly(openAnomalies.first.severity);
    final severity = anomalySeverity ??
        _severityFor((variationVsPrevious ?? variationVsAverage)?.abs());
    final supplierCount = insights?.supplierCount ??
        stats?.supplierCount ??
        sorted
            .map((row) => row.supplierId ?? row.supplierName ?? 'unknown')
            .toSet()
            .length;

    return _ProductDetailIntelligence(
      latestPrice: latestPrice ?? product.unitPrice,
      previousPrice: previousPrice,
      averagePrice: averagePrice,
      average30d: average30d,
      average90d: average90d,
      variationVsPrevious: variationVsPrevious,
      variationVsAverage: variationVsAverage,
      purchaseCount: insights?.purchaseCount ?? stats?.sampleCount ?? sorted.length,
      supplierCount: supplierCount,
      lastPurchaseDate: stats?.lastPurchaseDate ?? latest?.date ?? latest?.observedAt,
      severity: severity,
    );
  }

  static double? _averageSince(List<ProductPriceModel> prices, DateTime since) {
    final values = prices
        .where((price) => !(price.date ?? price.observedAt).isBefore(since))
        .map((price) => price.price)
        .toList();
    if (values.isEmpty) return null;
    return values.fold<double>(0, (sum, value) => sum + value) / values.length;
  }

  static double? _variation(double? latest, double? baseline) {
    if (latest == null || baseline == null || baseline == 0) return null;
    return ((latest - baseline) / baseline) * 100;
  }

  static _PriceSeverity _severityFor(double? variation) {
    if (variation == null || variation < 5) return _PriceSeverity.stable;
    if (variation < 15) return _PriceSeverity.watch;
    if (variation < 30) return _PriceSeverity.high;
    return _PriceSeverity.critical;
  }

  static _PriceSeverity? _severityFromAnomaly(String severity) {
    switch (severity) {
      case 'critical':
        return _PriceSeverity.critical;
      case 'high':
        return _PriceSeverity.high;
      case 'medium':
      case 'low':
        return _PriceSeverity.watch;
      default:
        return null;
    }
  }
}

enum _PriceSeverity { stable, watch, high, critical }

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({required this.product, required this.detail});

  final ProductModel product;
  final _ProductDetailIntelligence detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              (product.displayCategory ?? 'Uncategorized').toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
                color: EditorialColors.onSurfaceVariant,
              ),
            ),
            _StatusPill(severity: detail.severity),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.08,
            color: EditorialColors.onSurface,
          ),
        ),
        if ((product.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            product.description!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: EditorialColors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ProductIdentityCard extends StatelessWidget {
  const _ProductIdentityCard({
    required this.product,
    required this.detail,
    required this.currencySymbol,
  });

  final ProductModel product;
  final _ProductDetailIntelligence detail;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.all(22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProductMark(product: product),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.displayCategory ?? 'Product',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: EditorialColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _money(detail.latestPrice, currencySymbol),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: EditorialColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SoftChip(label: product.unitType ?? 'Unit unknown'),
                    _SoftChip(label: '${detail.purchaseCount} purchases'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoreMetricsGrid extends StatelessWidget {
  const _CoreMetricsGrid({
    required this.product,
    required this.detail,
    required this.currencySymbol,
  });

  final ProductModel product;
  final _ProductDetailIntelligence detail;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final lastChange = detail.variationVsPrevious;
    final metrics = [
      _MetricData(
        label: 'Current Stock',
        value: product.currentStock == null ? '—' : _compactNumber(product.currentStock!),
        caption: product.trackInventory ? 'tracked' : 'not tracked',
        tone: product.currentStock != null &&
                product.minStockLevel != null &&
                product.currentStock! <= product.minStockLevel!
            ? _MetricTone.negative
            : _MetricTone.neutral,
      ),
      _MetricData(
        label: 'Latest Price',
        value: _money(detail.latestPrice, currencySymbol),
        caption: _dateLabel(detail.lastPurchaseDate),
      ),
      _MetricData(
        label: 'Average Price',
        value: _money(detail.averagePrice, currencySymbol),
        caption: detail.average90d == null ? 'all history' : '90 day view',
      ),
      _MetricData(
        label: 'Purchases',
        value: detail.purchaseCount.toString(),
        caption: 'price records',
      ),
      _MetricData(
        label: 'Suppliers',
        value: detail.supplierCount.toString(),
        caption: 'provider history',
      ),
      _MetricData(
        label: 'Last Change',
        value: lastChange == null ? '—' : _percent(lastChange),
        caption: 'vs previous',
        tone: lastChange == null || lastChange.abs() < 5
            ? _MetricTone.neutral
            : lastChange > 0
                ? _MetricTone.negative
                : _MetricTone.positive,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = constraints.maxWidth < 340 ? 1 : 2;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics)
              SizedBox(width: itemWidth, child: _MetricCard(metric: metric)),
          ],
        );
      },
    );
  }
}

class _PriceIntelligenceSection extends StatelessWidget {
  const _PriceIntelligenceSection({
    required this.detail,
    required this.pricesAsync,
    required this.anomalies,
    required this.currencySymbol,
  });

  final _ProductDetailIntelligence detail;
  final AsyncValue<List<ProductPriceModel>> pricesAsync;
  final List<PriceAnomalyModel> anomalies;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Price Intelligence',
      trailing: _BenchmarkPill(severity: detail.severity),
      child: pricesAsync.when(
        loading: () => const _InlineSkeleton(height: 230),
        error: (_, __) => const _QuietEmptyText('Price history unavailable.'),
        data: (prices) {
          if (prices.length < 2) {
            return const _QuietEmptyText('Not enough price history yet.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _IntelligenceFact(label: 'Latest', value: _money(detail.latestPrice, currencySymbol)),
                  _IntelligenceFact(label: 'Previous', value: _money(detail.previousPrice, currencySymbol)),
                  _IntelligenceFact(label: 'Avg 30d', value: _money(detail.average30d, currencySymbol)),
                  _IntelligenceFact(label: 'Avg 90d', value: _money(detail.average90d, currencySymbol)),
                  _IntelligenceFact(label: 'Vs previous', value: detail.variationVsPrevious == null ? '—' : _percent(detail.variationVsPrevious!)),
                  _IntelligenceFact(label: 'Vs average', value: detail.variationVsAverage == null ? '—' : _percent(detail.variationVsAverage!)),
                ],
              ),
              const SizedBox(height: 20),
              _PriceTrendChart(
                prices: prices,
                anomalies: anomalies,
                currencySymbol: currencySymbol,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AiReasoningSection extends StatelessWidget {
  const _AiReasoningSection({
    required this.product,
    required this.detail,
    required this.openAnomaliesAsync,
  });

  final ProductModel product;
  final _ProductDetailIntelligence detail;
  final AsyncValue<List<PriceAnomalyModel>> openAnomaliesAsync;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'What Changed?',
      child: openAnomaliesAsync.when(
        loading: () => const _InlineSkeleton(height: 96),
        error: (_, __) => const _QuietEmptyText('AI insight unavailable.'),
        data: (anomalies) {
          final anomaly = anomalies.isEmpty ? null : anomalies.first;
          final text = anomaly?.aiExplanation ??
              anomaly?.explanation ??
              _deterministicReasoning(product, detail);
          return Text(
            text,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.55,
              color: EditorialColors.onSurfaceVariant,
            ),
          );
        },
      ),
    );
  }
}

class _SupplierBreakdownSection extends StatelessWidget {
  const _SupplierBreakdownSection({
    required this.breakdownAsync,
    required this.currencySymbol,
  });

  final AsyncValue<List<ProductSupplierBreakdownModel>> breakdownAsync;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Supplier Breakdown',
      child: breakdownAsync.when(
        loading: () => const _InlineSkeleton(height: 180),
        error: (_, __) => const _QuietEmptyText('Supplier history unavailable.'),
        data: (breakdown) {
          if (breakdown.isEmpty) {
            return const _QuietEmptyText('No supplier history yet.');
          }
          final bestPrice = breakdown
              .map((entry) => entry.latestPrice)
              .reduce((left, right) => left < right ? left : right);
          return Column(
            children: [
              for (var index = 0; index < breakdown.length; index++) ...[
                _SupplierCard(
                  entry: breakdown[index],
                  currencySymbol: currencySymbol,
                  isBestPrice: breakdown[index].latestPrice == bestPrice,
                ),
                if (index != breakdown.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LinkedDocumentsSection extends StatelessWidget {
  const _LinkedDocumentsSection({
    required this.documentsAsync,
    required this.currencySymbol,
  });

  final AsyncValue<List<ProductLinkedDocumentModel>> documentsAsync;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Linked Documents',
      child: documentsAsync.when(
        loading: () => const _InlineSkeleton(height: 150),
        error: (_, __) => const _QuietEmptyText('Linked documents unavailable.'),
        data: (documents) {
          if (documents.isEmpty) {
            return const _QuietEmptyText('No linked documents yet.');
          }
          return Column(
            children: [
              for (var index = 0; index < documents.length; index++) ...[
                _LinkedDocumentRow(
                  document: documents[index],
                  currencySymbol: currencySymbol,
                ),
                if (index != documents.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AliasesSection extends StatelessWidget {
  const _AliasesSection({required this.aliasesAsync});

  final AsyncValue<List<String>> aliasesAsync;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Known Aliases',
      child: aliasesAsync.when(
        loading: () => const _InlineSkeleton(height: 72),
        error: (_, __) => const _QuietEmptyText('Aliases unavailable.'),
        data: (aliases) {
          if (aliases.isEmpty) {
            return const _QuietEmptyText('No aliases recorded yet.');
          }
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final alias in aliases) _SoftChip(label: alias)],
          );
        },
      ),
    );
  }
}

class _AnomalyActionsSection extends StatelessWidget {
  const _AnomalyActionsSection({
    required this.anomalies,
    required this.onResolve,
  });

  final List<PriceAnomalyModel> anomalies;
  final Future<void> Function(PriceAnomalyModel anomaly, String status)
      onResolve;

  @override
  Widget build(BuildContext context) {
    final anomaly = anomalies.first;
    return _SectionCard(
      title: 'Operational Actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            anomaly.title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: EditorialColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            anomaly.explanation ??
                'Review this price anomaly before using it as a baseline.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: EditorialColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PillAction(label: 'Resolve', onTap: () => onResolve(anomaly, 'resolved')),
              _PillAction(label: 'Ignore', onTap: () => onResolve(anomaly, 'ignored'), secondary: true),
              _PillAction(label: 'Approve baseline', onTap: () => onResolve(anomaly, 'baseline_approved'), secondary: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F1A1C1C),
            blurRadius: 40,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: EditorialColors.onSurface,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ProductMark extends StatelessWidget {
  const _ProductMark({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainer,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Center(
        child: Text(
          _initials(product.name),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: EditorialColors.onSurface,
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _MetricData metric;

  @override
  Widget build(BuildContext context) {
    final color = switch (metric.tone) {
      _MetricTone.positive => EditorialColors.success,
      _MetricTone.negative => EditorialColors.error,
      _MetricTone.neutral => EditorialColors.onSurface,
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 126),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: EditorialColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.value,
              maxLines: 1,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            metric.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: EditorialColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.entry,
    required this.currencySymbol,
    required this.isBestPrice,
  });

  final ProductSupplierBreakdownModel entry;
  final String currencySymbol;
  final bool isBestPrice;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: entry.supplierId == null
          ? null
          : () => context.push('${AppRoutes.providers}/${entry.supplierId}'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: EditorialColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.supplierName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: EditorialColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${entry.purchaseCount} purchases · last ${_dateLabel(entry.lastPurchasedAt)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: EditorialColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 116),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _money(entry.latestPrice, currencySymbol),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: EditorialColors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'avg ${_money(entry.averagePrice, currencySymbol)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: EditorialColors.onSurfaceVariant,
                    ),
                  ),
                  if (isBestPrice) ...[
                    const SizedBox(height: 6),
                    const _SoftChip(label: 'best price', positive: true),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkedDocumentRow extends StatelessWidget {
  const _LinkedDocumentRow({
    required this.document,
    required this.currencySymbol,
  });

  final ProductLinkedDocumentModel document;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: () => DocumentDetailSheet.show(context, document.documentId),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EditorialColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 19,
                color: EditorialColors.onSurface,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: EditorialColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      document.supplierName,
                      _dateLabel(document.documentDate),
                      '${document.lineCount} line${document.lineCount == 1 ? '' : 's'}',
                    ].where((value) => value != null && value.isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: EditorialColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 82),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _money(
                    document.totalAmount,
                    document.currency == null
                        ? currencySymbol
                        : _currencySymbol(document.currency!),
                  ),
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: EditorialColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: EditorialColors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceTrendChart extends StatelessWidget {
  const _PriceTrendChart({
    required this.prices,
    required this.anomalies,
    required this.currencySymbol,
  });

  final List<ProductPriceModel> prices;
  final List<PriceAnomalyModel> anomalies;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final sorted = [...prices]
      ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
    if (sorted.length < 2) {
      return const _QuietEmptyText('Not enough price history yet.');
    }

    final spots = sorted.asMap().entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value.price))
        .toList();
    final minPrice = sorted.map((price) => price.price).reduce(
          (left, right) => left < right ? left : right,
        );
    final maxPrice = sorted.map((price) => price.price).reduce(
          (left, right) => left > right ? left : right,
        );
    final pad = (maxPrice - minPrice).abs() * 0.18 + 0.5;
    final anomalyPriceIds = anomalies
        .where((anomaly) => anomaly.isOpen && anomaly.productPriceId != null)
        .map((anomaly) => anomaly.productPriceId!)
        .toSet();

    return SizedBox(
      height: 178,
      child: LineChart(
        LineChartData(
          minY: minPrice - pad,
          maxY: maxPrice + pad,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: EditorialColors.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: sorted.length <= 8,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  if (index < 0 || index >= sorted.length) {
                    return const SizedBox.shrink();
                  }
                  final date = sorted[index].date ?? sorted[index].observedAt;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('d MMM').format(date.toLocal()),
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: EditorialColors.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: spots.length > 2,
              curveSmoothness: 0.28,
              color: EditorialColors.primary,
              barWidth: 2.4,
              isStrokeCapRound: true,
              dotData: FlDotData(
                checkToShowDot: (spot, _) {
                  final index = spot.x.toInt();
                  if (index < 0 || index >= sorted.length) return false;
                  return sorted.length <= 6 ||
                      anomalyPriceIds.contains(sorted[index].id);
                },
                getDotPainter: (spot, _, __, ___) {
                  final index = spot.x.toInt();
                  final isAnomaly = index >= 0 &&
                      index < sorted.length &&
                      anomalyPriceIds.contains(sorted[index].id);
                  return FlDotCirclePainter(
                    radius: isAnomaly ? 5 : 3.5,
                    color: isAnomaly
                        ? EditorialColors.error
                        : EditorialColors.primary,
                    strokeColor: EditorialColors.surfaceContainerLowest,
                    strokeWidth: 2,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: EditorialColors.surfaceContainer,
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => EditorialColors.primary,
              getTooltipItems: (items) => items.map((item) {
                return LineTooltipItem(
                  _money(item.y, currencySymbol),
                  GoogleFonts.manrope(
                    color: EditorialColors.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.severity});

  final _PriceSeverity severity;

  @override
  Widget build(BuildContext context) {
    final label = switch (severity) {
      _PriceSeverity.stable => 'Healthy',
      _PriceSeverity.watch => 'Watch',
      _PriceSeverity.high => 'High',
      _PriceSeverity.critical => 'Critical',
    };
    final color = _severityColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BenchmarkPill extends StatelessWidget {
  const _BenchmarkPill({required this.severity});

  final _PriceSeverity severity;

  @override
  Widget build(BuildContext context) {
    final label = switch (severity) {
      _PriceSeverity.stable => 'Normal',
      _PriceSeverity.watch => 'Watch',
      _PriceSeverity.high => 'High',
      _PriceSeverity.critical => 'Critical',
    };
    return _SoftChip(label: 'Benchmark: $label');
  }
}

class _SoftChip extends StatelessWidget {
  const _SoftChip({required this.label, this.positive = false});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: positive
            ? EditorialColors.successContainer
            : EditorialColors.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: positive
              ? EditorialColors.success
              : EditorialColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _IntelligenceFact extends StatelessWidget {
  const _IntelligenceFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 138,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: EditorialColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: EditorialColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: secondary
              ? EditorialColors.surfaceContainer
              : EditorialColors.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: secondary
                ? EditorialColors.onSurface
                : EditorialColors.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _PressableScale extends StatefulWidget {
  const _PressableScale({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      child: AnimatedScale(
        scale: disabled || !_pressed ? 1 : 0.97,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.child,
    required this.index,
    required this.disabled,
  });

  final Widget child;
  final int index;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    if (disabled) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 190 + (index * 24).clamp(0, 120)),
      curve: Curves.easeOutCubic,
      builder: (context, value, animatedChild) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 14),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}

class _InlineSkeleton extends StatelessWidget {
  const _InlineSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
    );
  }
}

class _QuietEmptyText extends StatelessWidget {
  const _QuietEmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.45,
        color: EditorialColors.onSurfaceVariant,
      ),
    );
  }
}

class _ProductDetailSkeleton extends StatelessWidget {
  const _ProductDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InlineSkeleton(height: 44),
            SizedBox(height: 20),
            _InlineSkeleton(height: 96),
            SizedBox(height: 18),
            _InlineSkeleton(height: 170),
            SizedBox(height: 18),
            _InlineSkeleton(height: 260),
          ],
        ),
      ),
    );
  }
}

class _ProductNotFound extends StatelessWidget {
  const _ProductNotFound({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 42,
                color: EditorialColors.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: EditorialColors.onSurface,
                ),
              ),
              const SizedBox(height: 18),
              _PillAction(
                label: 'Back to Products',
                onTap: () => context.go(AppRoutes.products),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.caption,
    this.tone = _MetricTone.neutral,
  });

  final String label;
  final String value;
  final String caption;
  final _MetricTone tone;
}

enum _MetricTone { neutral, positive, negative }

String _deterministicReasoning(
  ProductModel product,
  _ProductDetailIntelligence detail,
) {
  if (!detail.hasEnoughHistory) {
    return 'Not enough purchase history yet. HospiDash will explain supplier and price movement once at least two real purchases are available.';
  }
  final variation = detail.variationVsPrevious;
  if (variation == null || variation.abs() < 5) {
    return '${product.name} is stable compared with the previous purchase. Keep watching supplier consistency before changing the baseline.';
  }
  final direction = variation > 0 ? 'increased' : 'decreased';
  final action = variation > 0
      ? 'Compare the last two invoices for supplier pricing, pack-size changes, or unit conversion differences before approving a new baseline.'
      : 'Check whether the lower price came from a supplier change, discount, or quantity/pack-size difference before treating it as the new normal.';
  return 'Price $direction ${variation.abs().toStringAsFixed(1)}% versus the previous purchase. $action';
}

Color _severityColor(_PriceSeverity severity) {
  return switch (severity) {
    _PriceSeverity.stable => EditorialColors.success,
    _PriceSeverity.watch => EditorialColors.warning,
    _PriceSeverity.high => EditorialColors.error,
    _PriceSeverity.critical => EditorialColors.error,
  };
}

String _money(double? value, String symbol) {
  if (value == null) return '—';
  return '$symbol ${value.toStringAsFixed(2)}';
}

String _percent(double value) {
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)}%';
}

String _compactNumber(double value) {
  final isWhole = value == value.truncateToDouble();
  return isWhole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}

String _dateLabel(DateTime? date) {
  if (date == null) return 'no date yet';
  return DateFormat('d MMM yyyy').format(date.toLocal());
}

String _currencySymbol(String currency) {
  switch (currency.toUpperCase()) {
    case 'EUR':
      return '€';
    case 'USD':
      return '\$';
    case 'GBP':
      return '£';
    default:
      return currency;
  }
}

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'P';
  if (words.length == 1) {
    return words.first.substring(0, words.first.length.clamp(1, 2)).toUpperCase();
  }
  return '${words.first[0]}${words[1][0]}'.toUpperCase();
}
