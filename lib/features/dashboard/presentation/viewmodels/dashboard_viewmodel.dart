import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/auth_service.dart';
import 'package:hospi_dash/data/models/document.dart';
import 'package:hospi_dash/data/models/sale.dart';
import 'package:hospi_dash/data/repositories/activity_repository.dart';
import 'package:hospi_dash/data/repositories/documents_repository.dart';
import 'package:hospi_dash/data/repositories/providers_repository.dart';
import 'package:hospi_dash/data/repositories/sales_repository.dart';
import 'package:hospi_dash/features/dashboard/presentation/viewmodels/dashboard_state.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/services/dashboard_service.dart';
import 'package:intl/intl.dart';

/// Provider for DashboardViewModel
final dashboardViewModelProvider =
    StateNotifierProvider<DashboardViewModel, DashboardState>((ref) {
  return DashboardViewModel(
    salesRepository: ref.watch(salesRepositoryProvider),
    documentsRepository: ref.watch(documentsRepositoryProvider),
    providersRepository: ref.watch(providersRepositoryProvider),
    activityRepository: ref.watch(activityRepositoryProvider),
    authService: ref.watch(authServiceProvider),
    dashboardService: ref.watch(dashboardServiceProvider),
    companyIdFuture: ref.read(companyIdProvider.future),
  );
});

/// Dashboard ViewModel
/// Fetches and aggregates data from multiple repositories
class DashboardViewModel extends StateNotifier<DashboardState> {
  final SalesRepository _salesRepository;
  final DocumentsRepository _documentsRepository;
  final ProvidersRepository _providersRepository;
  final ActivityRepository _activityRepository;
  final AuthService _authService;
  final DashboardService _dashboardService;
  final Future<String?> _companyIdFuture;

  DashboardViewModel({
    required SalesRepository salesRepository,
    required DocumentsRepository documentsRepository,
    required ProvidersRepository providersRepository,
    required ActivityRepository activityRepository,
    required AuthService authService,
    required DashboardService dashboardService,
    required Future<String?> companyIdFuture,
  })  : _salesRepository = salesRepository,
        _documentsRepository = documentsRepository,
        _providersRepository = providersRepository,
        _activityRepository = activityRepository,
        _authService = authService,
        _dashboardService = dashboardService,
        _companyIdFuture = companyIdFuture,
        super(const DashboardState()) {
    // Auto-load on creation
    loadDashboard();
  }

  /// Load all dashboard data
  Future<void> loadDashboard() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Ensure company ID is loaded
      await _authService.getCurrentCompanyId();

      // Resolve company ID (Future captured at provider creation time — safe to
      // await without holding a Ref beyond provider scope).
      final companyId = await _companyIdFuture;

      // Get period label
      final now = DateTime.now();
      final periodLabel = DateFormat('MMMM yyyy').format(now);

      // Fetch all data in parallel.
      final results = await Future.wait([
        _salesRepository.getSalesSummary(),
        // Use DashboardService for expense data — correct schema, correct columns.
        companyId != null
            ? _dashboardService.fetchMetrics(companyId)
            : Future.value(DashboardMetrics.empty()),
        _providersRepository.getTopProvidersBySpending(limit: 5),
        _activityRepository.getRecentActivity(limit: 10),
        _getCompanyName(),
      ]);

      final metrics = results[1] as DashboardMetrics;

      // Build DocumentSummary from real metrics.
      final documentSummary = DocumentSummary(
        totalExpenses: metrics.totalExpenses,
        previousPeriodExpenses: metrics.previousPeriodExpenses,
        percentageChange: metrics.expensesPercentageChange,
        isPositive: metrics.expensesDecreasing,
        pendingCount: 0,
        overdueCount: 0,
      );

      // If there is no real sales revenue, use the expense daily series as the
      // chart data source. This keeps all state in ONE atomic copyWith call and
      // avoids writing to a separate StateProvider from an async context
      // (which can trigger markNeedsBuild during a build frame).
      var saleSummary = results[0] as SaleSummary;
      if (!saleSummary.dailyRevenue.any((d) => d.amount > 0) &&
          metrics.dailyExpenses.isNotEmpty) {
        saleSummary = SaleSummary(
          totalRevenue: saleSummary.totalRevenue,
          previousPeriodRevenue: saleSummary.previousPeriodRevenue,
          percentageChange: saleSummary.percentageChange,
          isPositive: saleSummary.isPositive,
          dailyRevenue: metrics.dailyExpenses,
        );
      }

      state = state.copyWith(
        isLoading: false,
        salesSummary: saleSummary,
        documentSummary: documentSummary,
        topProviders: results[2] as dynamic,
        recentActivity: results[3] as dynamic,
        companyName: results[4] as String?,
        periodLabel: periodLabel,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Refresh dashboard data (pull-to-refresh)
  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true);
    
    try {
      await loadDashboard();
    } finally {
      state = state.copyWith(isRefreshing: false);
    }
  }

  /// Get company name from user context
  Future<String?> _getCompanyName() async {
    final context = await _authService.getUserContext();
    return context?['company_name'] as String?;
  }
}
