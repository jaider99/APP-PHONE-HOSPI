import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/auth_service.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/data/models/sale.dart';

/// Provider for SalesRepository
final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  final authService = ref.watch(authServiceProvider);
  return SalesRepository(authService: authService);
});

/// Repository for sales data operations
/// Multi-tenant: All queries filtered by company_id via RLS
class SalesRepository {
  final AuthService _authService;
  final _supabase = SupabaseService.client;

  SalesRepository({required AuthService authService})
      : _authService = authService;

  String? get _companyId => _authService.currentCompanyId;

  /// Get sales for the current month
  Future<List<Sale>> getCurrentMonthSales() async {
    if (_companyId == null) return [];

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);

      final response = await _supabase
          .from('sales')
          .select()
          .eq('company_id', _companyId!)
          .gte('sale_date', startOfMonth.toIso8601String().split('T')[0])
          .lte('sale_date', endOfMonth.toIso8601String().split('T')[0])
          .order('sale_date', ascending: false);

      return (response as List)
          .map((json) => Sale.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch current month sales', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get sales for the previous month (for comparison)
  Future<List<Sale>> getPreviousMonthSales() async {
    if (_companyId == null) return [];

    try {
      final now = DateTime.now();
      final startOfPrevMonth = DateTime(now.year, now.month - 1, 1);
      final endOfPrevMonth = DateTime(now.year, now.month, 0);

      final response = await _supabase
          .from('sales')
          .select()
          .eq('company_id', _companyId!)
          .gte('sale_date', startOfPrevMonth.toIso8601String().split('T')[0])
          .lte('sale_date', endOfPrevMonth.toIso8601String().split('T')[0])
          .order('sale_date', ascending: false);

      return (response as List)
          .map((json) => Sale.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch previous month sales', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get sales summary with comparison
  Future<SaleSummary> getSalesSummary() async {
    final currentSales = await getCurrentMonthSales();
    final previousSales = await getPreviousMonthSales();

    final currentTotal = currentSales.fold<double>(
      0,
      (sum, sale) => sum + sale.totalAmount,
    );

    final previousTotal = previousSales.fold<double>(
      0,
      (sum, sale) => sum + sale.totalAmount,
    );

    double percentageChange = 0;
    if (previousTotal > 0) {
      percentageChange = ((currentTotal - previousTotal) / previousTotal) * 100;
    }

    // Build daily revenue for chart — last 30 days, spanning month boundary
    final dailyRevenue = <DailyRevenue>[];
    final now = DateTime.now();
    // Combine both months' sales for cross-month lookup
    final allSales = [...currentSales, ...previousSales];

    for (int i = 29; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day - i);
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final dayTotal = allSales
          .where((s) =>
              s.saleDate.isAfter(dayStart.subtract(const Duration(seconds: 1))) &&
              s.saleDate.isBefore(dayEnd))
          .fold<double>(0, (sum, s) => sum + s.totalAmount);

      dailyRevenue.add(DailyRevenue(date: dayStart, amount: dayTotal));
    }

    return SaleSummary(
      totalRevenue: currentTotal,
      previousPeriodRevenue: previousTotal,
      percentageChange: percentageChange,
      isPositive: percentageChange >= 0,
      dailyRevenue: dailyRevenue,
    );
  }

  /// Get recent sales (last N)
  Future<List<Sale>> getRecentSales({int limit = 10}) async {
    if (_companyId == null) return [];

    try {
      final response = await _supabase
          .from('sales')
          .select()
          .eq('company_id', _companyId!)
          .order('sale_date', ascending: false)
          .limit(limit);

      return (response as List)
          .map((json) => Sale.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch recent sales', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Create a new sale record
  Future<Sale?> createSale({
    required DateTime saleDate,
    required double totalAmount,
    double? cashAmount,
    double? cardAmount,
    double? otherAmount,
    String? notes,
  }) async {
    if (_companyId == null) return null;

    try {
      final response = await _supabase.from('sales').insert({
        'company_id': _companyId,
        'sale_date': saleDate.toIso8601String().split('T')[0],
        'total_amount': totalAmount,
        'cash_amount': cashAmount ?? 0,
        'card_amount': cardAmount ?? 0,
        'other_amount': otherAmount ?? 0,
        'notes': notes,
      }).select().single();

      return Sale.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create sale', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}
