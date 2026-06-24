import 'package:freezed_annotation/freezed_annotation.dart';

part 'sale.freezed.dart';
part 'sale.g.dart';

/// Sale domain model
/// Represents daily sales data for the company
@freezed
class Sale with _$Sale {
  const factory Sale({
    required String id,
    @JsonKey(name: 'company_id') required String companyId,
    @JsonKey(name: 'sale_date') required DateTime saleDate,
    @JsonKey(name: 'total_amount') required double totalAmount,
    @JsonKey(name: 'cash_amount') @Default(0) double cashAmount,
    @JsonKey(name: 'card_amount') @Default(0) double cardAmount,
    @JsonKey(name: 'other_amount') @Default(0) double otherAmount,
    String? notes,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Sale;

  factory Sale.fromJson(Map<String, dynamic> json) => _$SaleFromJson(json);
}

/// Sale summary for dashboard metrics
@freezed
class SaleSummary with _$SaleSummary {
  const factory SaleSummary({
    required double totalRevenue,
    required double previousPeriodRevenue,
    required double percentageChange,
    required bool isPositive,
    required List<DailyRevenue> dailyRevenue,
  }) = _SaleSummary;
  
  const SaleSummary._();
  
  factory SaleSummary.empty() => const SaleSummary(
    totalRevenue: 0,
    previousPeriodRevenue: 0,
    percentageChange: 0,
    isPositive: true,
    dailyRevenue: [],
  );
}

/// Daily revenue data point for charts
@freezed
class DailyRevenue with _$DailyRevenue {
  const factory DailyRevenue({
    required DateTime date,
    required double amount,
  }) = _DailyRevenue;

  factory DailyRevenue.fromJson(Map<String, dynamic> json) => 
      _$DailyRevenueFromJson(json);
}
