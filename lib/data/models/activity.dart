import 'package:freezed_annotation/freezed_annotation.dart';

part 'activity.freezed.dart';
part 'activity.g.dart';

/// Activity type enum
enum ActivityType {
  sale,
  document,
  order,
}

/// Activity item for the recent activity feed
/// Combines sales and documents into a unified feed
@freezed
class Activity with _$Activity {
  const factory Activity({
    required String id,
    required ActivityType type,
    required String title,
    required String subtitle,
    required double amount,
    required DateTime timestamp,
    required bool isPositive,
  }) = _Activity;

  const Activity._();

  factory Activity.fromJson(Map<String, dynamic> json) =>
      _$ActivityFromJson(json);

  /// Create from a sale record
  factory Activity.fromSale(Map<String, dynamic> json) {
    final saleDate = DateTime.parse(json['sale_date'] as String);
    final amount = (json['total_amount'] as num).toDouble();
    
    return Activity(
      id: json['id'] as String,
      type: ActivityType.sale,
      title: 'Daily Sales',
      subtitle: _formatDate(saleDate),
      amount: amount,
      timestamp: saleDate,
      isPositive: true,
    );
  }

  /// Create from a document record
  factory Activity.fromDocument(Map<String, dynamic> json) {
    final rawDocDate = json['document_date'];
    final rawCreatedAt = json['created_at'];

    // document_date can be null if extraction hasn't run yet — fall back to created_at
    final DateTime timestamp;
    if (rawDocDate != null) {
      timestamp = DateTime.parse(rawDocDate as String);
    } else if (rawCreatedAt != null) {
      timestamp = DateTime.parse(rawCreatedAt as String);
    } else {
      timestamp = DateTime.now();
    }

    final amount = rawDocDate != null || json['total_amount'] != null
        ? ((json['total_amount'] as num?)?.toDouble() ?? 0.0)
        : 0.0;

    final docType = json['document_type'] as String? ?? 'invoice';
    final provider = json['provider'] as Map<String, dynamic>?;
    final providerName = provider?['name'] as String? ?? 'Unknown';

    String title;
    switch (docType) {
      case 'invoice':
        title = 'Invoice';
        break;
      case 'receipt':
        title = 'Receipt';
        break;
      case 'delivery_note':
        title = 'Delivery';
        break;
      default:
        title = 'Document';
    }
    
    return Activity(
      id: json['id'] as String,
      type: ActivityType.document,
      title: title,
      subtitle: '$providerName · ${_formatDate(timestamp)}',
      amount: amount,
      timestamp: timestamp,
      isPositive: false,
    );
  }
  
  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'Today, ${_formatTime(date)}';
    } else if (diff.inDays == 1) {
      return 'Yesterday, ${_formatTime(date)}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
  
  static String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
