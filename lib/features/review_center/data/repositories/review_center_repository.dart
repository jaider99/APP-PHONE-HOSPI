import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/features/review_center/data/models/review_item.dart';
import 'package:hospi_dash/services/extraction_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const int defaultReviewCenterItemLimit = 120;

class ReviewCenterRepository {
  const ReviewCenterRepository(this._client);

  final SupabaseClient _client;

  Future<List<ReviewItem>> fetchOpenItems({
    required String companyId,
    int limit = defaultReviewCenterItemLimit,
    List<ReviewType>? types,
  }) async {
    final stopwatch = Stopwatch()..start();
    var query = _client
        .from('review_items')
        .select()
        .eq('company_id', companyId)
        .eq('status', ReviewStatus.open.value);

    final values = types
        ?.where((type) => type != ReviewType.unknown)
        .map((type) => type.value)
        .toList(growable: false);
    if (values != null && values.isNotEmpty) {
      query = query.inFilter('review_type', values);
    }

    final response =
        await query.order('created_at', ascending: false).limit(limit);
    final items = (response as List<dynamic>)
        .map((row) => ReviewItem.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);

    AppLogger.info(
      '[ReviewCenter] fetchOpenItems rows=${items.length} '
      'limit=$limit filters=${values?.length ?? 0} '
      'ms=${stopwatch.elapsedMilliseconds}',
    );

    return items
      ..sort((a, b) {
        final severityCompare = b.severity.rank.compareTo(a.severity.rank);
        if (severityCompare != 0) return severityCompare;
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  Future<ReviewItemCounts> fetchCounts({required String companyId}) async {
    final stopwatch = Stopwatch()..start();
    final response = await _client
        .from('review_items')
        .select('review_type, severity')
        .eq('company_id', companyId)
        .eq('status', ReviewStatus.open.value);
    final rows = response as List<dynamic>;

    final byType = <ReviewType, int>{};
    final bySeverity = <ReviewSeverity, int>{};
    var aiReview = 0;
    var priceAlerts = 0;

    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final type = ReviewType.fromJson(map['review_type'] as String?);
      final severity = ReviewSeverity.fromJson(map['severity'] as String?);
      byType[type] = (byType[type] ?? 0) + 1;
      bySeverity[severity] = (bySeverity[severity] ?? 0) + 1;

      if (type.countsAsAiReview) aiReview++;
      if (type.countsAsPriceAlert) priceAlerts++;
    }

    AppLogger.info(
      '[ReviewCenter] fetchCounts rows=${rows.length} '
      'ms=${stopwatch.elapsedMilliseconds}',
    );

    return ReviewItemCounts(
      open: rows.length,
      critical: bySeverity[ReviewSeverity.critical] ?? 0,
      aiReview: aiReview,
      priceAlerts: priceAlerts,
      byType: byType,
      bySeverity: bySeverity,
    );
  }

  Future<int> syncCompanyReviewItems({required String companyId}) async {
    final stopwatch = Stopwatch()..start();
    final response = await _client.rpc<int>(
      'sync_review_items_for_company',
      params: {'p_company_id': companyId},
    );
    AppLogger.info(
      '[ReviewCenter] syncCompanyReviewItems changed=$response '
      'ms=${stopwatch.elapsedMilliseconds}',
    );
    return response;
  }

  Future<ReviewItem> resolveItem({
    required String reviewItemId,
    Map<String, dynamic>? payload,
  }) {
    return _setItemStatus(
      reviewItemId: reviewItemId,
      action: 'resolved',
      payload: payload,
    );
  }

  Future<ReviewItem> ignoreItem({
    required ReviewItem item,
    Map<String, dynamic>? payload,
  }) async {
    if (item.type == ReviewType.priceAnomaly) {
      await _client.rpc<void>(
        'resolve_price_anomaly',
        params: {
          'p_company_id': item.companyId,
          'p_anomaly_id': item.sourceId,
          'p_resolution_status': 'ignored',
          'p_resolution_note': 'Ignored from Review Center',
        },
      );
    }

    return _setItemStatus(
      reviewItemId: item.id,
      action: 'ignored',
      payload: payload,
    );
  }

  Future<ReviewItem> retryItem({required ReviewItem item}) async {
    final updated = await _setItemStatus(
      reviewItemId: item.id,
      action: 'retry',
      payload: {'source_table': item.sourceTable, 'source_id': item.sourceId},
    );

    if (item.isFailedExtraction && item.isDocumentSource) {
      await const ExtractionService().invokeProcessDocument(
        supabase: _client,
        documentId: item.sourceId,
        companyId: item.companyId,
      );
      await syncCompanyReviewItems(companyId: item.companyId);
    }

    return updated;
  }

  Future<ReviewItem> resolvePriceAnomaly({
    required ReviewItem item,
    String resolutionStatus = 'resolved',
  }) async {
    await _client.rpc<void>(
      'resolve_price_anomaly',
      params: {
        'p_company_id': item.companyId,
        'p_anomaly_id': item.sourceId,
        'p_resolution_status': resolutionStatus,
        'p_resolution_note': 'Resolved from Review Center',
      },
    );

    return resolveItem(
      reviewItemId: item.id,
      payload: {'price_anomaly_resolution': resolutionStatus},
    );
  }

  Future<ReviewItem> _setItemStatus({
    required String reviewItemId,
    required String action,
    Map<String, dynamic>? payload,
  }) async {
    final response = await _client.rpc<Map<String, dynamic>>(
      'resolve_review_item',
      params: {
        'p_review_item_id': reviewItemId,
        'p_action': action,
        'p_payload': payload ?? const <String, dynamic>{},
      },
    );
    return ReviewItem.fromJson(response);
  }
}
