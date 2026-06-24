import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/services/storage_service.dart';

import '../models/pos_connection.dart';
import '../models/pos_connection_result.dart';
import '../models/sale.dart';
import '../models/sales_import.dart';
import '../models/sales_item.dart';
import '../models/sales_summary.dart';

class SalesDeleteException implements Exception {
  const SalesDeleteException(this.message, {required this.stage});

  final String message;
  final String stage;

  @override
  String toString() => message;
}

class SalesRepository {
  SalesRepository({
    required SupabaseClient supabase,
    required StorageService storageService,
  })  : _supabase = supabase,
        _storageService = storageService;

  final SupabaseClient _supabase;
  final StorageService _storageService;
  final Uuid _uuid = const Uuid();

  Future<SalesSummary> fetchSummary({
    required String companyId,
    required SalesPeriodRange range,
  }) async {
    final response = await _supabase.rpc(
      'get_sales_summary',
      params: {
        'p_company_id': companyId,
        'p_period_start': range.startDate,
        'p_period_end': range.endDate,
      },
    );

    if (response is List && response.isNotEmpty) {
      return SalesSummary.fromRpc(response.first as Map<String, dynamic>);
    }
    if (response is Map<String, dynamic>) {
      return SalesSummary.fromRpc(response);
    }
    return SalesSummary.empty();
  }

  Future<List<SalesImport>> fetchImports(String companyId) async {
    final response = await _supabase
        .from('sales_imports')
        .select(
          'id, company_id, source_type, source_name, file_path, status, '
          'imported_at, period_start, period_end, total_gross, total_net, '
          'total_tax, currency, notes, created_at',
        )
        .eq('company_id', companyId)
        .order('created_at', ascending: false)
        .limit(12);

    return (response as List<dynamic>)
        .map((row) => SalesImport.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<Sale>> fetchImportedSales({
    required String companyId,
    required String salesImportId,
  }) async {
    final response = await _supabase
        .from('sales')
        .select(
          'id, company_id, sales_import_id, sale_date, sale_datetime, '
          'gross_amount, net_amount, tax_amount, discount_amount, tip_amount, '
          'currency, payment_method, channel, pos_transaction_id, '
          'source_type, transaction_count, metadata',
        )
        .eq('company_id', companyId)
        .eq('sales_import_id', salesImportId)
        .order('sale_date', ascending: false);

    return (response as List<dynamic>)
        .map((row) => Sale.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<PosConnection>> fetchPosConnections(String companyId) async {
    final response = await _supabase
        .from('pos_connection_status')
        .select(
          'id, company_id, provider, provider_key, provider_name, '
          'country_code, status, connection_type, credentials_status, '
          'external_account_id, last_sync_at, sync_status, created_at',
        )
        .eq('company_id', companyId)
        .order('created_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => PosConnection.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<SalesItem>> fetchTopItems({
    required String companyId,
    required SalesPeriodRange range,
    int limit = 8,
  }) async {
    final response = await _supabase
        .from('sales_items')
        .select(
          'id, company_id, sale_id, sales_import_id, product_name, '
          'normalized_product_name, quantity, unit_price, total_amount, '
          'category, pos_product_id, product_id, sales!inner(sale_date)',
        )
        .eq('company_id', companyId)
        .gte('sales.sale_date', range.startDate)
        .lte('sales.sale_date', range.endDate)
        .order('total_amount', ascending: false)
        .limit(limit);

    return (response as List<dynamic>)
        .map((row) => SalesItem.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<SalesImport> createSalesReportImport({
    required String companyId,
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
    String? sourceName,
    String? providerKey,
    String? providerName,
    String? countryCode,
    void Function(double progress)? onProgress,
  }) async {
    final importId = _uuid.v4();
    onProgress?.call(0.05);

    final uploadResult = await _storageService.uploadSalesImport(
      companyId: companyId,
      importId: importId,
      fileName: fileName,
      fileBytes: fileBytes,
      mimeType: mimeType,
      onProgress: (progress) => onProgress?.call(0.05 + progress * 0.45),
    );

    if (uploadResult is StorageUploadFailure) {
      throw StateError(uploadResult.message);
    }
    final upload = uploadResult as StorageUploadSuccess;
    onProgress?.call(0.55);

    final userId = SupabaseService.currentUser?.id;
    final metadata = <String, dynamic>{
      if (providerKey != null) 'provider_key': providerKey,
      if (providerName != null) 'provider_name': providerName,
      if (countryCode != null) 'country_code': countryCode,
      if (providerKey != null) 'launched_from': 'connect_pos_screen',
    };

    final inserted = await _supabase
        .from('sales_imports')
        .insert({
          'id': importId,
          'company_id': companyId,
          'source_type': 'vlm_import',
          'source_name': sourceName ?? _sourceNameForMime(mimeType),
          if (providerKey != null) 'provider_key': providerKey,
          if (metadata.isNotEmpty) 'metadata': metadata,
          'file_path': upload.path,
          'status': 'processing',
          'created_by': userId,
        })
        .select(
          'id, company_id, source_type, source_name, file_path, status, '
          'imported_at, period_start, period_end, total_gross, total_net, '
          'total_tax, currency, notes, created_at',
        )
        .single();

    onProgress?.call(0.7);
    unawaited(_invokeSalesImport(importId, companyId));
    return SalesImport.fromJson(inserted);
  }

  Future<PosConnectionResult> requestPosConnection({
    required String countryCode,
    required String providerKey,
    String? connectionMode,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'connect-pos',
        body: {
          'country_code': countryCode,
          'provider': providerKey,
          if (connectionMode != null) 'connection_mode': connectionMode,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return PosConnectionResult.fromJson(data);
      }
      if (data is Map) {
        return PosConnectionResult.fromJson(Map<String, dynamic>.from(data));
      }
      throw const PosConnectionRequestException(
        'POS connection service returned an unexpected response.',
      );
    } on FunctionException catch (error, stackTrace) {
      AppLogger.warning(
        '[ConnectPOS] connect-pos failed status=${error.status}',
        error: error,
        stackTrace: stackTrace,
      );
      if (error.status == 404) {
        throw const PosConnectionServiceUnavailableException();
      }
      throw PosConnectionRequestException(_functionErrorMessage(error));
    }
  }

  Future<Sale> updateSale({
    required String companyId,
    required String saleId,
    required DateTime saleDate,
    required double grossAmount,
    required int transactionCount,
    double? netAmount,
    double? taxAmount,
    double? discountAmount,
    double? tipAmount,
    String? channel,
    String? paymentMethod,
    String? notes,
  }) async {
    final response = await _supabase.rpc(
      'update_sales_record',
      params: {
        'p_company_id': companyId,
        'p_sale_id': saleId,
        'p_sale_date': _date(saleDate),
        'p_gross_amount': grossAmount,
        'p_net_amount': netAmount,
        'p_tax_amount': taxAmount,
        'p_discount_amount': discountAmount,
        'p_tip_amount': tipAmount,
        'p_transaction_count': transactionCount,
        'p_channel': channel,
        'p_payment_method': paymentMethod,
        'p_notes': notes,
      },
    );

    final row = response is List && response.isNotEmpty
        ? response.first as Map<String, dynamic>
        : response as Map<String, dynamic>;
    return Sale.fromJson(row);
  }

  Future<void> deleteSale({
    required String companyId,
    required String saleId,
  }) async {
    AppLogger.info(
      '[SalesDelete] Deleting sale sale=${_redactId(saleId)} '
      'company=${_redactId(companyId)} stage=rpc_start',
    );
    try {
      await _supabase.rpc(
        'delete_sales_record',
        params: {
          'p_company_id': companyId,
          'p_sale_id': saleId,
        },
      );
      AppLogger.info(
        '[SalesDelete] Sale deleted sale=${_redactId(saleId)} '
        'company=${_redactId(companyId)} stage=rpc_complete',
      );
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.warning(
        '[SalesDelete] Sale delete failed code=${error.code} '
        'sale=${_redactId(saleId)} company=${_redactId(companyId)} '
        'stage=delete_sales_record',
        error: error,
        stackTrace: stackTrace,
      );
      throw SalesDeleteException(
        _salesDeleteMessage(error, target: _DeleteTarget.sale),
        stage: 'delete_sales_record',
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        '[SalesDelete] Sale delete failed sale=${_redactId(saleId)} '
        'company=${_redactId(companyId)} stage=delete_sales_record',
        error: error,
        stackTrace: stackTrace,
      );
      throw const SalesDeleteException(
        'Could not delete sale. Check your connection and try again.',
        stage: 'delete_sales_record',
      );
    }
  }

  Future<void> deleteSalesImport({
    required String companyId,
    required String salesImportId,
  }) async {
    AppLogger.info(
      '[SalesDelete] Deleting import import=${_redactId(salesImportId)} '
      'company=${_redactId(companyId)} stage=rpc_start',
    );
    try {
      await _supabase.rpc(
        'delete_sales_import',
        params: {
          'p_company_id': companyId,
          'p_sales_import_id': salesImportId,
        },
      );
      AppLogger.info(
        '[SalesDelete] Import deleted import=${_redactId(salesImportId)} '
        'company=${_redactId(companyId)} stage=rpc_complete',
      );
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.warning(
        '[SalesDelete] Import delete failed code=${error.code} '
        'import=${_redactId(salesImportId)} company=${_redactId(companyId)} '
        'stage=delete_sales_import',
        error: error,
        stackTrace: stackTrace,
      );
      throw SalesDeleteException(
        _salesDeleteMessage(error, target: _DeleteTarget.import),
        stage: 'delete_sales_import',
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        '[SalesDelete] Import delete failed import=${_redactId(salesImportId)} '
        'company=${_redactId(companyId)} stage=delete_sales_import',
        error: error,
        stackTrace: stackTrace,
      );
      throw const SalesDeleteException(
        'Could not delete sales import. Check your connection and try again.',
        stage: 'delete_sales_import',
      );
    }
  }

  Future<void> disconnectPosConnection(String connectionId) async {
    try {
      await _supabase.functions.invoke(
        'disconnect-pos',
        body: {'connection_id': connectionId},
      );
    } on FunctionException catch (error, stackTrace) {
      AppLogger.warning(
        '[ConnectPOS] disconnect-pos failed status=${error.status}',
        error: error,
        stackTrace: stackTrace,
      );
      throw PosConnectionRequestException(_functionErrorMessage(error));
    }
  }

  Future<void> deletePosConnection({
    required String companyId,
    required String connectionId,
  }) async {
    AppLogger.info(
      '[SalesDelete] Deleting POS connection connection=${_redactId(connectionId)} '
      'company=${_redactId(companyId)} stage=rpc_start',
    );
    try {
      await _supabase.rpc(
        'delete_pos_connection',
        params: {
          'p_company_id': companyId,
          'p_connection_id': connectionId,
        },
      );
      AppLogger.info(
        '[SalesDelete] POS connection deleted '
        'connection=${_redactId(connectionId)} company=${_redactId(companyId)} '
        'stage=rpc_complete',
      );
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.warning(
        '[SalesDelete] POS delete failed code=${error.code} '
        'connection=${_redactId(connectionId)} company=${_redactId(companyId)} '
        'stage=delete_pos_connection',
        error: error,
        stackTrace: stackTrace,
      );
      throw SalesDeleteException(
        _salesDeleteMessage(error, target: _DeleteTarget.posConnection),
        stage: 'delete_pos_connection',
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        '[SalesDelete] POS delete failed connection=${_redactId(connectionId)} '
        'company=${_redactId(companyId)} stage=delete_pos_connection',
        error: error,
        stackTrace: stackTrace,
      );
      throw const SalesDeleteException(
        'Could not delete POS connection. Check your connection and try again.',
        stage: 'delete_pos_connection',
      );
    }
  }

  Future<void> _invokeSalesImport(
    String salesImportId,
    String companyId,
  ) async {
    try {
      await _supabase.functions.invoke(
        'process-sales-import',
        body: {'sales_import_id': salesImportId},
      );
    } on FunctionException catch (error, stackTrace) {
      AppLogger.error(
        '[SalesImport] process-sales-import failed '
        'status=${error.status} details=${_functionDetails(error)}',
        error: error,
        stackTrace: stackTrace,
      );
      if (error.status == 404) {
        await _markSalesImportStartFailure(salesImportId, companyId);
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        '[SalesImport] process-sales-import invoke failed',
        error: error,
        stackTrace: stackTrace,
      );
      await _markSalesImportStartFailure(salesImportId, companyId);
    }
  }

  Future<void> _markSalesImportStartFailure(
    String salesImportId,
    String companyId,
  ) async {
    await _supabase
        .from('sales_imports')
        .update({
          'status': 'failed',
          'notes': 'Sales import processing could not be started.',
        })
        .eq('id', salesImportId)
        .eq('company_id', companyId);
  }

  String _sourceNameForMime(String mimeType) {
    if (mimeType == 'application/pdf') return 'PDF sales report';
    if (mimeType == 'text/csv') return 'CSV sales report';
    if (mimeType.startsWith('image/')) return 'Image sales report';
    return 'Sales report';
  }

  String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _functionErrorMessage(FunctionException error) {
    final details = error.details;
    if (details is Map && details['message'] is String) {
      return details['message'] as String;
    }
    return 'POS connection request could not be completed. Please try again.';
  }

  String _functionDetails(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final errorMessage = details['error'];
      final stage = details['stage'];
      return 'error=$errorMessage stage=$stage';
    }
    return details.toString();
  }

  String _redactId(String id) {
    if (id.length <= 8) return '***';
    return '${id.substring(0, 4)}...${id.substring(id.length - 4)}';
  }

  String _salesDeleteMessage(
    PostgrestException error, {
    required _DeleteTarget target,
  }) {
    final code = error.code;
    final message = error.message.toLowerCase();

    if (code == '42501' || message.contains('access denied')) {
      return switch (target) {
        _DeleteTarget.sale => 'You do not have permission to delete this sale.',
        _DeleteTarget.import =>
          'You do not have permission to delete this sales import.',
        _DeleteTarget.posConnection =>
          'You do not have permission to delete this POS connection.',
      };
    }

    if (code == 'P0002' || message.contains('not found')) {
      return switch (target) {
        _DeleteTarget.sale => 'This sale is no longer available.',
        _DeleteTarget.import => 'This sales import is no longer available.',
        _DeleteTarget.posConnection =>
          'This POS connection is no longer available.',
      };
    }

    if (code == '23503' || message.contains('foreign key')) {
      return switch (target) {
        _DeleteTarget.sale =>
          'This sale has linked records. Try deleting the full import.',
        _DeleteTarget.import =>
          'This sales import has linked records and could not be deleted.',
        _DeleteTarget.posConnection =>
          'This POS connection has linked records and could not be deleted.',
      };
    }

    return switch (target) {
      _DeleteTarget.sale =>
        'Could not delete sale. Check your connection and try again.',
      _DeleteTarget.import =>
        'Could not delete sales import. Check your connection and try again.',
      _DeleteTarget.posConnection =>
        'Could not delete POS connection. Check your connection and try again.',
    };
  }
}

enum _DeleteTarget { sale, import, posConnection }
