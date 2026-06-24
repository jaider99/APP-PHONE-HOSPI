import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/config/env_config.dart';
import 'package:hospi_dash/core/services/auth_service.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';

/// Provider for API service
final apiServiceProvider = Provider<ApiService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ApiService(authService: authService);
});

/// API service for making HTTP requests
/// Handles authentication headers and multi-tenant company_id
class ApiService {
  final AuthService _authService;
  late final Dio _dio;

  ApiService({required AuthService authService}) : _authService = authService {
    _dio = Dio(
      BaseOptions(
        baseUrl: EnvConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Add auth token
          final session = SupabaseService.currentSession;
          if (session != null) {
            options.headers['Authorization'] = 'Bearer ${session.accessToken}';
          }

          // Add company_id header for multi-tenant requests
          final companyId = _authService.currentCompanyId;
          if (companyId != null) {
            options.headers['X-Company-ID'] = companyId;
          }

          AppLogger.debug('API Request: ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          AppLogger.debug(
            'API Response: ${response.statusCode} ${response.requestOptions.uri}',
          );
          return handler.next(response);
        },
        onError: (error, handler) async {
          AppLogger.error(
            'API Error: ${error.message}',
            error: error,
            stackTrace: error.stackTrace,
          );

          // Handle token refresh on 401
          if (error.response?.statusCode == 401) {
            try {
              final result = await _authService.refreshSession();
              if (result.isSuccess) {
                // Retry the request with new token
                final retryResponse = await _retry(error.requestOptions);
                return handler.resolve(retryResponse);
              }
            } catch (_) {
              // Token refresh failed, sign out
              await _authService.signOut();
            }
          }

          return handler.next(error);
        },
      ),
    );

    // Add logging in debug mode
    if (EnvConfig.isDevelopment) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          logPrint: (o) => AppLogger.debug(o.toString()),
        ),
      );
    }
  }

  Future<Response<T>> _retry<T>(RequestOptions requestOptions) async {
    final session = SupabaseService.currentSession;
    final options = Options(
      method: requestOptions.method,
      headers: {
        ...requestOptions.headers,
        if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
      },
    );

    return _dio.request<T>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }

  /// GET request
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// POST request
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// PUT request
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// PATCH request
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// DELETE request
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// Upload file with multipart
  Future<Response<T>> uploadFile<T>(
    String path, {
    required String filePath,
    required String fieldName,
    Map<String, dynamic>? data,
    void Function(int, int)? onSendProgress,
  }) async {
    final formData = FormData.fromMap({
      fieldName: await MultipartFile.fromFile(filePath),
      ...?data,
    });

    return _dio.post<T>(
      path,
      data: formData,
      onSendProgress: onSendProgress,
    );
  }
}
