import 'package:flutter/widgets.dart';

/// Extension on [State] providing safe post-await helpers.
///
/// Every `setState()` that follows an `await` must be preceded by
/// `if (!mounted) return;` — this extension reduces boilerplate.
extension MountedGuard on State {
  /// Calls [setState] only if the widget is still mounted.
  // ignore: invalid_use_of_protected_member — intentional: this extension
  // is designed exclusively for State subclasses where setState is valid.
  // ignore: invalid_use_of_protected_member
  void setStateIfMounted(VoidCallback action) {
    // ignore: invalid_use_of_protected_member
    if (mounted) setState(action);
  }

  /// Awaits [future] and returns its result only if still mounted.
  ///
  /// Throws [_DisposedException] if the widget was disposed while
  /// the future was in-flight, so callers can bail out cleanly:
  ///
  /// ```dart
  /// try {
  ///   final result = await awaitMounted(someAsyncCall());
  ///   context.go('/dashboard');
  /// } on DisposedException {
  ///   return; // widget gone, do nothing
  /// }
  /// ```
  Future<T> awaitMounted<T>(
    Future<T> future, {
    VoidCallback? onDisposed,
  }) async {
    final result = await future;
    if (!mounted) {
      onDisposed?.call();
      throw const DisposedException();
    }
    return result;
  }
}

/// Thrown by [MountedGuard.awaitMounted] when the widget is disposed
/// before the awaited future completes.
class DisposedException implements Exception {
  const DisposedException();

  @override
  String toString() => 'DisposedException: widget was disposed during await';
}
