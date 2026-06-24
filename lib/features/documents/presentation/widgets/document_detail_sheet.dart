import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';
import 'package:hospi_dash/core/theme/app_motion.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/documents/data/services/document_delete_service.dart';
import 'package:hospi_dash/features/documents/data/services/document_management_service.dart';
import 'package:hospi_dash/features/documents/presentation/widgets/document_edit_sheet.dart';
import 'package:hospi_dash/features/documents/presentation/widgets/extracted_products_card.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:hospi_dash/providers/documents_provider.dart';
import 'package:hospi_dash/services/step_up_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdfx/pdfx.dart';

const double _deleteConfirmFloatingNavClearance = 104;
const double _deleteConfirmMaxWidth = 520;
const double _deleteConfirmHorizontalPadding = 16;
const double _deleteConfirmBottomGap = 12;
const double _deleteConfirmStackedActionsWidth = 360;

/// Bottom sheet showing full document details with line items
class DocumentDetailSheet extends ConsumerStatefulWidget {
  final String documentId;

  const DocumentDetailSheet({super.key, required this.documentId});

  static Future<void> show(BuildContext context, String documentId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DocumentDetailSheet(documentId: documentId),
    );
  }

  @override
  ConsumerState<DocumentDetailSheet> createState() =>
      _DocumentDetailSheetState();
}

class _DocumentDetailSheetState extends ConsumerState<DocumentDetailSheet> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(documentDetailProvider(widget.documentId));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 1.0,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: detailAsync.when(
                  data: (doc) {
                    if (doc == null) {
                      return const Center(child: Text('Document not found'));
                    }
                    return _DetailContent(
                      document: doc,
                      isDeleting: _isDeleting,
                      scrollController: scrollController,
                      onEdit: () {
                        DocumentEditSheet.show(context, doc);
                      },
                      onReExtract: () async {
                        final service = ref.read(
                          documentManagementServiceProvider,
                        );
                        await service.reExtractDocument(widget.documentId);
                        if (context.mounted) Navigator.pop(context);
                      },
                      onDelete: _isDeleting ? null : () => _deleteDocument(doc),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text('Error loading document: $e')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteDocument(DocumentModel document) async {
    debugPrint('[DELETE] Delete tapped documentId=${document.id}');
    debugPrint('[DELETE] Showing confirmation');
    final confirmed = await _confirmDelete(context);
    debugPrint('[DELETE] User confirmed: $confirmed');
    if (!confirmed || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      debugPrint('[DELETE] Requires local auth: true');
      final deleteService = DocumentDeleteService(
        SupabaseService.client,
        stepUpAuthService: ref.read(stepUpAuthServiceProvider),
      );
      await deleteService.deleteDocument(
        documentId: document.id,
        companyId: document.companyId,
        filePath: document.filePath ?? '',
      );

      ref.read(documentsProvider.notifier).removeDocument(document.id);
      ref.invalidate(documentCountsProvider);
      ref.invalidate(documentDetailProvider(document.id));

      if (!mounted) return;
      debugPrint('[DELETE] Navigating back after delete');
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Document deleted')));
    } on DocumentDeleteException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          action: e.retryable
              ? SnackBarAction(
                  label: 'Retry',
                  onPressed: () => _deleteDocument(document),
                )
              : null,
        ),
      );
    } on StepUpAuthException catch (e) {
      if (!mounted) return;
      debugPrint('[DELETE] Local auth result: ${e.result.name}');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.28),
          builder: (sheetContext) {
            final media = MediaQuery.of(sheetContext);
            // The shell renders the floating bottom nav as a Stack overlay, so
            // route-local sheets must reserve its footprint in addition to the
            // device safe area or the card actions sit underneath the nav pill.
            final bottomPadding = math.max(
                  media.viewInsets.bottom,
                  media.padding.bottom + _deleteConfirmFloatingNavClearance,
                ) +
                _deleteConfirmBottomGap;
            final disableAnimations = media.disableAnimations;

            final card = Container(
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: EditorialColors.hairline),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    blurRadius: 30,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: EditorialColors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Delete document?',
                      style: EditorialTypography.titleLarge.copyWith(
                        color: EditorialColors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This will remove the document and its extracted data. This action cannot be undone.',
                      style: EditorialTypography.bodyMedium.copyWith(
                        color: EditorialColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'You may be asked to confirm this action.',
                      style: EditorialTypography.bodySmall.copyWith(
                        color: EditorialColors.outline,
                      ),
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cancelButton = OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: EditorialColors.onSurface,
                            side: const BorderSide(
                              color: EditorialColors.hairline,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 13,
                            ),
                          ),
                          child: const Text('Cancel'),
                        );
                        final deleteButton = OutlinedButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          label: const Text('Delete document'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.45),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 13,
                            ),
                          ),
                        );

                        if (constraints.maxWidth <
                            _deleteConfirmStackedActionsWidth) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cancelButton,
                              const SizedBox(height: 10),
                              deleteButton,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: cancelButton),
                            const SizedBox(width: 12),
                            Expanded(child: deleteButton),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );

            return SafeArea(
              top: false,
              child: AnimatedPadding(
                duration: disableAnimations ? Duration.zero : AppMotion.fast,
                curve: AppMotion.enter,
                padding: EdgeInsets.fromLTRB(
                  _deleteConfirmHorizontalPadding,
                  0,
                  _deleteConfirmHorizontalPadding,
                  bottomPadding,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _deleteConfirmMaxWidth,
                    ),
                    child: SingleChildScrollView(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: disableAnimations ? 1 : 0,
                          end: 1,
                        ),
                        duration: disableAnimations
                            ? Duration.zero
                            : AppMotion.emphasised,
                        curve: AppMotion.enter,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, (1 - value) * 16),
                              child: child,
                            ),
                          );
                        },
                        child: card,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ) ??
        false;
  }
}

class _DetailContent extends StatelessWidget {
  final DocumentModel document;
  final bool isDeleting;
  final ScrollController scrollController;
  final VoidCallback onEdit;
  final VoidCallback onReExtract;
  final VoidCallback? onDelete;

  const _DetailContent({
    required this.document,
    required this.isDeleting,
    required this.scrollController,
    required this.onEdit,
    required this.onReExtract,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        // Keep action buttons above the floating nav pill.
        // Nav pill occupies ~76px + 16px gap = 92px from bottom.
        92 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        // Header row
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.displayTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _StatusBadge(status: document.status),
                ],
              ),
            ),
            if (document.totalAmount != null)
              Text(
                _formatAmount(document.totalAmount!, document.currency),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
          ],
        ),

        AppSpacing.verticalXl,

        _PreviewSection(document: document),

        AppSpacing.verticalLg,

        if (document.isDuplicate) ...[
          _DuplicateNotice(document: document),
          AppSpacing.verticalLg,
        ],

        // Metadata fields
        _MetadataSection(document: document),

        AppSpacing.verticalLg,

        // Line items
        ExtractedProductsCard(
          items: document.lineItems,
          currencyCode: document.currency,
          onEdit: onEdit,
          onRetry: onReExtract,
          isProcessing: document.status == DocumentStatus.processing,
          hasExtractionError: document.status == DocumentStatus.failed,
        ),

        AppSpacing.verticalXl,

        // Actions
        Row(
          children: [
            Expanded(
              child: _FinanceActionButton(
                key: const Key('document_edit_action'),
                label: 'Edit',
                icon: Icons.edit_outlined,
                onPressed: onEdit,
                isPrimary: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FinanceActionButton(
                key: const Key('document_delete_action'),
                label: isDeleting ? 'Deleting...' : 'Delete',
                icon: Icons.delete_outline_rounded,
                showSpinner: isDeleting,
                onPressed: isDeleting ? null : onDelete,
              ),
            ),
          ],
        ),
        if (document.status == DocumentStatus.flagged ||
            document.status == DocumentStatus.failed) ...[
          AppSpacing.verticalSm,
          _FinanceActionButton(
            key: const Key('document_reextract_action'),
            label: 'Re-extract',
            icon: Icons.refresh_rounded,
            onPressed: onReExtract,
            foregroundColor: AppColors.info,
            backgroundColor: EditorialColors.surfaceContainerLow,
          ),
        ],

        AppSpacing.verticalXxl,
      ],
    );
  }

  String _formatAmount(double amount, String currency) {
    final formatter = NumberFormat.currency(
      symbol: _currencySymbol(currency),
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  String _currencySymbol(String code) {
    return switch (code.toUpperCase()) {
      'EUR' => '€',
      'USD' => '\$',
      'GBP' => '£',
      _ => code,
    };
  }
}

class _FinanceActionButton extends StatefulWidget {
  const _FinanceActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isPrimary = false,
    this.showSpinner = false,
    this.foregroundColor,
    this.backgroundColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool showSpinner;
  final Color? foregroundColor;
  final Color? backgroundColor;

  @override
  State<_FinanceActionButton> createState() => _FinanceActionButtonState();
}

class _FinanceActionButtonState extends State<_FinanceActionButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.foregroundColor ??
        (widget.isPrimary ? EditorialColors.onPrimary : AppColors.error);
    final background = widget.backgroundColor ??
        (widget.isPrimary ? EditorialColors.primary : const Color(0xFFF1F1F1));
    final shadowOpacity = widget.isPrimary ? 0.20 : 0.12;

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: widget.onPressed == null ? 0.56 : 1,
            duration: const Duration(milliseconds: 120),
            child: Container(
              constraints: const BoxConstraints(minHeight: 54),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(shadowOpacity),
                    blurRadius: widget.isPrimary ? 24 : 20,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(
                      widget.isPrimary ? 0.02 : 0.62,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showSpinner)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    )
                  else
                    Icon(widget.icon, color: foreground, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewSection extends ConsumerWidget {
  final DocumentModel document;

  const _PreviewSection({required this.document});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (document.isPdf) {
      final filePath = document.filePath;
      if (filePath == null || filePath.isEmpty) {
        // If we already have a signed fileUrl in the model, use its bytes directly
        if (document.fileUrl.isNotEmpty) {
          return _PdfPreviewCard(document: document, filePath: filePath ?? '');
        }
        return const _PreviewPlaceholder(
          icon: Icons.picture_as_pdf_rounded,
          label: 'Preview unavailable',
        );
      }
      return _PdfPreviewCard(document: document, filePath: filePath);
    }

    final filePath = document.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      final previewAsync = ref.watch(documentPreviewUrlProvider(filePath));
      return previewAsync.when(
        loading: () => const _PreviewLoading(),
        error: (_, __) => const _PreviewPlaceholder(
          icon: Icons.broken_image_rounded,
          label: 'Failed to load document',
        ),
        data: (url) => url != null && url.isNotEmpty
            ? _ImagePreview(url: url)
            : const _PreviewPlaceholder(
                icon: Icons.broken_image_rounded,
                label: 'Failed to load document',
              ),
      );
    }

    final directUrl = document.fileUrl;
    if (directUrl.isNotEmpty && directUrl.contains('token=')) {
      return _ImagePreview(url: directUrl);
    }

    if (filePath == null || filePath.isEmpty) {
      return const _PreviewPlaceholder(
        icon: Icons.broken_image_rounded,
        label: 'Preview unavailable',
      );
    }

    return const _PreviewPlaceholder(
      icon: Icons.broken_image_rounded,
      label: 'Preview unavailable',
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final String url;
  const _ImagePreview({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: url,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 100),
        memCacheWidth: 800,
        placeholder: (_, __) => Container(
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        errorWidget: (_, __, ___) => const _PreviewPlaceholder(
          icon: Icons.broken_image_rounded,
          label: 'Preview unavailable',
        ),
      ),
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PreviewPlaceholder({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.primary.withOpacity(0.45)),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PDF PREVIEW CARD + FULLSCREEN VIEWER
// =============================================================================

/// Tappable card that pre-loads PDF bytes and opens a fullscreen viewer on tap.
/// Prefers signing from filePath and only falls back to an existing signed fileUrl.
class _PdfPreviewCard extends ConsumerWidget {
  final DocumentModel document;
  final String filePath;

  const _PdfPreviewCard({required this.document, required this.filePath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDirect =
      filePath.isEmpty &&
      document.fileUrl.isNotEmpty &&
      document.fileUrl.contains('token=');
    final pdfBytesAsync = hasDirect || filePath.isEmpty
        ? null
        : ref.watch(documentPdfBytesProvider(filePath));
    final isLoading = !hasDirect && (pdfBytesAsync is AsyncLoading);

    return GestureDetector(
      onTap: isLoading
          ? null
          : () async {
              if (hasDirect) {
                final res = await http.get(Uri.parse(document.fileUrl));
                if (res.statusCode == 200) {
                  if (context.mounted) {
                    _openPdfViewer(context, res.bodyBytes);
                  }
                }
              } else {
                _openPdfViewer(context, pdfBytesAsync?.value);
              }
            },
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.picture_as_pdf_rounded,
              size: 48,
              color: isLoading
                  ? AppColors.primary.withOpacity(0.4)
                  : AppColors.primary,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                document.fileName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Tap to view',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openPdfViewer(BuildContext context, Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PDF not available')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _PdfViewerPage(pdfBytes: bytes, fileName: document.fileName),
      ),
    );
  }
}

/// Full-screen PDF viewer using pdfx.
class _PdfViewerPage extends StatefulWidget {
  final Uint8List pdfBytes;
  final String fileName;

  const _PdfViewerPage({required this.pdfBytes, required this.fileName});

  @override
  State<_PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<_PdfViewerPage> {
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openData(widget.pdfBytes),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PdfViewPinch(
        controller: _controller,
        scrollDirection: Axis.vertical,
      ),
    );
  }
}

// =============================================================================
// STATUS BADGE
// =============================================================================

class _StatusBadge extends StatelessWidget {
  final DocumentStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, bgColor) = switch (status) {
      DocumentStatus.processing => (
          'Processing',
          EditorialColors.onSurfaceVariant,
          EditorialColors.surfaceContainerHigh,
        ),
      DocumentStatus.completed => (
          'Completed',
          EditorialColors.onSurface,
          EditorialColors.surfaceContainerHigh,
        ),
      DocumentStatus.flagged => (
          'Flagged',
          EditorialColors.error,
          EditorialColors.errorContainer,
        ),
      DocumentStatus.failed => (
          'Failed',
          EditorialColors.error,
          EditorialColors.errorContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _DuplicateNotice extends ConsumerWidget {
  const _DuplicateNotice({required this.document});

  final DocumentModel document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final originalId = document.duplicateOfId;
    final originalAsync = originalId == null
        ? const AsyncValue<DocumentModel?>.data(null)
        : ref.watch(documentDetailProvider(originalId));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Duplicate detected',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          originalAsync.when(
            data: (original) {
              final referenceNumber = original?.documentNumber ??
                  document.documentNumber ??
                  'Unknown';
              final referenceSupplier = original?.supplierName ??
                  document.supplierName ??
                  'Unknown supplier';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This document matches:',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.error.withOpacity(0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Invoice #$referenceNumber from $referenceSupplier',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (originalId != null) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (context.mounted) {
                            DocumentDetailSheet.show(context, originalId);
                          }
                        });
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('View original'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              );
            },
            loading: () => const SizedBox(
              height: 22,
              child: LinearProgressIndicator(minHeight: 2),
            ),
            error: (_, __) => Text(
              'This document matches another invoice in your company.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.error.withOpacity(0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// METADATA SECTION
// =============================================================================

class _MetadataSection extends StatelessWidget {
  final DocumentModel document;

  const _MetadataSection({required this.document});

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('dd MMM yyyy');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _MetadataRow(
            label: 'Supplier',
            value: document.supplierName ?? 'Unknown supplier',
          ),
          _MetadataRow(label: 'Type', value: document.documentType.displayName),
          _MetadataRow(
            label: 'Document #',
            value: document.documentNumber ?? '-',
          ),
          _MetadataRow(
            label: 'Date',
            value: document.documentDate != null
                ? dateFormatter.format(document.documentDate!)
                : '-',
          ),
          _MetadataRow(
            label: 'Total',
            value: document.totalAmount != null
                ? '${document.currency} ${document.totalAmount!.toStringAsFixed(2)}'
                : '--',
          ),
          _MetadataRow(label: 'File', value: document.fileName),
          _MetadataRow(
            label: 'Uploaded',
            value: dateFormatter.format(document.createdAt),
          ),
          _MetadataRow(
            label: 'Tax',
            value: document.taxAmount != null
                ? '${document.currency} ${document.taxAmount!.toStringAsFixed(2)}'
                : '--',
          ),
          if (document.notes != null && document.notes!.isNotEmpty)
            _MetadataRow(label: 'Notes', value: document.notes!),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.primary.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
