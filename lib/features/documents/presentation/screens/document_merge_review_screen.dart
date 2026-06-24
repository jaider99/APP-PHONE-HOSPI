import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/features/documents/data/services/duplicate_merge_service.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:hospi_dash/providers/documents_provider.dart';
import 'package:hospi_dash/shared/ui/ui.dart';
import 'package:hospi_dash/shared/widgets/app_back_button.dart';
import 'package:intl/intl.dart';

class DocumentMergeReviewScreen extends ConsumerWidget {
  const DocumentMergeReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(documentMergeReviewQueueProvider);

    return AppScaffold(
      backgroundColor: AppColors.background,
      clampContent: false,
      topBar: const AppTopBar(
        eyebrow: 'documents',
        title: 'Duplicate review queue',
        leading: AppBackButton(fallbackRoute: AppRoutes.documents),
      ),
      body: reviewAsync.when(
        data: (documents) {
          if (documents.isEmpty) {
            return const Center(
              child: Text('No documents need duplicate review.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            itemCount: documents.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final source = documents[index];
              return _ReviewCard(source: source);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load review queue: $error')),
      ),
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({required this.source});

  final DocumentModel source;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final targetId = widget.source.mergedIntoId;
    final targetAsync = targetId == null
        ? const AsyncValue<DocumentModel?>.data(null)
        : ref.watch(documentDetailProvider(targetId));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${(widget.source.mergeConfidence * 100).round()}% confidence',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _mergeReason(widget.source),
                  style: const TextStyle(
                    color: AppColors.outline,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            AppSpacing.verticalMd,
            targetAsync.when(
              data: (target) => Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _DocumentPreviewPane(label: 'Incoming', document: widget.source)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DocumentPreviewPane(
                          label: 'Candidate',
                          document: target,
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.verticalMd,
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSubmitting ? null : () => _keepSeparate(context),
                          child: Text(_isSubmitting ? 'Working...' : 'Keep separate'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _isSubmitting || target == null ? null : () => _merge(context, target),
                          child: const Text('Merge'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text('Failed to load candidate document: $error'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _merge(BuildContext context, DocumentModel target) async {
    await _runAction(context, () async {
      final service = ref.read(duplicateMergeServiceProvider);
      await service.mergeDocuments(
        companyId: widget.source.companyId,
        sourceDocumentId: widget.source.id,
        targetDocumentId: target.id,
        confidence: widget.source.mergeConfidence,
        method: 'manual',
        reason: _mergeReason(widget.source),
      );
      }, 'Documents merged',);
  }

  Future<void> _keepSeparate(BuildContext context) async {
    await _runAction(context, () async {
      final service = ref.read(duplicateMergeServiceProvider);
      await service.keepSeparate(
        companyId: widget.source.companyId,
        documentId: widget.source.id,
      );
      }, 'Marked as separate',);
  }

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action,
    String successMessage,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSubmitting = true);
    try {
      await action();
      ref.invalidate(documentMergeReviewQueueProvider);
      ref.invalidate(documentMergeReviewCountProvider);
      ref.invalidate(documentsProvider);
      ref.invalidate(documentCountsProvider);
      ref.invalidate(documentDetailProvider(widget.source.id));
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Action failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _mergeReason(DocumentModel document) {
    final raw = document.extractionRaw?['merge_evaluation'];
    if (raw is Map<String, dynamic>) {
      final reason = raw['reason'] as String?;
      if (reason != null && reason.isNotEmpty) return reason;
    }
    return 'Manual review after merge scoring';
  }
}

class _DocumentPreviewPane extends StatelessWidget {
  const _DocumentPreviewPane({required this.label, required this.document});

  final String label;
  final DocumentModel? document;

  @override
  Widget build(BuildContext context) {
    if (document == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text('No candidate document linked.'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.outline,
            ),
          ),
          AppSpacing.verticalSm,
          Text(
            document!.displayTitle,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _MetadataRow(label: 'Invoice', value: document!.documentNumber ?? 'Unknown'),
          _MetadataRow(label: 'Date', value: document!.documentDate == null ? 'Unknown' : DateFormat('dd MMM yyyy').format(document!.documentDate!)),
          _MetadataRow(label: 'Amount', value: document!.totalAmount == null ? 'Unknown' : '${document!.currency} ${document!.totalAmount!.toStringAsFixed(2)}'),
          _MetadataRow(label: 'Type', value: document!.documentType.displayName),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}