import 'package:freezed_annotation/freezed_annotation.dart';

part 'provider.freezed.dart';
part 'provider.g.dart';

/// Provider domain model
/// Represents suppliers for the company
@freezed
class Provider with _$Provider {
  const factory Provider({
    required String id,
    @JsonKey(name: 'company_id') required String companyId,
    required String name,
    @JsonKey(name: 'name_normalized') String? nameNormalized,
    @JsonKey(name: 'tax_id') String? taxId,
    String? email,
    String? phone,
    String? address,
    String? category,
    String? website,
    String? notes,
    @JsonKey(name: 'payment_terms') @Default(30) int paymentTerms,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
    // Aggregated data
    @JsonKey(name: 'total_spent') double? totalSpent,
  }) = _Provider;

  const Provider._();

  factory Provider.fromJson(Map<String, dynamic> json) =>
      _$ProviderFromJson(json);

  /// Get initials for avatar
  String get initials {
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }
}

/// Provider with spending data for top providers list
@freezed
class ProviderSpending with _$ProviderSpending {
  const factory ProviderSpending({
    required String id,
    required String name,
    String? category,
    required double totalSpent,
  }) = _ProviderSpending;

  const ProviderSpending._();

  factory ProviderSpending.fromJson(Map<String, dynamic> json) =>
      _$ProviderSpendingFromJson(json);

  /// Get initials for avatar
  String get initials {
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }
}
