import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/services/auth_service.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/utils/app_logger.dart';
import 'package:hospi_dash/data/models/document.dart';

/// Provider for DocumentsRepository
final documentsRepositoryProvider = Provider<DocumentsRepository>((ref) {
  final authService = ref.watch(authServiceProvider);
  return DocumentsRepository(authService: authService);
});

/// Repository for document/invoice data operations
/// Multi-tenant: All queries filtered by company_id via RLS
class DocumentsRepository {
  final AuthService _authService;
  final _supabase = SupabaseService.client;

  DocumentsRepository({required AuthService authService})
      : _authService = authService;

  String? get _companyId => _authService.currentCompanyId;

  /// Get documents for the current month (expenses)
  Future<List<Document>> getCurrentMonthDocuments() async {
    if (_companyId == null) return [];

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);

      final response = await _supabase
          .from('documents')
          .select('*, provider:providers(id, name, category)')
          .eq('company_id', _companyId!)
          .gte('document_date', startOfMonth.toIso8601String().split('T')[0])
          .lte('document_date', endOfMonth.toIso8601String().split('T')[0])
          .eq('is_archived', false)
          .order('document_date', ascending: false);

      return (response as List)
          .map((json) => Document.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch current month documents', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get documents for the previous month (for comparison)
  Future<List<Document>> getPreviousMonthDocuments() async {
    if (_companyId == null) return [];

    try {
      final now = DateTime.now();
      final startOfPrevMonth = DateTime(now.year, now.month - 1);
      final endOfPrevMonth = DateTime(now.year, now.month, 0);

      final response = await _supabase
          .from('documents')
          .select('*, provider:providers(id, name, category)')
          .eq('company_id', _companyId!)
          .gte('document_date', startOfPrevMonth.toIso8601String().split('T')[0])
          .lte('document_date', endOfPrevMonth.toIso8601String().split('T')[0])
          .eq('is_archived', false)
          .order('document_date', ascending: false);

      return (response as List)
          .map((json) => Document.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch previous month documents', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get document summary with comparison
  Future<DocumentSummary> getDocumentSummary() async {
    final currentDocs = await getCurrentMonthDocuments();
    final previousDocs = await getPreviousMonthDocuments();

    final currentTotal = currentDocs.fold<double>(
      0,
      (sum, doc) => sum + doc.totalAmount,
    );

    final previousTotal = previousDocs.fold<double>(
      0,
      (sum, doc) => sum + doc.totalAmount,
    );

    double percentageChange = 0;
    if (previousTotal > 0) {
      percentageChange = ((currentTotal - previousTotal) / previousTotal) * 100;
    }

    final pendingCount = currentDocs
        .where((doc) => doc.paymentStatus == 'pending')
        .length;
    
    final overdueCount = currentDocs
        .where((doc) => doc.isOverdue)
        .length;

    return DocumentSummary(
      totalExpenses: currentTotal,
      previousPeriodExpenses: previousTotal,
      percentageChange: percentageChange,
      isPositive: percentageChange <= 0, // For expenses, less is better
      pendingCount: pendingCount,
      overdueCount: overdueCount,
    );
  }

  /// Get recent documents (last N)
  Future<List<Document>> getRecentDocuments({int limit = 10}) async {
    if (_companyId == null) return [];

    try {
      final response = await _supabase
          .from('documents')
          .select('*, provider:providers(id, name, category)')
          .eq('company_id', _companyId!)
          .eq('is_archived', false)
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((json) => Document.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch recent documents', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get pending documents
  Future<List<Document>> getPendingDocuments() async {
    if (_companyId == null) return [];

    try {
      final response = await _supabase
          .from('documents')
          .select('*, provider:providers(id, name, category)')
          .eq('company_id', _companyId!)
          .eq('payment_status', 'pending')
          .eq('is_archived', false)
          .order('due_date', ascending: true);

      return (response as List)
          .map((json) => Document.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch pending documents', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get overdue documents
  Future<List<Document>> getOverdueDocuments() async {
    if (_companyId == null) return [];

    try {
      final now = DateTime.now();
      final response = await _supabase
          .from('documents')
          .select('*, provider:providers(id, name, category)')
          .eq('company_id', _companyId!)
          .eq('payment_status', 'pending')
          .lt('due_date', now.toIso8601String().split('T')[0])
          .eq('is_archived', false)
          .order('due_date', ascending: true);

      return (response as List)
          .map((json) => Document.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch overdue documents', error: e, stackTrace: stackTrace);
      return [];
    }
  }
}
