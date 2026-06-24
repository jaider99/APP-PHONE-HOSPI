import 'package:flutter/foundation.dart';
import 'package:hospi_dash/models/chart_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'intelligence_models.dart';

/// Intelligence query service for dashboard category/product cards.
///
/// All queries are tenant-scoped via `.eq('company_id', companyId)`.
/// RLS on the base tables still enforces tenant boundaries server-side.
class IntelligenceService {
  const IntelligenceService(this._supabase);

  final SupabaseClient _supabase;

  // ── Category intelligence ──────────────────────────────────────────────────

  /// Returns all active categories with spend aggregates from
  /// productized line-item spend for the selected dashboard [period].
  /// Falls back to categorized document totals only for documents that do not
  /// yet have categorized product price rows, so productized invoices are not
  /// double counted.
  Future<List<CategoryIntelligence>> fetchCategoryIntelligence(
    String companyId, {
    ChartPeriod period = ChartPeriod.oneMonth,
  }) async {
    try {
      final today = _today();
      final current = _dateRangeFor(period, today);
      final prior = _priorRangeFor(current);

      final categoryRows = await _fetchCategoryRows(companyId);
      final currentPriceRows = await _fetchProductPriceRows(
        companyId: companyId,
        range: current,
      );
      final priorPriceRows = await _fetchProductPriceRows(
        companyId: companyId,
        range: prior,
      );

      final categories = <String, _CategoryAccumulator>{};
      for (final row in categoryRows) {
        final data = row as Map<String, dynamic>;
        final id = data['id'] as String?;
        if (id == null) continue;
        categories[id] = _CategoryAccumulator.fromCategory(data);
      }

      final currentProductizedDocuments = <String>{};
      final priorProductizedDocuments = <String>{};

      _addProductCategorySpend(
        rows: currentPriceRows,
        categories: categories,
        productizedDocumentIds: currentProductizedDocuments,
        isCurrent: true,
      );
      _addProductCategorySpend(
        rows: priorPriceRows,
        categories: categories,
        productizedDocumentIds: priorProductizedDocuments,
        isCurrent: false,
      );

      final currentDocumentRows = await _fetchCategorizedDocumentRows(
        companyId: companyId,
        range: current,
      );
      final priorDocumentRows = await _fetchCategorizedDocumentRows(
        companyId: companyId,
        range: prior,
      );

      debugPrint(
        '[CategoryIntelligence] companyId=$companyId '
        'current=${_dateStr(current.start)}..${_dateStr(current.end)} '
        'prior=${_dateStr(prior.start)}..${_dateStr(prior.end)} '
        'sourceTable=product_prices '
        'rowCount=${currentPriceRows.length}/${priorPriceRows.length} '
        'totalAmount=${_sumProductSpend(currentPriceRows).toStringAsFixed(2)}/'
        '${_sumProductSpend(priorPriceRows).toStringAsFixed(2)}',
      );
      debugPrint(
        '[CategoryIntelligence] companyId=$companyId '
        'current=${_dateStr(current.start)}..${_dateStr(current.end)} '
        'prior=${_dateStr(prior.start)}..${_dateStr(prior.end)} '
        'sourceTable=documents '
        'rowCount=${currentDocumentRows.length}/${priorDocumentRows.length} '
        'totalAmount=${_sumDocumentSpend(currentDocumentRows, current).toStringAsFixed(2)}/'
        '${_sumDocumentSpend(priorDocumentRows, prior).toStringAsFixed(2)}',
      );

      _addDocumentCategoryFallbackSpend(
        rows: currentDocumentRows,
        categories: categories,
        productizedDocumentIds: currentProductizedDocuments,
        range: current,
        isCurrent: true,
      );
      _addDocumentCategoryFallbackSpend(
        rows: priorDocumentRows,
        categories: categories,
        productizedDocumentIds: priorProductizedDocuments,
        range: prior,
        isCurrent: false,
      );

      return categories.values.map((category) => category.toModel()).toList()
        ..sort((a, b) {
          final currentCompare =
              b.currentMonthSpent.compareTo(a.currentMonthSpent);
          if (currentCompare != 0) return currentCompare;
          return b.totalSpent.compareTo(a.totalSpent);
        });
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') return [];
      debugPrint(
        '[CategoryIntelligence] source=documents/product_prices error=$e',
      );
      return [];
    } catch (e) {
      debugPrint(
        '[CategoryIntelligence] source=documents/product_prices error=$e',
      );
      return [];
    }
  }

  // ── Top products ───────────────────────────────────────────────────────────

  /// Returns the top [limit] products ranked by current-month spend from
  /// product price observations in the selected dashboard [period].
  ///
  /// Set [includeAllTime] to rank by all available product price history.
  Future<List<ProductIntelligenceSummary>> fetchTopProducts(
    String companyId, {
    int limit = 10,
    bool includeAllTime = false,
    ChartPeriod period = ChartPeriod.oneMonth,
  }) async {
    try {
      final today = _today();
      final current = _dateRangeFor(period, today);
      final prior = _priorRangeFor(current);
      final currentRows = await _fetchProductPriceRows(
        companyId: companyId,
        range: includeAllTime ? null : current,
      );
      final priorRows = includeAllTime
          ? const <dynamic>[]
          : await _fetchProductPriceRows(companyId: companyId, range: prior);

      final products = <String, _ProductAccumulator>{};
      _addProductSpendRows(
        rows: currentRows,
        products: products,
        isCurrent: true,
        countAsAllTimeCurrent: includeAllTime,
      );
      _addProductSpendRows(
        rows: priorRows,
        products: products,
        isCurrent: false,
      );

      final ranked = products.values
          .where((product) => includeAllTime || product.currentSpent > 0)
          .map((product) => product.toModel())
          .toList()
        ..sort((a, b) {
          final primary = includeAllTime
              ? b.totalSpent.compareTo(a.totalSpent)
              : b.currentMonthSpent.compareTo(a.currentMonthSpent);
          if (primary != 0) return primary;
          return b.purchaseCount.compareTo(a.purchaseCount);
        });

      return ranked.take(limit).toList();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') return [];
      debugPrint('IntelligenceService.fetchTopProducts: $e');
      return [];
    } catch (e) {
      debugPrint('IntelligenceService.fetchTopProducts: $e');
      return [];
    }
  }

  // ── Price variance alerts ─────────────────────────────────────────────────

  /// Returns products where `max_price / min_price > [threshold]`
  /// (default 1.20 = 20 % variance) — potential price anomalies worth reviewing.
  ///
  /// Ordered by variance ratio descending (highest variance first).
  Future<List<ProductIntelligenceSummary>> fetchPriceVarianceAlerts(
    String companyId, {
    double threshold = 1.20,
    int limit = 10,
  }) async {
    try {
      // Fetch all products with at least 2 price data points so variance is meaningful.
      final response = await _supabase
          .from('v_top_products_by_spend')
          .select()
          .eq('company_id', companyId)
          .not('min_price', 'is', null)
          .not('max_price', 'is', null)
          .gt('purchase_count', 1)
          .order('total_spent', ascending: false)
          .limit(200); // fetch more; filter + sort client-side for ratio

      final all = (response as List)
          .map(
            (j) =>
                ProductIntelligenceSummary.fromJson(j as Map<String, dynamic>),
          )
          .toList();

      final alerts = all
          .where(
            (p) =>
                p.minPrice != null &&
                p.minPrice! > 0 &&
                p.maxPrice != null &&
                (p.maxPrice! / p.minPrice!) >= threshold,
          )
          .toList()
        ..sort((a, b) {
          final ra = a.minPrice! > 0 ? a.maxPrice! / a.minPrice! : 0.0;
          final rb = b.minPrice! > 0 ? b.maxPrice! / b.minPrice! : 0.0;
          return rb.compareTo(ra);
        });

      return alerts.take(limit).toList();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') return [];
      debugPrint('IntelligenceService.fetchPriceVarianceAlerts: $e');
      return [];
    } catch (e) {
      debugPrint('IntelligenceService.fetchPriceVarianceAlerts: $e');
      return [];
    }
  }

  Future<List<dynamic>> _fetchCategoryRows(String companyId) {
    return _supabase
        .from('categories')
        .select('id, company_id, name, color_hex, icon, sort_order')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
  }

  Future<List<dynamic>> _fetchProductPriceRows({
    required String companyId,
    _DateRange? range,
  }) {
    var query = _supabase
        .from('product_prices')
        .select(
          'id, company_id, product_id, document_id, supplier_id, price, quantity, unit, '
          'date, observed_at, products!inner(id, name, image_url, is_active, '
          'category_id, categories(id, name, color_hex)), '
          'documents!inner(id, status, is_duplicate, merge_status, deleted_at), '
          'providers(name)',
        )
        .eq('company_id', companyId)
        .eq('products.is_active', true)
        .eq('documents.status', 'completed')
        .eq('documents.is_duplicate', false)
        .neq('documents.merge_status', 'merged')
        .isFilter('documents.deleted_at', null);

    if (range != null) {
      query = query
          .not('date', 'is', null)
          .gte('date', _dateStr(range.start))
          .lte('date', _dateStr(range.end));
    }

    return query.order('observed_at', ascending: false);
  }

  Future<List<dynamic>> _fetchCategorizedDocumentRows({
    required String companyId,
    required _DateRange range,
  }) {
    return _supabase
        .from('documents')
        .select(
          'id, company_id, category_id, total_amount, document_date, created_at, '
          'categories!documents_category_id_fkey(id, name, color_hex, icon, sort_order)',
        )
        .eq('company_id', companyId)
        .eq('status', 'completed')
        .eq('is_duplicate', false)
        .neq('merge_status', 'merged')
        .not('category_id', 'is', null)
        .not('total_amount', 'is', null)
        .isFilter('deleted_at', null)
        .or(
          'document_date.gte.${_dateStr(range.start)},created_at.gte.${_dateStr(range.start)}',
        )
        .or(
          'document_date.lte.${_dateStr(range.end)},document_date.is.null',
        );
  }

  void _addProductCategorySpend({
    required List<dynamic> rows,
    required Map<String, _CategoryAccumulator> categories,
    required Set<String> productizedDocumentIds,
    required bool isCurrent,
  }) {
    for (final row in rows) {
      final data = row as Map<String, dynamic>;
      final product = _asMap(data['products']);
      final category = _asMap(product?['categories']);
      final categoryId =
          product?['category_id'] as String? ?? category?['id'] as String?;
      if (categoryId == null || category == null) continue;

      final documentId = data['document_id'] as String?;
      if (documentId != null) productizedDocumentIds.add(documentId);

      final accumulator = categories.putIfAbsent(
        categoryId,
        () => _CategoryAccumulator.fromCategory({
          ...category,
          'company_id': data['company_id'],
        }),
      );
      accumulator.addSpend(
        amount: _lineSpend(data),
        documentId: documentId ?? data['id'] as String?,
        date: _parseDate(data['date'] as String?),
        isCurrent: isCurrent,
      );
    }
  }

  void _addDocumentCategoryFallbackSpend({
    required List<dynamic> rows,
    required Map<String, _CategoryAccumulator> categories,
    required Set<String> productizedDocumentIds,
    required _DateRange range,
    required bool isCurrent,
  }) {
    for (final row in rows) {
      final data = row as Map<String, dynamic>;
      final documentId = data['id'] as String?;
      if (documentId == null || productizedDocumentIds.contains(documentId)) {
        continue;
      }

      final categoryId = data['category_id'] as String?;
      if (categoryId == null) continue;
      final effectiveDate = _effectiveDocumentDate(data);
      if (effectiveDate == null || !_dateInRange(effectiveDate, range)) {
        continue;
      }
      final category = _asMap(data['categories']);
      final accumulator = categories.putIfAbsent(
        categoryId,
        () => _CategoryAccumulator.fromCategory({
          if (category != null) ...category,
          'id': categoryId,
          'company_id': data['company_id'],
          'name': category?['name'] ?? 'Unknown',
        }),
      );
      accumulator.addSpend(
        amount: (data['total_amount'] as num?)?.toDouble() ?? 0,
        documentId: documentId,
        date: effectiveDate,
        isCurrent: isCurrent,
      );
    }
  }

  void _addProductSpendRows({
    required List<dynamic> rows,
    required Map<String, _ProductAccumulator> products,
    required bool isCurrent,
    bool countAsAllTimeCurrent = false,
  }) {
    for (final row in rows) {
      final data = row as Map<String, dynamic>;
      final product = _asMap(data['products']);
      final productId =
          data['product_id'] as String? ?? product?['id'] as String?;
      if (productId == null || product == null) continue;

      final accumulator = products.putIfAbsent(
        productId,
        () => _ProductAccumulator.fromRow(productId, data, product),
      );
      accumulator.addSpend(
        row: data,
        amount: _lineSpend(data),
        isCurrent: isCurrent || countAsAllTimeCurrent,
      );
    }
  }

  double _lineSpend(Map<String, dynamic> row) {
    final price = (row['price'] as num?)?.toDouble() ?? 0;
    final rawQuantity = (row['quantity'] as num?)?.toDouble();
    final quantity =
        rawQuantity == null || rawQuantity <= 0 ? 1.0 : rawQuantity;
    return price * quantity;
  }

  double _sumProductSpend(List<dynamic> rows) {
    return rows.fold(0.0, (sum, row) {
      if (row is! Map<String, dynamic>) return sum;
      return sum + _lineSpend(row);
    });
  }

  double _sumDocumentSpend(List<dynamic> rows, _DateRange range) {
    return rows.fold(0.0, (sum, row) {
      if (row is! Map<String, dynamic>) return sum;
      final effectiveDate = _effectiveDocumentDate(row);
      if (effectiveDate == null || !_dateInRange(effectiveDate, range)) {
        return sum;
      }
      return sum + ((row['total_amount'] as num?)?.toDouble() ?? 0);
    });
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) return _asMap(value.first);
    return null;
  }

  DateTime? _parseDate(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  DateTime? _effectiveDocumentDate(Map<String, dynamic> row) {
    return _parseDate(row['document_date'] as String?) ??
        _parseDate(row['created_at'] as String?);
  }

  bool _dateInRange(DateTime date, _DateRange range) {
    final normalized = DateTime(date.year, date.month, date.day);
    return !normalized.isBefore(range.start) && !normalized.isAfter(range.end);
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _dateStr(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  _DateRange _dateRangeFor(ChartPeriod period, DateTime today) {
    return switch (period) {
      ChartPeriod.oneWeek => _DateRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        ),
      ChartPeriod.oneMonth => _DateRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        ),
      ChartPeriod.threeMonths => _DateRange(
          start: today.subtract(const Duration(days: 89)),
          end: today,
        ),
      ChartPeriod.sixMonths => _DateRange(
          start: today.subtract(const Duration(days: 179)),
          end: today,
        ),
      ChartPeriod.oneYear => _DateRange(
          start: today.subtract(const Duration(days: 364)),
          end: today,
        ),
    };
  }

  _DateRange _priorRangeFor(_DateRange current) {
    final days = current.end.difference(current.start).inDays;
    final priorEnd = current.start.subtract(const Duration(days: 1));
    return _DateRange(
      start: priorEnd.subtract(Duration(days: days)),
      end: priorEnd,
    );
  }
}

class _DateRange {
  const _DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _CategoryAccumulator {
  _CategoryAccumulator({
    required this.id,
    required this.companyId,
    required this.name,
    this.colorHex,
    this.icon,
  });

  factory _CategoryAccumulator.fromCategory(Map<String, dynamic> row) {
    return _CategoryAccumulator(
      id: row['id'] as String,
      companyId: row['company_id'] as String? ?? '',
      name: row['name'] as String? ?? 'Unknown',
      colorHex: row['color_hex'] as String?,
      icon: row['icon'] as String?,
    );
  }

  final String id;
  final String companyId;
  final String name;
  final String? colorHex;
  final String? icon;
  final documentIds = <String>{};
  double currentSpent = 0;
  double priorSpent = 0;
  DateTime? lastDocumentDate;

  double get totalSpent => currentSpent + priorSpent;

  void addSpend({
    required double amount,
    required bool isCurrent,
    String? documentId,
    DateTime? date,
  }) {
    if (amount <= 0) return;
    if (isCurrent) {
      currentSpent += amount;
    } else {
      priorSpent += amount;
    }
    if (documentId != null) documentIds.add(documentId);
    if (date != null &&
        (lastDocumentDate == null || date.isAfter(lastDocumentDate!))) {
      lastDocumentDate = date;
    }
  }

  CategoryIntelligence toModel() {
    return CategoryIntelligence(
      id: id,
      companyId: companyId,
      name: name,
      colorHex: colorHex,
      icon: icon,
      totalDocuments: documentIds.length,
      totalSpent: totalSpent,
      currentMonthSpent: currentSpent,
      priorMonthSpent: priorSpent,
      lastDocumentDate: lastDocumentDate,
    );
  }
}

class _ProductAccumulator {
  _ProductAccumulator({
    required this.productId,
    required this.companyId,
    required this.productName,
    this.imageUrl,
    this.categoryId,
    this.categoryName,
    this.categoryColor,
  });

  factory _ProductAccumulator.fromRow(
    String productId,
    Map<String, dynamic> row,
    Map<String, dynamic> product,
  ) {
    final category = _staticAsMap(product['categories']);
    return _ProductAccumulator(
      productId: productId,
      companyId: row['company_id'] as String? ?? '',
      productName: product['name'] as String? ?? '',
      imageUrl: product['image_url'] as String?,
      categoryId: product['category_id'] as String?,
      categoryName: category?['name'] as String?,
      categoryColor: category?['color_hex'] as String?,
    );
  }

  final String productId;
  final String companyId;
  final String productName;
  final String? imageUrl;
  final String? categoryId;
  final String? categoryName;
  final String? categoryColor;
  final purchaseIds = <String>{};
  double totalQuantity = 0;
  double totalSpent = 0;
  double currentSpent = 0;
  double priorSpent = 0;
  double? latestPrice;
  double? minPrice;
  double? maxPrice;
  String? supplierId;
  String? supplierName;
  DateTime? latestObservedAt;

  void addSpend({
    required Map<String, dynamic> row,
    required double amount,
    required bool isCurrent,
  }) {
    if (amount <= 0) return;
    totalSpent += amount;
    if (isCurrent) {
      currentSpent += amount;
    } else {
      priorSpent += amount;
    }
    final quantity = (row['quantity'] as num?)?.toDouble();
    totalQuantity += quantity == null || quantity <= 0 ? 1 : quantity;
    final price = (row['price'] as num?)?.toDouble();
    if (price != null) {
      minPrice =
          minPrice == null ? price : (price < minPrice! ? price : minPrice);
      maxPrice =
          maxPrice == null ? price : (price > maxPrice! ? price : maxPrice);
    }
    final purchaseId = row['id'] as String?;
    if (purchaseId != null) purchaseIds.add(purchaseId);

    final observedAt = DateTime.tryParse(row['observed_at'] as String? ?? '');
    if (observedAt != null &&
        (latestObservedAt == null || observedAt.isAfter(latestObservedAt!))) {
      latestObservedAt = observedAt;
      latestPrice = price;
      supplierId = row['supplier_id'] as String?;
      supplierName = _staticAsMap(row['providers'])?['name'] as String?;
    }
  }

  ProductIntelligenceSummary toModel() {
    return ProductIntelligenceSummary(
      productId: productId,
      companyId: companyId,
      productName: productName,
      imageUrl: imageUrl,
      categoryId: categoryId,
      categoryName: categoryName,
      categoryColor: categoryColor,
      supplierId: supplierId,
      supplierName: supplierName,
      totalQuantity: totalQuantity,
      totalSpent: totalSpent,
      currentMonthSpent: currentSpent,
      priorMonthSpent: priorSpent,
      latestPrice: latestPrice,
      minPrice: minPrice,
      maxPrice: maxPrice,
      purchaseCount: purchaseIds.length,
    );
  }

  static Map<String, dynamic>? _staticAsMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) return _staticAsMap(value.first);
    return null;
  }
}
