import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product_model.dart';
import '../models/product_intelligence_summary_model.dart';
import '../models/product_insights_model.dart';
import '../models/product_linked_document_model.dart';
import '../models/product_price_model.dart';
import '../models/product_price_stats_model.dart';
import '../models/product_supplier_breakdown_model.dart';
import '../models/price_anomaly_model.dart';

// Top-level parse functions required by compute() (must not be closures).
List<ProductModel> _parseProductList(List<dynamic> raw) =>
    raw.map((e) => ProductModel.fromJson(e as Map<String, dynamic>)).toList();

List<ProductPriceModel> _parsePriceList(List<dynamic> raw) => raw
    .map((e) => ProductPriceModel.fromJson(e as Map<String, dynamic>))
    .toList();

List<PriceAnomalyModel> _parseAnomalyList(List<dynamic> raw) => raw
    .map((e) => PriceAnomalyModel.fromJson(e as Map<String, dynamic>))
    .toList();

List<String> _parseAliasList(List<dynamic> raw) => raw
    .map((e) => (e as Map<String, dynamic>)['raw_name'] as String?)
    .whereType<String>()
    .toList();

double? _readNumber(Map<String, dynamic> row, String key) =>
    (row[key] as num?)?.toDouble();

DateTime? _readDate(Map<String, dynamic> row, String key) {
  final value = row[key];
  return value is String ? DateTime.tryParse(value) : null;
}

/// Data access layer for the `products` and `product_prices` tables.
class ProductRepository {
  const ProductRepository(this._supabase);

  final SupabaseClient _supabase;

  // ─── Product list ──────────────────────────────────────────────────────────

  /// Fetches the active product catalogue for [companyId].
  ///
  /// Optionally filters by [search] text (name ILIKE) and [category].
  Future<List<ProductModel>> fetchProducts(
    String companyId, {
    String? search,
    String? category,
    int limit = 200,
    int offset = 0,
  }) async {
    var query = _supabase
        .from('products')
        .select(
          'id, company_id, provider_id, name, name_normalized, sku, barcode, '
          'normalized_name, description, category, category_id, '
          'categories(name), subcategory, unit_price, '
          'currency, unit_type, tax_rate, track_inventory, min_stock_level, '
          'current_stock, image_url, is_active, created_at, updated_at',
        )
        .eq('company_id', companyId)
        .eq('is_active', true);

    if (search != null && search.isNotEmpty) {
      final escaped = search.replaceAll('%', '\\%').replaceAll('_', '\\_');
      query = query.ilike('name', '%$escaped%');
    }

    final response = await query
        .order('name', ascending: true)
        .range(offset, offset + limit - 1);

    final products =
        await compute(_parseProductList, response as List<dynamic>);
    if (category == null || category.isEmpty) {
      return products;
    }
    return products
        .where((product) => product.displayCategory == category)
        .toList();
  }

  Future<List<ProductIntelligenceSummaryModel>> fetchProductIntelligence(
    String companyId, {
    String? search,
    String? category,
    ProductCatalogueFilter filter = ProductCatalogueFilter.all,
    int limit = 240,
  }) async {
    final products =
        await _fetchProductsForIntelligence(companyId, limit: limit);
    final productIds = products.map((product) => product.id).toList();
    if (productIds.isEmpty) return const [];

    final priceRows = await _fetchCompanyProductPrices(
      companyId,
      productIds: productIds,
    );
    final fallbackRows = priceRows.isEmpty
        ? await _fetchDocumentItemPriceFallback(
            companyId,
            productIds: productIds,
          )
        : const <Map<String, dynamic>>[];
    final rowsByProduct = <String, List<Map<String, dynamic>>>{};
    for (final row in priceRows.isEmpty ? fallbackRows : priceRows) {
      final productId = row['product_id'] as String?;
      if (productId == null) continue;
      rowsByProduct.putIfAbsent(productId, () => []).add(row);
    }

    final statsByProduct = await _fetchPriceStatsByProduct(companyId);
    final openAnomaliesByProduct =
        await _fetchOpenAnomaliesByProduct(companyId);

    final summaries = products
        .map(
          (product) => _buildProductSummary(
            product: product,
            priceRows: rowsByProduct[product.id] ?? const [],
            stats: statsByProduct[product.id],
            anomaly: openAnomaliesByProduct[product.id],
          ),
        )
        .where(
          (summary) => _matchesProductSummaryFilters(
            summary,
            search: search,
            category: category,
            filter: filter,
          ),
        )
        .toList()
      ..sort((a, b) {
        final reviewCompare = (b.needsReview ? 1 : 0) - (a.needsReview ? 1 : 0);
        if (reviewCompare != 0) return reviewCompare;
        final dateA = a.lastPurchasedAt;
        final dateB = b.lastPurchasedAt;
        if (dateA != null && dateB != null) return dateB.compareTo(dateA);
        if (dateA != null) return -1;
        if (dateB != null) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return summaries;
  }

  Future<List<ProductModel>> _fetchProductsForIntelligence(
    String companyId, {
    int limit = 240,
  }) async {
    final response = await _supabase
        .from('products')
        .select(
          'id, company_id, provider_id, name, name_normalized, sku, barcode, '
          'normalized_name, description, category, category_id, '
          'categories(name), subcategory, unit_price, '
          'currency, unit_type, tax_rate, track_inventory, min_stock_level, '
          'current_stock, is_active, created_at, updated_at',
        )
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name', ascending: true)
        .limit(limit);

    return compute(_parseProductList, response as List<dynamic>);
  }

  // ─── Product detail ────────────────────────────────────────────────────────

  /// Fetches a single product by [productId], scoped to [companyId].
  Future<ProductModel?> fetchProductById(
    String productId,
    String companyId,
  ) async {
    final response = await _supabase
        .from('products')
        .select(
          'id, company_id, provider_id, name, name_normalized, sku, barcode, '
          'normalized_name, description, category, category_id, '
          'categories(name), subcategory, unit_price, '
          'currency, unit_type, tax_rate, track_inventory, min_stock_level, '
          'current_stock, image_url, is_active, created_at, updated_at',
        )
        .eq('id', productId)
        .eq('company_id', companyId)
        .maybeSingle();

    if (response == null) return null;
    return ProductModel.fromJson(response);
  }

  // ─── Price history ─────────────────────────────────────────────────────────

  /// Returns price observations for [productId] scoped to [companyId],
  /// ordered by most recent first. Caps at [limit] rows.
  Future<List<ProductPriceModel>> fetchPriceHistory(
    String productId,
    String companyId, {
    int limit = 60,
  }) async {
    final response = await _supabase
        .from('product_prices')
        .select(
          'id, company_id, product_id, document_id, document_item_id, '
          'supplier_id, providers(name), price, quantity, unit, date, observed_at',
        )
        .eq('product_id', productId)
        .eq('company_id', companyId)
        .order('observed_at', ascending: false)
        .limit(limit);

    return compute(_parsePriceList, response as List<dynamic>);
  }

  Future<ProductPriceStatsModel?> fetchPriceStats(
    String productId,
    String companyId,
  ) async {
    try {
      final response = await _supabase
          .from('product_price_stats')
          .select()
          .eq('product_id', productId)
          .eq('company_id', companyId)
          .maybeSingle();

      if (response == null) return null;
      return ProductPriceStatsModel.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') return null;
      rethrow;
    }
  }

  Future<List<PriceAnomalyModel>> fetchPriceAnomalies(
    String productId,
    String companyId, {
    bool includeResolved = true,
    int limit = 50,
  }) async {
    try {
      var query = _supabase
          .from('price_anomalies')
          .select(
            'id, company_id, product_id, supplier_id, providers(name), '
            'document_id, document_item_id, product_price_id, anomaly_type, '
            'current_price, expected_price, deviation_percent, severity, '
            'confidence_score, explanation, heuristic_details, ai_confidence, '
            'ai_explanation, resolved, resolution_status, created_at',
          )
          .eq('product_id', productId)
          .eq('company_id', companyId);

      if (!includeResolved) {
        query = query.eq('resolved', false);
      }

      final response =
          await query.order('created_at', ascending: false).limit(limit);

      return compute(_parseAnomalyList, response as List<dynamic>);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') return [];
      rethrow;
    }
  }

  Future<void> resolvePriceAnomaly({
    required String companyId,
    required String anomalyId,
    required String resolutionStatus,
    String? note,
  }) async {
    await _supabase.rpc(
      'resolve_price_anomaly',
      params: {
        'p_company_id': companyId,
        'p_anomaly_id': anomalyId,
        'p_resolution_status': resolutionStatus,
        'p_resolution_note': note,
      },
    );
  }

  // ─── Distinct categories ───────────────────────────────────────────────────

  /// Returns distinct non-null category values for the company's catalogue.
  Future<List<String>> fetchCategories(String companyId) async {
    final response = await _supabase
        .from('products')
        .select('category, categories(name)')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name', ascending: true);

    final seen = <String>{};
    final categories = <String>[];
    for (final row in (response as List)) {
      final map = row as Map<String, dynamic>;
      final cat = ((map['categories'] as Map<String, dynamic>?)?['name'] ??
          map['category']) as String?;
      if (cat != null && cat.isNotEmpty && seen.add(cat)) {
        categories.add(cat);
      }
    }
    return categories;
  }

  Future<List<String>> fetchAliases(String productId, String companyId) async {
    final response = await _supabase
        .from('product_aliases')
        .select('raw_name')
        .eq('product_id', productId)
        .eq('company_id', companyId)
        .order('created_at', ascending: true);

    return compute(_parseAliasList, response as List<dynamic>);
  }

  Future<List<ProductSupplierBreakdownModel>> buildSupplierBreakdown(
    String productId,
    String companyId,
  ) async {
    final prices = await fetchPriceHistory(productId, companyId, limit: 200);
    final grouped = <String, List<ProductPriceModel>>{};

    for (final price in prices) {
      final key = price.supplierId ?? 'unknown';
      grouped.putIfAbsent(key, () => []).add(price);
    }

    final results = grouped.entries.map((entry) {
      final rows = [...entry.value]
        ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
      final total = rows.fold<double>(0, (sum, row) => sum + row.price);
      return ProductSupplierBreakdownModel(
        supplierId: rows.first.supplierId,
        supplierName: rows.first.supplierName ?? 'Unknown supplier',
        purchaseCount: rows.length,
        averagePrice: total / rows.length,
        latestPrice: rows.first.price,
        lastPurchasedAt: rows.first.date ?? rows.first.observedAt,
      );
    }).toList()
      ..sort((a, b) => b.purchaseCount.compareTo(a.purchaseCount));

    return results;
  }

  Future<List<ProductLinkedDocumentModel>> fetchLinkedDocuments(
    String productId,
    String companyId, {
    int limit = 80,
  }) async {
    final response = await _supabase
        .from('product_prices')
        .select(
          'document_id, date, observed_at, documents!inner(id, company_id, '
          'document_number, document_type, document_date, total_amount, '
          'currency, file_path, providers(name))',
        )
        .eq('product_id', productId)
        .eq('company_id', companyId)
        .eq('documents.company_id', companyId)
        .not('document_id', 'is', null)
        .order('observed_at', ascending: false)
        .limit(limit);

    final grouped = <String, _LinkedDocumentAccumulator>{};
    for (final raw in response as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final document = Map<String, dynamic>.from(row['documents'] as Map);
      final documentId = document['id'] as String?;
      if (documentId == null) continue;

      final accumulator = grouped.putIfAbsent(
        documentId,
        () => _LinkedDocumentAccumulator(document),
      );
      accumulator.lineCount += 1;
    }

    final documents = grouped.values.map((entry) => entry.toModel()).toList()
      ..sort((a, b) {
        final left = a.documentDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.documentDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });

    return documents;
  }

  Future<ProductInsightsModel?> buildInsights(
    String productId,
    String companyId,
  ) async {
    final prices = await fetchPriceHistory(productId, companyId, limit: 200);
    if (prices.isEmpty) return null;

    final sorted = [...prices]
      ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    final latest = sorted.first;
    final previous = sorted.length > 1 ? sorted[1] : null;
    final minimum = sorted
        .map((row) => row.price)
        .reduce((left, right) => left < right ? left : right);
    final maximum = sorted
        .map((row) => row.price)
        .reduce((left, right) => left > right ? left : right);
    final average =
        sorted.fold<double>(0, (sum, row) => sum + row.price) / sorted.length;
    final change = previous == null ? null : latest.price - previous.price;
    final changePercent = previous == null || previous.price == 0
        ? null
        : ((latest.price - previous.price) / previous.price) * 100;
    final supplierCount = sorted
        .map((row) => row.supplierId ?? row.supplierName ?? 'unknown')
        .toSet()
        .length;

    return ProductInsightsModel(
      latestPrice: latest.price,
      averagePrice: average,
      minimumPrice: minimum,
      maximumPrice: maximum,
      changeFromPrevious: change,
      changePercentFromPrevious: changePercent,
      purchaseCount: sorted.length,
      supplierCount: supplierCount,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchCompanyProductPrices(
    String companyId, {
    required List<String> productIds,
  }) async {
    final response = await _supabase
        .from('product_prices')
        .select(
          'id, company_id, product_id, supplier_id, providers(name), price, '
          'quantity, date, observed_at',
        )
        .eq('company_id', companyId)
        .inFilter('product_id', productIds)
        .order('observed_at', ascending: false)
        .limit(1000);

    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchDocumentItemPriceFallback(
    String companyId, {
    required List<String> productIds,
  }) async {
    final response = await _supabase
        .from('document_items')
        .select(
          'id, company_id, product_id, unit_price, quantity, line_total, '
          'created_at, documents!inner(id, company_id, status, deleted_at, '
          'is_duplicate, merge_status, document_date, provider_id, providers(name))',
        )
        .eq('company_id', companyId)
        .eq('documents.company_id', companyId)
        .eq('documents.status', 'completed')
        .eq('documents.is_duplicate', false)
        .neq('documents.merge_status', 'merged')
        .isFilter('documents.deleted_at', null)
        .inFilter('product_id', productIds)
        .order('created_at', ascending: false)
        .limit(1000);

    return (response as List).map((row) {
      final data = Map<String, dynamic>.from(row as Map);
      final document = Map<String, dynamic>.from(data['documents'] as Map);
      final price = _readNumber(data, 'unit_price') ??
          _fallbackUnitPrice(
            lineTotal: _readNumber(data, 'line_total'),
            quantity: _readNumber(data, 'quantity'),
          );
      return {
        'id': data['id'],
        'company_id': data['company_id'],
        'product_id': data['product_id'],
        'supplier_id': document['provider_id'],
        'providers': document['providers'],
        'price': price,
        'quantity': data['quantity'],
        'date': document['document_date'],
        'observed_at': document['document_date'] != null
            ? '${document['document_date']}T12:00:00.000Z'
            : data['created_at'],
      };
    }).toList();
  }

  Future<Map<String, ProductPriceStatsModel>> _fetchPriceStatsByProduct(
    String companyId,
  ) async {
    try {
      final response = await _supabase
          .from('product_price_stats')
          .select()
          .eq('company_id', companyId);

      return {
        for (final row in response as List)
          ProductPriceStatsModel.fromJson(row as Map<String, dynamic>)
              .productId: ProductPriceStatsModel.fromJson(row),
      };
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') return const {};
      rethrow;
    }
  }

  Future<Map<String, PriceAnomalyModel>> _fetchOpenAnomaliesByProduct(
    String companyId,
  ) async {
    try {
      final response = await _supabase
          .from('price_anomalies')
          .select(
            'id, company_id, product_id, supplier_id, providers(name), '
            'document_id, document_item_id, product_price_id, anomaly_type, '
            'current_price, expected_price, deviation_percent, severity, '
            'confidence_score, explanation, heuristic_details, ai_confidence, '
            'ai_explanation, resolved, resolution_status, created_at',
          )
          .eq('company_id', companyId)
          .eq('resolved', false)
          .order('created_at', ascending: false)
          .limit(200);

      final results = <String, PriceAnomalyModel>{};
      for (final row in response as List) {
        final anomaly = PriceAnomalyModel.fromJson(row as Map<String, dynamic>);
        results.putIfAbsent(anomaly.productId, () => anomaly);
      }
      return results;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') return const {};
      rethrow;
    }
  }

  ProductIntelligenceSummaryModel _buildProductSummary({
    required ProductModel product,
    required List<Map<String, dynamic>> priceRows,
    required ProductPriceStatsModel? stats,
    required PriceAnomalyModel? anomaly,
  }) {
    final sorted = [...priceRows]..sort((a, b) {
        final left = _readDate(b, 'observed_at') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final right = _readDate(a, 'observed_at') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return left.compareTo(right);
      });
    final latest = sorted.isNotEmpty ? sorted.first : null;
    final previous = sorted.length > 1 ? sorted[1] : null;
    final latestPrice = _readNumber(latest ?? const {}, 'price') ??
        stats?.lastPrice ??
        product.unitPrice;
    final previousPrice = _readNumber(previous ?? const {}, 'price');
    final average90d = sorted.isEmpty
        ? stats?.averagePrice
        : _averageSince(
              sorted,
              DateTime.now().subtract(const Duration(days: 90)),
            ) ??
            stats?.averagePrice;
    final average30d = stats?.thirtyDayAverage ??
        _averageSince(
          sorted,
          DateTime.now().subtract(const Duration(days: 30)),
        );
    final variationVsPrevious =
        latestPrice == null || previousPrice == null || previousPrice == 0
            ? stats?.trendPercent
            : ((latestPrice - previousPrice) / previousPrice) * 100;
    final variationVsAverage =
        latestPrice == null || average90d == null || average90d == 0
            ? null
            : ((latestPrice - average90d) / average90d) * 100;
    final direction = _directionFor(variationVsPrevious);
    final severity = _severityFor(
      variationVsPrevious?.abs() ?? variationVsAverage?.abs(),
      latestPrice,
    );
    final supplier = ((latest?['providers'] as Map?)?['name'] as String?) ??
        anomaly?.supplierName;
    final lastPurchasedAt = _readDate(latest ?? const {}, 'date') ??
        _readDate(latest ?? const {}, 'observed_at') ??
        stats?.lastPurchaseDate;
    final reasoning = anomaly?.aiExplanation ??
        anomaly?.explanation ??
        _deterministicReasoning(
          productName: product.name,
          variation: variationVsPrevious,
          severity: severity,
          purchaseCount: sorted.length,
        );

    return ProductIntelligenceSummaryModel(
      product: product,
      latestPrice: latestPrice,
      previousPrice: previousPrice,
      averagePrice30d: average30d,
      averagePrice90d: average90d,
      variationVsPreviousPercent: variationVsPrevious,
      variationVsAveragePercent: variationVsAverage,
      direction: direction,
      severity: anomaly == null ? severity : ProductPriceSeverity.high,
      supplierName: supplier,
      lastPurchasedAt: lastPurchasedAt,
      purchaseCount: sorted.isEmpty ? stats?.sampleCount ?? 0 : sorted.length,
      needsReview: anomaly?.isOpen ?? false,
      reasoning: reasoning,
    );
  }

  bool _matchesProductSummaryFilters(
    ProductIntelligenceSummaryModel summary, {
    required String? search,
    required String? category,
    required ProductCatalogueFilter filter,
  }) {
    if (category != null && category.isNotEmpty) {
      if (category == 'Uncategorized') {
        if ((summary.category ?? '').isNotEmpty) return false;
      } else if (summary.category != category) {
        return false;
      }
    }

    switch (filter) {
      case ProductCatalogueFilter.all:
        break;
      case ProductCatalogueFilter.priceChanges:
        if (!summary.hasPriceChange) return false;
      case ProductCatalogueFilter.needsReview:
        if (!summary.needsReview) return false;
      case ProductCatalogueFilter.uncategorized:
        if ((summary.category ?? '').isNotEmpty) return false;
    }

    final query = search?.trim().toLowerCase();
    if (query == null || query.isEmpty) return true;
    final haystack = [
      summary.name,
      summary.product.nameNormalized,
      summary.category,
      summary.supplierName,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(query);
  }

  double? _fallbackUnitPrice({double? lineTotal, double? quantity}) {
    if (lineTotal == null || quantity == null || quantity <= 0) return null;
    return lineTotal / quantity;
  }

  double? _averageSince(List<Map<String, dynamic>> rows, DateTime since) {
    final values = rows
        .where((row) {
          final date = _readDate(row, 'date') ?? _readDate(row, 'observed_at');
          return date != null && !date.isBefore(since);
        })
        .map((row) => _readNumber(row, 'price'))
        .whereType<double>()
        .toList();

    if (values.isEmpty) return null;
    return values.fold<double>(0, (sum, value) => sum + value) / values.length;
  }

  ProductPriceDirection _directionFor(double? variation) {
    if (variation == null) return ProductPriceDirection.unknown;
    if (variation.abs() < 1) return ProductPriceDirection.stable;
    return variation > 0
        ? ProductPriceDirection.up
        : ProductPriceDirection.down;
  }

  ProductPriceSeverity _severityFor(double? variation, double? latestPrice) {
    if (latestPrice == null) return ProductPriceSeverity.noPrice;
    if (variation == null || variation < 5) return ProductPriceSeverity.stable;
    if (variation < 15) return ProductPriceSeverity.watch;
    if (variation < 30) return ProductPriceSeverity.high;
    return ProductPriceSeverity.critical;
  }

  String? _deterministicReasoning({
    required String productName,
    required double? variation,
    required ProductPriceSeverity severity,
    required int purchaseCount,
  }) {
    if (purchaseCount < 2 || variation == null) return null;
    if (severity == ProductPriceSeverity.stable) {
      return '$productName is stable across recent purchases.';
    }
    final direction = variation > 0 ? 'increased' : 'decreased';
    return '$productName $direction ${variation.abs().toStringAsFixed(1)}% compared with the previous purchase.';
  }
}

class _LinkedDocumentAccumulator {
  _LinkedDocumentAccumulator(this.document);

  final Map<String, dynamic> document;
  int lineCount = 0;

  ProductLinkedDocumentModel toModel() {
    final documentNumber = document['document_number'] as String?;
    final filePath = document['file_path'] as String?;
    final fallbackName = filePath == null || filePath.isEmpty
        ? 'Document'
        : filePath.split('/').last;
    final type = document['document_type'] as String? ?? 'document';
    final supplierName =
        (document['providers'] as Map<String, dynamic>?)?['name'] as String?;

    return ProductLinkedDocumentModel(
      documentId: document['id'] as String,
      title: documentNumber == null || documentNumber.isEmpty
          ? fallbackName
          : documentNumber,
      documentType: type.replaceAll('_', ' '),
      supplierName: supplierName,
      documentDate: document['document_date'] == null
          ? null
          : DateTime.tryParse(document['document_date'] as String),
      totalAmount: (document['total_amount'] as num?)?.toDouble(),
      currency: document['currency'] as String?,
      lineCount: lineCount,
    );
  }
}
