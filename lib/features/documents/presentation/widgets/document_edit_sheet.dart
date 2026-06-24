import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/expenses/data/models/expense_model.dart';
import 'package:hospi_dash/features/expenses/presentation/providers/expense_form_provider.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:hospi_dash/providers/documents_provider.dart';
import 'package:intl/intl.dart';

/// Document edit bottom sheet
/// Allows manual editing of extracted document data
class DocumentEditSheet extends ConsumerStatefulWidget {
  final DocumentModel document;

  const DocumentEditSheet({
    super.key,
    required this.document,
  });

  /// Show the sheet
  static Future<void> show(BuildContext context, DocumentModel document) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DocumentEditSheet(document: document),
    );
  }

  @override
  ConsumerState<DocumentEditSheet> createState() => _DocumentEditSheetState();
}

class _DocumentEditSheetState extends ConsumerState<DocumentEditSheet> {
  late final TextEditingController _documentNumberController;
  late final TextEditingController _totalAmountController;
  late final TextEditingController _taxAmountController;
  late final TextEditingController _notesController;
  DateTime? _documentDate;
  String? _categoryId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _documentNumberController = TextEditingController(
      text: widget.document.documentNumber ?? '',
    );
    _totalAmountController = TextEditingController(
      text: widget.document.totalAmount?.toStringAsFixed(2) ?? '',
    );
    _taxAmountController = TextEditingController(
      text: widget.document.taxAmount?.toStringAsFixed(2) ?? '',
    );
    _notesController = TextEditingController(
      text: widget.document.notes ?? '',
    );
    _documentDate = widget.document.documentDate;
    _categoryId = widget.document.categoryId;
  }

  @override
  void dispose() {
    _documentNumberController.dispose();
    _totalAmountController.dispose();
    _taxAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              Text(
                'Edit Document',
                style: EditorialTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                widget.document.displayTitle,
                style: EditorialTypography.bodyMedium.copyWith(
                  color: AppColors.outline,
                ),
              ),

              const SizedBox(height: 32),

              // Document number
              _buildTextField(
                label: 'Document Number',
                controller: _documentNumberController,
                hint: 'e.g., INV-2024-001',
              ),

              const SizedBox(height: 20),

              // Document date
              _buildDateField(),

              const SizedBox(height: 20),

              // Total amount
              _buildCategoryField(categories),

              const SizedBox(height: 20),

              // Total amount
              _buildTextField(
                label: 'Total Amount',
                controller: _totalAmountController,
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                prefix: _getCurrencySymbol(widget.document.currency),
              ),

              const SizedBox(height: 20),

              // Tax amount
              _buildTextField(
                label: 'Tax Amount',
                controller: _taxAmountController,
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                prefix: _getCurrencySymbol(widget.document.currency),
              ),

              const SizedBox(height: 20),

              // Notes
              _buildTextField(
                label: 'Notes',
                controller: _notesController,
                hint: 'Add any notes...',
                maxLines: 3,
              ),

              const SizedBox(height: 32),

              // Actions
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Cancel',
                          textAlign: TextAlign.center,
                          style: EditorialTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Save button
                  Expanded(
                    child: GestureDetector(
                      onTap: _isSaving ? null : _save,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.onSurface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _isSaving
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.surfaceContainerLowest,
                                  ),
                                ),
                              )
                            : Text(
                                'Save Changes',
                                textAlign: TextAlign.center,
                                style: EditorialTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.surfaceContainerLowest,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    String? prefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: EditorialTypography.bodySmall.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            maxLines: maxLines,
            style: EditorialTypography.bodyMedium.copyWith(
              fontSize: 15,
              color: AppColors.onSurface,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: EditorialTypography.bodyMedium.copyWith(
                fontSize: 15,
                color: AppColors.outline,
              ),
              prefixText: prefix != null ? '$prefix ' : null,
              prefixStyle: EditorialTypography.bodyMedium.copyWith(
                fontSize: 15,
                color: AppColors.onSurface,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    final displayDate = _documentDate != null
        ? DateFormat('MMM d, yyyy').format(_documentDate!)
        : 'Select date';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Document Date',
          style: EditorialTypography.bodySmall.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _selectDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayDate,
                    style: EditorialTypography.bodyMedium.copyWith(
                      fontSize: 15,
                      color: _documentDate != null
                          ? AppColors.onSurface
                          : AppColors.outline,
                    ),
                  ),
                ),
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: AppColors.outline,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryField(AsyncValue<List<ExpenseCategory>> categories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category',
          style: EditorialTypography.bodySmall.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _categoryId,
              isExpanded: true,
              dropdownColor: AppColors.surfaceContainerLow,
              style: EditorialTypography.bodyMedium.copyWith(
                fontSize: 15,
                color: AppColors.onSurface,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No category'),
                ),
                ...categories.maybeWhen(
                  data: (items) => items
                      .map(
                        (category) => DropdownMenuItem<String?>(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      )
                      .toList(),
                  orElse: () => const <DropdownMenuItem<String?>>[],
                ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _documentDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.secondary,
              onPrimary: Colors.white,
              surface: AppColors.surfaceContainerLowest,
              onSurface: AppColors.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _documentDate = picked);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final uploadService = ref.read(documentUploadServiceProvider);

    // Parse amounts
    double? totalAmount;
    double? taxAmount;

    if (_totalAmountController.text.isNotEmpty) {
      totalAmount = double.tryParse(_totalAmountController.text);
    }
    if (_taxAmountController.text.isNotEmpty) {
      taxAmount = double.tryParse(_taxAmountController.text);
    }

    final success = await uploadService.updateDocument(
      documentId: widget.document.id,
      documentNumber: _documentNumberController.text.isNotEmpty
          ? _documentNumberController.text
          : null,
      documentDate: _documentDate,
      categoryId: _categoryId,
      totalAmount: totalAmount,
      taxAmount: taxAmount,
      notes: _notesController.text.isNotEmpty ? _notesController.text : null,
    );

    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.of(context).pop();
      Navigator.of(context).pop(); // Close detail sheet too

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document updated')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update document')),
        );
      }
    }
  }

  String _getCurrencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'EUR':
        return '€';
      case 'USD':
        return '\$';
      case 'GBP':
        return '£';
      default:
        return currency;
    }
  }
}
