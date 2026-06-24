import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/auth_service.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/data/models/activity.dart';

/// Provider for ActivityRepository
final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ActivityRepository(authService: authService);
});

/// Repository for combined activity feed
/// Merges sales and documents into a unified timeline
class ActivityRepository {
  final AuthService _authService;
  final _supabase = SupabaseService.client;

  ActivityRepository({required AuthService authService})
      : _authService = authService;

  String? get _companyId => _authService.currentCompanyId;

  /// Get recent activity combining sales and documents
  Future<List<Activity>> getRecentActivity({int limit = 10}) async {
    if (_companyId == null) return [];

    try {
      // Fetch recent sales
      final salesResponse = await _supabase
          .from('sales')
          .select()
          .eq('company_id', _companyId!)
          .order('sale_date', ascending: false)
          .limit(limit);

      // Fetch recent documents — use correct schema columns
      final docsResponse = await _supabase
          .from('documents')
          .select('*, provider:providers(id, name, category)')
          .eq('company_id', _companyId!)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(limit);

      // Convert to Activity items
      final activities = <Activity>[];

      for (final sale in (salesResponse as List)) {
        activities.add(Activity.fromSale(sale as Map<String, dynamic>));
      }

      for (final doc in (docsResponse as List)) {
        activities.add(Activity.fromDocument(doc as Map<String, dynamic>));
      }

      // Sort by timestamp descending and take limit
      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      return activities.take(limit).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch recent activity', error: e, stackTrace: stackTrace);
      return [];
    }
  }
}
