import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/features/documents/data/models/upload_document_result.dart';
import 'package:hospi_dash/features/expenses/data/models/expense_model.dart';
import 'package:hospi_dash/features/expenses/data/services/expense_service.dart';
import 'package:hospi_dash/providers/company_provider.dart';
import 'package:hospi_dash/providers/documents_provider.dart';

// =============================================================================
// EXPENSE FORM ARGS — passed via GoRouter extra
// =============================================================================

/// Arguments for navigating to the expense form screen.
@immutable
class ExpenseFormArgs {
  final Uint8List fileBytes;
  final String companyId;
  final String fileName;
  final String mimeType;
  final List<Uint8List> initialPages;

  const ExpenseFormArgs({
    required this.fileBytes,
    required this.companyId,
    required this.fileName,
    required this.mimeType,
    this.initialPages = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'fileBytes': fileBytes,
      'companyId': companyId,
      'fileName': fileName,
      'mimeType': mimeType,
      'initialPages': initialPages,
    };
  }

  factory ExpenseFormArgs.fromMap(Map<String, dynamic> map) {
    return ExpenseFormArgs(
      fileBytes: map['fileBytes'] as Uint8List,
      companyId: map['companyId'] as String,
      fileName: map['fileName'] as String,
      mimeType: map['mimeType'] as String,
      initialPages: (map['initialPages'] as List<dynamic>? ?? const [])
          .whereType<Uint8List>()
          .toList(),
    );
  }
}

// =============================================================================
// EXPENSE FORM STATE
// =============================================================================

@immutable
class ExpenseFormState {
  final String? categoryId;
  final String? documentType;
  final String? paymentMethod;
  final String? purchaseOrderId;
  final String? incident;
  final bool isPaid;

  final List<Uint8List> pages;
  final bool moreOptionsExpanded;
  final bool isSubmitting;
  final String? submitError;
  final bool submitted;

  const ExpenseFormState({
    this.categoryId,
    this.documentType,
    this.paymentMethod,
    this.purchaseOrderId,
    this.incident,
    this.isPaid = false,
    this.pages = const [],
    this.moreOptionsExpanded = false,
    this.isSubmitting = false,
    this.submitError,
    this.submitted = false,
  });

  ExpenseFormState copyWith({
    String? categoryId,
    String? documentType,
    String? paymentMethod,
    String? purchaseOrderId,
    String? incident,
    bool? isPaid,
    List<Uint8List>? pages,
    bool? moreOptionsExpanded,
    bool? isSubmitting,
    String? submitError,
    bool? submitted,
    // Allow clearing nullable fields
    bool clearCategoryId = false,
    bool clearDocumentType = false,
    bool clearPaymentMethod = false,
    bool clearPurchaseOrderId = false,
    bool clearIncident = false,
    bool clearSubmitError = false,
  }) {
    return ExpenseFormState(
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      documentType:
          clearDocumentType ? null : (documentType ?? this.documentType),
      paymentMethod:
          clearPaymentMethod ? null : (paymentMethod ?? this.paymentMethod),
      purchaseOrderId: clearPurchaseOrderId
          ? null
          : (purchaseOrderId ?? this.purchaseOrderId),
      incident: clearIncident ? null : (incident ?? this.incident),
      isPaid: isPaid ?? this.isPaid,
      pages: pages ?? this.pages,
      moreOptionsExpanded: moreOptionsExpanded ?? this.moreOptionsExpanded,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitError:
          clearSubmitError ? null : (submitError ?? this.submitError),
      submitted: submitted ?? this.submitted,
    );
  }
}

// =============================================================================
// EXPENSE FORM NOTIFIER FAMILY — keyed by documentId
// =============================================================================

final expenseFormProvider = StateNotifierProvider.autoDispose
    .family<ExpenseFormNotifier, ExpenseFormState, ExpenseFormArgs>(
  (ref, args) => ExpenseFormNotifier(ref, args),
);

class ExpenseFormNotifier extends StateNotifier<ExpenseFormState> {
  final Ref _ref;
  final ExpenseFormArgs _args;

  ExpenseFormNotifier(this._ref, this._args)
      : super(ExpenseFormState(
          pages: _args.initialPages.isNotEmpty
              ? List<Uint8List>.from(_args.initialPages)
              : (_args.mimeType.startsWith('image/')
                  ? <Uint8List>[_args.fileBytes]
                  : const <Uint8List>[]),
        ));

  // ── FORM MUTATIONS ──────────────────────────────────────────────────────

  void setCategory(String? id) => state = state.copyWith(
        categoryId: id,
        clearCategoryId: id == null,
      );

  void setDocumentType(String? type) => state = state.copyWith(
        documentType: type,
        clearDocumentType: type == null,
      );

  void setPaymentMethod(String? method) => state = state.copyWith(
        paymentMethod: method,
        clearPaymentMethod: method == null,
      );

  void setPurchaseOrderId(String? id) => state = state.copyWith(
        purchaseOrderId: id,
        clearPurchaseOrderId: id == null,
      );

  void setIncident(String? incident) => state = state.copyWith(
        incident: incident,
        clearIncident: incident == null,
      );

  void setIsPaid(bool value) => state = state.copyWith(isPaid: value);

  void toggleMoreOptions() => state = state.copyWith(
        moreOptionsExpanded: !state.moreOptionsExpanded,
      );

  void removePage(int index) {
    if (index < 0 || index >= state.pages.length) return;
    final updated = List<Uint8List>.from(state.pages)..removeAt(index);
    state = state.copyWith(pages: updated);
  }

  void addPage(Uint8List bytes) {
    state = state.copyWith(pages: [...state.pages, bytes]);
  }

  // ── SUBMIT ──────────────────────────────────────────────────────────────

  Future<UploadDocumentResult> submit() async {
    if (state.isSubmitting) {
      return const UploadDocumentResult(
        success: false,
        error: 'Upload already in progress.',
      );
    }

    state = state.copyWith(isSubmitting: true, clearSubmitError: true);

    try {
      final uploadService = _ref.read(documentUploadServiceProvider);
      final result = await uploadService.submitExpenseFlow(
        companyId: _args.companyId,
        fileName: _args.fileName,
        fileBytes: _args.fileBytes,
        mimeType: _args.mimeType,
        pages: state.pages,
        categoryId: state.categoryId,
        documentType: state.documentType,
        paymentMethod: state.paymentMethod,
        purchaseOrderId: state.purchaseOrderId,
        incident: state.incident,
        isPaid: state.isPaid,
      );

      if (!result.success) {
        state = state.copyWith(
          isSubmitting: false,
          submitError: result.error ?? 'Failed to upload expense. Please try again.',
        );
        return result;
      }

      _ref.invalidate(documentsProvider);
      _ref.invalidate(documentCountsProvider);
      _ref.invalidate(expenseCategoriesProvider);

      state = state.copyWith(isSubmitting: false, submitted: true);
      return result;
    } catch (e) {
      debugPrint('ExpenseFormNotifier.submit error: $e');
      state = state.copyWith(
        isSubmitting: false,
        submitError: 'Failed to upload expense. Please try again.',
      );
      return const UploadDocumentResult(
        success: false,
        error: 'Failed to upload expense. Please try again.',
      );
    }
  }
}

// =============================================================================
// CATEGORIES PROVIDER
// =============================================================================

final expenseCategoriesProvider =
    FutureProvider.autoDispose<List<ExpenseCategory>>((ref) async {
  final companyId = await ref.watch(companyIdProvider.future);
  if (companyId == null) return [];

  final service = ref.read(expenseServiceProvider);
  return service.fetchCategories(companyId);
});
