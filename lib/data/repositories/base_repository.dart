import 'package:hospi_dash/core/services/auth_service.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/core/utils/result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Base repository with common Supabase operations
/// Multi-tenant aware - automatically filters by company_id
abstract class BaseRepository {
  final AuthService _authService;
  final SupabaseClient _supabase = SupabaseService.client;

  BaseRepository({required AuthService authService})
      : _authService = authService;

  /// Get the current company_id for multi-tenant filtering
  String get companyId {
    final id = _authService.currentCompanyId;
    if (id == null) {
      throw StateError('No company_id available. User must be authenticated.');
    }
    return id;
  }

  /// Get the Supabase client
  SupabaseClient get supabase => _supabase;

  /// Execute a Supabase query with error handling
  Future<Result<T>> executeQuery<T>(
    Future<T> Function() query, {
    String? errorMessage,
  }) async {
    try {
      final result = await query();
      return Result.success(result);
    } on PostgrestException catch (e) {
      AppLogger.error(
        errorMessage ?? 'Database query failed',
        error: e,
      );
      return Result.failure(Exception(e.message));
    } catch (e, stackTrace) {
      AppLogger.error(
        errorMessage ?? 'Query failed',
        error: e,
        stackTrace: stackTrace,
      );
      return Result.failure(Exception(e.toString()));
    }
  }

  /// Insert a record with company_id
  Future<Result<Map<String, dynamic>>> insert({
    required String table,
    required Map<String, dynamic> data,
  }) async {
    return executeQuery(
      () async {
        final insertData = {
          ...data,
          'company_id': companyId,
          'created_at': DateTime.now().toIso8601String(),
        };

        final response =
            await _supabase.from(table).insert(insertData).select().single();

        return response;
      },
      errorMessage: 'Failed to insert into $table',
    );
  }

  /// Update a record
  Future<Result<Map<String, dynamic>>> update({
    required String table,
    required String id,
    required Map<String, dynamic> data,
  }) async {
    return executeQuery(
      () async {
        final updateData = {
          ...data,
          'updated_at': DateTime.now().toIso8601String(),
        };

        final response = await _supabase
            .from(table)
            .update(updateData)
            .eq('id', id)
            .eq('company_id', companyId) // Multi-tenant filter
            .select()
            .single();

        return response;
      },
      errorMessage: 'Failed to update $table',
    );
  }

  /// Delete a record
  Future<Result<void>> delete({
    required String table,
    required String id,
  }) async {
    return executeQuery(
      () async {
        await _supabase
            .from(table)
            .delete()
            .eq('id', id)
            .eq('company_id', companyId); // Multi-tenant filter
      },
      errorMessage: 'Failed to delete from $table',
    );
  }

  /// Get a single record by ID
  Future<Result<Map<String, dynamic>>> getById({
    required String table,
    required String id,
    String? select,
  }) async {
    return executeQuery(
      () async {
        final response = await _supabase
            .from(table)
            .select(select ?? '*')
            .eq('id', id)
            .eq('company_id', companyId) // Multi-tenant filter
            .single();

        return response;
      },
      errorMessage: 'Failed to get record from $table',
    );
  }

  /// Get all records with optional filters
  Future<Result<List<Map<String, dynamic>>>> getAll({
    required String table,
    String? select,
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
    int? offset,
  }) async {
    return executeQuery(
      () async {
        // Filter phase
        var filterBuilder = _supabase
            .from(table)
            .select(select ?? '*')
            .eq('company_id', companyId); // Multi-tenant filter

        // Apply additional filters
        if (filters != null) {
          filters.forEach((key, value) {
            filterBuilder = filterBuilder.eq(key, value);
          });
        }

        // Transform phase - use dynamic to handle type changes
        dynamic query = filterBuilder;

        // Apply ordering
        if (orderBy != null) {
          query = query.order(orderBy, ascending: ascending);
        }

        // Apply pagination
        if (limit != null) {
          query = query.limit(limit);
        }

        if (offset != null) {
          query = query.range(offset, offset + (limit ?? 10) - 1);
        }

        final response = await query;
        return List<Map<String, dynamic>>.from(response);
      },
      errorMessage: 'Failed to get records from $table',
    );
  }

  /// Stream records with realtime updates
  Stream<List<Map<String, dynamic>>> streamAll({
    required String table,
    String? select,
    Map<String, dynamic>? filters,
  }) {
    var query = _supabase
        .from(table)
        .stream(primaryKey: ['id']).eq('company_id', companyId);

    return query.map((data) => List<Map<String, dynamic>>.from(data));
  }
}
