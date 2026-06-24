import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Extension methods for BuildContext
extension BuildContextExtensions on BuildContext {
  /// Get the current theme
  ThemeData get theme => Theme.of(this);

  /// Get the color scheme
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// Get the text theme
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// Get the screen size
  Size get screenSize => MediaQuery.sizeOf(this);

  /// Get the screen width
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Get the screen height
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// Check if device is mobile
  bool get isMobile => screenWidth < 600;

  /// Check if device is tablet
  bool get isTablet => screenWidth >= 600 && screenWidth < 840;

  /// Check if device is desktop
  bool get isDesktop => screenWidth >= 840;

  /// Get the safe area padding
  EdgeInsets get safeAreaPadding => MediaQuery.paddingOf(this);

  /// Show a snackbar
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colorScheme.error : null,
      ),
    );
  }

  /// Show a success snackbar
  void showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Show an error snackbar
  void showErrorSnackBar(String message) {
    showSnackBar(message, isError: true);
  }
}

/// Extension methods for DateTime
extension DateTimeExtensions on DateTime {
  /// Format as date string (e.g., "Jan 15, 2024")
  String get formattedDate => DateFormat.yMMMd().format(this);

  /// Format as time string (e.g., "2:30 PM")
  String get formattedTime => DateFormat.jm().format(this);

  /// Format as date and time (e.g., "Jan 15, 2024 2:30 PM")
  String get formattedDateTime => DateFormat.yMMMd().add_jm().format(this);

  /// Format as relative time (e.g., "2 hours ago")
  String get relativeTime {
    final now = DateTime.now();
    final difference = now.difference(this);

    if (difference.inDays > 30) {
      return formattedDate;
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  /// Check if date is today
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  /// Check if date is yesterday
  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year &&
        month == yesterday.month &&
        day == yesterday.day;
  }
}

/// Extension methods for num (numbers)
extension NumExtensions on num {
  /// Format as currency (e.g., "$1,234.56")
  String get asCurrency => NumberFormat.currency(symbol: '\$').format(this);

  /// Format as compact number (e.g., "1.2K")
  String get asCompact => NumberFormat.compact().format(this);

  /// Format as percentage (e.g., "12.5%")
  String get asPercentage => NumberFormat.percentPattern().format(this / 100);

  /// Format with decimal places
  String toDecimal(int places) => toStringAsFixed(places);
}

/// Extension methods for String
extension StringExtensions on String {
  /// Capitalize first letter
  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Capitalize each word
  String get titleCase {
    if (isEmpty) return this;
    return split(' ').map((word) => word.capitalize).join(' ');
  }

  /// Check if string is a valid email
  bool get isValidEmail {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(this);
  }

  /// Truncate string with ellipsis
  String truncate(int maxLength) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength)}...';
  }
}

/// Extension methods for List
extension ListExtensions<T> on List<T> {
  /// Get first element or null
  T? get firstOrNull => isEmpty ? null : first;

  /// Get last element or null
  T? get lastOrNull => isEmpty ? null : last;

  /// Get element at index or null
  T? getOrNull(int index) {
    if (index < 0 || index >= length) return null;
    return this[index];
  }
}
