import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hospi_dash/data/models/activity.dart';
import 'package:hospi_dash/data/models/document.dart';
import 'package:hospi_dash/data/models/provider.dart';
import 'package:hospi_dash/data/models/sale.dart';

part 'dashboard_state.freezed.dart';

/// Dashboard UI state
@freezed
class DashboardState with _$DashboardState {
  const factory DashboardState({
    @Default(false) bool isLoading,
    @Default(false) bool isRefreshing,
    String? error,
    
    // Sales data
    @Default(null) SaleSummary? salesSummary,
    
    // Documents/Expenses data
    @Default(null) DocumentSummary? documentSummary,
    
    // Top providers
    @Default([]) List<ProviderSpending> topProviders,
    
    // Recent activity
    @Default([]) List<Activity> recentActivity,
    
    // Company info
    String? companyName,
    
    // Current period label
    @Default('') String periodLabel,
  }) = _DashboardState;

  const DashboardState._();
  
  /// Net profit = revenue - expenses
  double get netProfit {
    final revenue = salesSummary?.totalRevenue ?? 0;
    final expenses = documentSummary?.totalExpenses ?? 0;
    return revenue - expenses;
  }
  
  /// Net profit margin percentage
  double get netProfitMargin {
    final revenue = salesSummary?.totalRevenue ?? 0;
    if (revenue == 0) return 0;
    return (netProfit / revenue) * 100;
  }
  
  /// Whether we have any data loaded
  bool get hasData => salesSummary != null || documentSummary != null;
}
