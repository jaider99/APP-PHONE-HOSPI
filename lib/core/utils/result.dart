import 'package:freezed_annotation/freezed_annotation.dart';

part 'result.freezed.dart';

/// A Result type for handling success/failure states
/// Provides a clean API for error handling without exceptions
@freezed
class Result<T> with _$Result<T> {
  const Result._();

  const factory Result.success(T data) = _Success<T>;
  const factory Result.failure(Exception error) = _Failure<T>;

  /// Check if result is successful
  bool get isSuccess => this is _Success<T>;

  /// Check if result is failure
  bool get isFailure => this is _Failure<T>;

  /// Get the data or null if failure
  T? get dataOrNull => when(
        success: (data) => data,
        failure: (_) => null,
      );

  /// Get the error or null if success
  Exception? get errorOrNull => when(
        success: (_) => null,
        failure: (error) => error,
      );

  /// Map the result to another type
  Result<R> mapSuccess<R>(R Function(T data) mapper) {
    return when(
      success: (data) => Result.success(mapper(data)),
      failure: (error) => Result.failure(error),
    );
  }

  /// Execute a callback on success
  void onSuccess(void Function(T data) callback) {
    when(
      success: callback,
      failure: (_) {},
    );
  }

  /// Execute a callback on failure
  void onFailure(void Function(Exception error) callback) {
    when(
      success: (_) {},
      failure: callback,
    );
  }
}
