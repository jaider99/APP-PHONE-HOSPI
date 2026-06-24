import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/core/theme/app_motion.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/documents/data/models/upload_document_result.dart';
import 'package:hospi_dash/features/documents/data/services/document_delete_service.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:hospi_dash/features/expenses/data/models/expense_model.dart';
import 'package:hospi_dash/features/expenses/presentation/providers/expense_form_provider.dart';
import 'package:hospi_dash/providers/documents_provider.dart';
import 'package:hospi_dash/services/category_ai_service.dart';
import 'package:hospi_dash/services/step_up_auth_service.dart';
import 'package:hospi_dash/shared/ui/ui.dart';
import 'package:hospi_dash/shared/widgets/app_back_button.dart';
import 'package:image_picker/image_picker.dart';

/// Expense creation form for metadata-first expense submission.
class ExpenseFormScreen extends ConsumerStatefulWidget {
  final ExpenseFormArgs args;

  const ExpenseFormScreen({super.key, required this.args});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _purchaseOrderCtrl;
  late final AnimationController _entranceController;
  late final ScrollController _scrollController;
  bool _ctaHighlighted = false;
  bool _configuredEntrance = false;

  @override
  void initState() {
    super.initState();
    _purchaseOrderCtrl = TextEditingController();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _scrollController = ScrollController()..addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _configureEntrance(
          MediaQuery.maybeOf(context)?.disableAnimations ?? false);
      _handleScroll();
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final shouldHighlight = _scrollController.position.extentAfter <= 220;
    if (shouldHighlight == _ctaHighlighted) return;
    setState(() => _ctaHighlighted = shouldHighlight);
  }

  void _configureEntrance(bool disableAnimations) {
    if (disableAnimations) {
      _entranceController.value = 1;
      _configuredEntrance = true;
      return;
    }
    if (_configuredEntrance) return;
    _configuredEntrance = true;
    _entranceController.forward();
  }

  Animation<double> _segment(double start, double end) {
    return CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureEntrance(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _entranceController.dispose();
    _purchaseOrderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final formState = ref.watch(expenseFormProvider(widget.args));
    final notifier = ref.read(expenseFormProvider(widget.args).notifier);
    final categories = ref.watch(expenseCategoriesProvider);
    final pageCount = formState.pages.isEmpty ? 1 : formState.pages.length;
    final heroPreviewBytes = formState.pages.isNotEmpty
        ? formState.pages.first
        : widget.args.fileBytes;
    final heroIsImage =
        formState.pages.isNotEmpty || widget.args.mimeType.startsWith('image/');

    return AppScaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      clampContent: false,
      topBar: AppTopBar(
        leading: const AppBackButton(
          fallbackRoute: AppRoutes.expenses,
          tooltip: 'Close',
          semanticLabel: 'Close expense form',
          useCloseIcon: true,
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 152),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EntranceReveal(
              animation: _segment(0.0, 0.42),
              disableAnimations: disableAnimations,
              child: const _UploadHeaderSection(),
            ),
            const SizedBox(height: 28),
            _EntranceReveal(
              animation: _segment(0.1, 0.58),
              disableAnimations: disableAnimations,
              child: _UploadHeroCard(
                previewBytes: heroPreviewBytes,
                isImage: heroIsImage,
                fileName: widget.args.fileName,
                mimeType: widget.args.mimeType,
                pageCount: pageCount,
              ),
            ),
            const SizedBox(height: 24),
            _EntranceReveal(
              animation: _segment(0.2, 0.74),
              disableAnimations: disableAnimations,
              child: _PagePreviewRow(
                pages: formState.pages,
                selectedFileBytes: widget.args.fileBytes,
                selectedFileName: widget.args.fileName,
                selectedMimeType: widget.args.mimeType,
                onDelete: notifier.removePage,
                onAddPage: () => _pickAdditionalPage(notifier),
                disableAnimations: disableAnimations,
              ),
            ),
            const SizedBox(height: 24),
            _EntranceReveal(
              animation: _segment(0.24, 0.8),
              disableAnimations: disableAnimations,
              child: const _InfoBanner(),
            ),
            const SizedBox(height: 28),
            _EntranceReveal(
              animation: _segment(0.3, 0.88),
              disableAnimations: disableAnimations,
              child: _SurfaceSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: EditorialColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Route the document to the right spend bucket.',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        height: 1.5,
                        color: EditorialColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _EditorialDropdown<String>(
                      value: formState.categoryId,
                      hint: 'No category',
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('No category'),
                        ),
                        ...categories.when(
                          data: (cats) => cats.map(
                            (ExpenseCategory c) => DropdownMenuItem<String>(
                              value: c.id,
                              child: _CategoryItemLabel(
                                name: c.name,
                                colorHex: c.colorHex,
                              ),
                            ),
                          ),
                          loading: () => <DropdownMenuItem<String>>[],
                          error: (_, __) => <DropdownMenuItem<String>>[],
                        ),
                      ],
                      onChanged: notifier.setCategory,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _EntranceReveal(
              animation: _segment(0.34, 0.94),
              disableAnimations: disableAnimations,
              child: _SurfaceSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'More options',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: EditorialColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Add metadata and control how this expense lands.',
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: EditorialColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Switch.adaptive(
                          value: formState.moreOptionsExpanded,
                          onChanged: (_) => notifier.toggleMoreOptions(),
                          activeColor: EditorialColors.accent,
                        ),
                      ],
                    ),
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: _MoreOptionsSection(
                          formState: formState,
                          notifier: notifier,
                          purchaseOrderCtrl: _purchaseOrderCtrl,
                        ),
                      ),
                      crossFadeState: formState.moreOptionsExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: disableAnimations
                          ? Duration.zero
                          : AppMotion.standard,
                      sizeCurve: Curves.easeOutCubic,
                    ),
                  ],
                ),
              ),
            ),
            if (formState.submitError != null) ...[
              const SizedBox(height: 18),
              _SurfaceSectionCard(
                backgroundColor: EditorialColors.errorContainer,
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: EditorialColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        formState.submitError!,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: EditorialColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),

      // ── Sticky CTA ─────────────────────────────────────────────────────
      bottomBar: _EntranceReveal(
        animation: _segment(0.3, 1),
        disableAnimations: disableAnimations,
        child: _StickyCTA(
          isSubmitting: formState.isSubmitting,
          onPressed:
              formState.isSubmitting ? null : () => _handleSubmit(notifier),
          isHighlighted: _ctaHighlighted,
          disableAnimations: disableAnimations,
        ),
      ),
    );
  }

  Future<void> _handleSubmit(ExpenseFormNotifier notifier) async {
    final result = await notifier.submit();
    if (!mounted || !result.success) return;

    if (result.documentId != null) {
      _showSnackBar('Expense saved • Extraction continues in the background');
      context.pop();
      return;
    }

    final categories = await ref.read(expenseCategoriesProvider.future);
    final categoryAi = ref.read(categoryAiServiceProvider);
    final resolvedCategoryName = categoryAi.resolveCategoryName(
      categories,
      result.aiCategoryId ?? result.categoryId,
    );

    if (result.mergeStatus == DocumentMergeStatus.merged) {
      _showSnackBar('Duplicate auto-merged into an existing invoice');
      context.pop();
      return;
    }

    if (result.mergeStatus == DocumentMergeStatus.review) {
      _showSnackBar('Possible duplicate sent to the review queue');
      context.pop();
      return;
    }

    if (result.categoryAutoApplied) {
      final categoryLabel = resolvedCategoryName ?? 'predicted category';
      _showSnackBar('Expense saved • Auto-categorized as $categoryLabel');
      context.pop();
      return;
    }

    if (result.hasCategorySuggestion) {
      final categoryLabel = resolvedCategoryName ?? 'predicted category';
      _showSnackBar(
        'Expense saved • Suggested category: $categoryLabel '
        '(${(result.categoryConfidence * 100).round()}%)',
      );
      context.pop();
      return;
    }

    if (result.categoryNeedsReview) {
      _showSnackBar('Expense saved • Category needs review');
      context.pop();
      return;
    }

    if (result.isDuplicate) {
      final keepDuplicate = await _showDuplicateDialog(result);
      if (!mounted) return;

      if (keepDuplicate) {
        _showSnackBar('Duplicate saved for audit');
        context.pop();
        return;
      }

      if (result.documentId != null) {
        try {
          final deleteService = DocumentDeleteService(
            SupabaseService.client,
            stepUpAuthService: ref.read(stepUpAuthServiceProvider),
          );
          await deleteService.deleteDocument(
            documentId: result.documentId!,
            companyId: widget.args.companyId,
            filePath: '',
          );
          ref
              .read(documentsProvider.notifier)
              .removeDocument(result.documentId!);
          ref.invalidate(documentCountsProvider);
          ref.invalidate(documentDetailProvider(result.documentId!));
        } on DocumentDeleteException catch (e) {
          if (!mounted) return;
          _showSnackBar(e.message);
          return;
        }
      }

      if (!mounted) return;
      _showSnackBar('Duplicate upload discarded');
      context.pop();
      return;
    }

    _showSnackBar('Expense saved');
    context.pop();
  }

  Future<bool> _showDuplicateDialog(UploadDocumentResult result) async {
    final referenceNumber = result.duplicateReferenceNumber ?? 'Unknown';
    final referenceSupplier =
        result.duplicateReferenceSupplier ?? 'Unknown supplier';

    final decision = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Possible duplicate detected'),
        content: Text(
          'This invoice already exists.\n\n'
          'Invoice #$referenceNumber from $referenceSupplier',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Upload anyway'),
          ),
        ],
      ),
    );

    return decision ?? false;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: EditorialTypography.bodySmall.copyWith(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: EditorialColors.onSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: EditorialRadius.borderRadiusMd,
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _pickAdditionalPage(ExpenseFormNotifier notifier) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1920,
    );
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    notifier.addPage(bytes);
  }
}

// =============================================================================
// INFO BANNER
// =============================================================================

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return _SurfaceSectionCard(
      backgroundColor: const Color(0xFFF1F1F1),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: EditorialColors.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'One document per upload',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: EditorialColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.55,
                color: EditorialColors.onSurfaceVariant,
              ),
              children: const [
                TextSpan(
                    text: 'Upload the images of the same document, with the '),
                TextSpan(
                  text: 'same date, number and supplier',
                  style: TextStyle(
                    color: EditorialColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: '. Repeat the process for any other invoice.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadHeaderSection extends StatelessWidget {
  const _UploadHeaderSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upload document',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 32,
            height: 1.08,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
            color: EditorialColors.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            'Add invoices, delivery notes, or expenses.',
            style: GoogleFonts.manrope(
              fontSize: 16,
              height: 1.55,
              color: EditorialColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadHeroCard extends StatelessWidget {
  const _UploadHeroCard({
    required this.previewBytes,
    required this.isImage,
    required this.fileName,
    required this.mimeType,
    required this.pageCount,
  });

  final Uint8List previewBytes;
  final bool isImage;
  final String fileName;
  final String mimeType;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return _SurfaceSectionCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _HeroPreviewTile(
            bytes: previewBytes,
            isImage: isImage,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F1F1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pageCount == 1 ? 'Page 1 / 1' : '$pageCount pages ready',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: EditorialColors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: EditorialColors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isImage ? 'Image document preview' : mimeType.toUpperCase(),
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.45,
                    color: EditorialColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Review each page below before sending it into the intelligence pipeline.',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.45,
                    color: EditorialColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPreviewTile extends StatelessWidget {
  const _HeroPreviewTile({required this.bytes, required this.isImage});

  final Uint8List bytes;
  final bool isImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1F1),
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: isImage
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            )
          : const Icon(
              Icons.description_outlined,
              size: 34,
              color: EditorialColors.onSurfaceVariant,
            ),
    );
  }
}

class _SurfaceSectionCard extends StatelessWidget {
  const _SurfaceSectionCard({
    required this.child,
    this.backgroundColor = Colors.white,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final Color backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EntranceReveal extends StatelessWidget {
  const _EntranceReveal({
    required this.animation,
    required this.disableAnimations,
    required this.child,
  });

  final Animation<double> animation;
  final bool disableAnimations;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (disableAnimations) {
      return FadeTransition(opacity: animation, child: child);
    }

    final offset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(animation);

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: offset,
        child: child,
      ),
    );
  }
}

// =============================================================================
// PAGE PREVIEW ROW
// =============================================================================

class _PagePreviewRow extends StatefulWidget {
  const _PagePreviewRow({
    required this.pages,
    required this.selectedFileBytes,
    required this.selectedFileName,
    required this.selectedMimeType,
    required this.onDelete,
    required this.onAddPage,
    required this.disableAnimations,
  });

  final List<Uint8List> pages;
  final Uint8List selectedFileBytes;
  final String selectedFileName;
  final String selectedMimeType;
  final void Function(int) onDelete;
  final VoidCallback onAddPage;
  final bool disableAnimations;

  @override
  State<_PagePreviewRow> createState() => _PagePreviewRowState();
}

class _PagePreviewRowState extends State<_PagePreviewRow> {
  late final PageController _pageController;
  double _page = 0;

  int get _realPageCount => widget.pages.isEmpty ? 1 : widget.pages.length;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.66)
      ..addListener(_handlePageScroll);
  }

  @override
  void didUpdateWidget(covariant _PagePreviewRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxIndex = _realPageCount;
    final current = (_pageController.page ?? 0).round();
    final targetPage = math.min(current, maxIndex);
    if (_pageController.hasClients && targetPage != current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(targetPage);
      });
    }
  }

  void _handlePageScroll() {
    final nextPage = _pageController.page ?? 0;
    if ((nextPage - _page).abs() < 0.001) return;
    setState(() => _page = nextPage);
  }

  @override
  void dispose() {
    _pageController
      ..removeListener(_handlePageScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _openPreview({
    required Uint8List bytes,
    required bool isImage,
    required String title,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: EditorialColors.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: EditorialColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  color: const Color(0xFFF1F1F1),
                  constraints: const BoxConstraints(maxHeight: 440),
                  width: double.infinity,
                  child: isImage
                      ? InteractiveViewer(
                          minScale: 1,
                          maxScale: 3,
                          child: Image.memory(bytes, fit: BoxFit.contain),
                        )
                      : const Padding(
                          padding: EdgeInsets.symmetric(vertical: 56),
                          child: Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 56,
                            color: EditorialColors.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _page.round();
    final currentPageLabel = activeIndex >= _realPageCount
        ? 'Add page'
        : 'Page ${math.min(activeIndex + 1, _realPageCount)} / $_realPageCount';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Document pages',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: EditorialColors.onSurface,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F1F1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                currentPageLabel,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: EditorialColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Swipe through pages, inspect details, delete mistakes, or append another page.',
          style: GoogleFonts.manrope(
            fontSize: 14,
            height: 1.5,
            color: EditorialColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 232,
          child: PageView.builder(
            controller: _pageController,
            padEnds: false,
            physics: _platformCarouselPhysics(context),
            itemCount: _realPageCount + 1,
            itemBuilder: (context, index) {
              final distance = (_page - index).abs().clamp(0, 1).toDouble();
              final scale =
                  widget.disableAnimations ? 1.0 : 1 - (distance * 0.04);

              late final Widget card;
              if (index == _realPageCount) {
                card = _AddPageButton(
                  onTap: widget.onAddPage,
                  disableAnimations: widget.disableAnimations,
                );
              } else if (widget.pages.isEmpty) {
                card = _PreviewPageCard(
                  bytes: widget.selectedFileBytes,
                  title: widget.selectedFileName,
                  subtitle: widget.selectedMimeType.startsWith('image/')
                      ? 'Original document'
                      : widget.selectedMimeType.toUpperCase(),
                  isImage: widget.selectedMimeType.startsWith('image/'),
                  onView: () => _openPreview(
                    bytes: widget.selectedFileBytes,
                    isImage: widget.selectedMimeType.startsWith('image/'),
                    title: widget.selectedFileName,
                  ),
                  disableAnimations: widget.disableAnimations,
                );
              } else {
                final pageNumber = index + 1;
                card = _PreviewPageCard(
                  bytes: widget.pages[index],
                  title: 'Page $pageNumber',
                  subtitle:
                      pageNumber == 1 ? 'Primary capture' : 'Additional page',
                  isImage: true,
                  onView: () => _openPreview(
                    bytes: widget.pages[index],
                    isImage: true,
                    title: 'Page $pageNumber',
                  ),
                  onDelete: () => widget.onDelete(index),
                  disableAnimations: widget.disableAnimations,
                );
              }

              return Padding(
                padding:
                    EdgeInsets.only(right: index == _realPageCount ? 0 : 14),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: card,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

ScrollPhysics _platformCarouselPhysics(BuildContext context) {
  final platform = Theme.of(context).platform;
  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return const BouncingScrollPhysics(parent: PageScrollPhysics());
    default:
      return const PageScrollPhysics();
  }
}

class _PreviewPageCard extends StatefulWidget {
  const _PreviewPageCard({
    required this.bytes,
    required this.title,
    required this.subtitle,
    required this.isImage,
    required this.onView,
    required this.disableAnimations,
    this.onDelete,
  });

  final Uint8List bytes;
  final String title;
  final String subtitle;
  final bool isImage;
  final VoidCallback onView;
  final VoidCallback? onDelete;
  final bool disableAnimations;

  @override
  State<_PreviewPageCard> createState() => _PreviewPageCardState();
}

class _PreviewPageCardState extends State<_PreviewPageCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final background = _pressed && !widget.disableAnimations
        ? const Color(0xFFF7F4F2)
        : Colors.white;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && !widget.disableAnimations ? 0.95 : 1,
        duration: widget.disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: widget.disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 24,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: double.infinity,
                    color: const Color(0xFFF1F1F1),
                    child: widget.isImage
                        ? Image.memory(
                            widget.bytes,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                          )
                        : const Icon(
                            Icons.description_outlined,
                            size: 34,
                            color: EditorialColors.onSurfaceVariant,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: EditorialColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: EditorialColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PreviewActionButton(
                      icon: Icons.open_in_full_rounded,
                      label: 'View',
                      onPressed: widget.onView,
                      disableAnimations: widget.disableAnimations,
                    ),
                  ),
                  if (widget.onDelete != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PreviewActionButton(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        onPressed: widget.onDelete!,
                        destructive: true,
                        disableAnimations: widget.disableAnimations,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewActionButton extends StatefulWidget {
  const _PreviewActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.disableAnimations,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
  final bool disableAnimations;

  @override
  State<_PreviewActionButton> createState() => _PreviewActionButtonState();
}

class _PreviewActionButtonState extends State<_PreviewActionButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final normalBackground =
        widget.destructive ? const Color(0xFFF7E7E2) : const Color(0xFFF1F1F1);
    final pressedBackground =
        widget.destructive ? const Color(0xFFEBCFC6) : const Color(0xFFE7E7E7);
    final foreground = widget.destructive
        ? const Color(0xFFB35D49)
        : EditorialColors.onSurfaceVariant;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed && !widget.disableAnimations ? 0.97 : 1,
        duration: widget.disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: widget.disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          height: 42,
          decoration: BoxDecoration(
            color: _pressed ? pressedBackground : normalBackground,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddPageButton extends StatefulWidget {
  const _AddPageButton({
    required this.onTap,
    required this.disableAnimations,
  });

  final VoidCallback onTap;
  final bool disableAnimations;

  @override
  State<_AddPageButton> createState() => _AddPageButtonState();
}

class _AddPageButtonState extends State<_AddPageButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 1.06)
            .chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.06, end: 1)
            .chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 50,
      ),
    ]).animate(_pulseController);
    if (!widget.disableAnimations) {
      _pulseController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _AddPageButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disableAnimations) {
      _pulseController.stop();
      _pulseController.value = 0;
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final background = _pressed && !widget.disableAnimations
        ? const Color(0xFFF3F3F3)
        : Colors.white;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed && !widget.disableAnimations ? 0.97 : 1,
        duration: widget.disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: widget.disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 24,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F1F1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: ScaleTransition(
                    scale: widget.disableAnimations
                        ? const AlwaysStoppedAnimation<double>(1)
                        : _pulse,
                    child: const Icon(
                      Icons.add_rounded,
                      size: 28,
                      color: EditorialColors.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Add page',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: EditorialColors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Append another capture',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: EditorialColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// EXTRACTION BANNERS
// =============================================================================

class _ExtractionLoadingBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EditorialColors.infoLight,
        borderRadius: EditorialRadius.borderRadiusMd,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: EditorialColors.info,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Extracting data from document…',
                style: EditorialTypography.bodySmall
                    .copyWith(color: EditorialColors.info)),
          ),
        ],
      ),
    );
  }
}

class _ExtractionErrorBanner extends StatelessWidget {
  final String message;
  const _ExtractionErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EditorialColors.warningLight,
        borderRadius: EditorialRadius.borderRadiusMd,
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              color: EditorialColors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: EditorialTypography.bodySmall
                    .copyWith(color: EditorialColors.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: EditorialColors.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: EditorialTypography.labelLarge
                .copyWith(color: EditorialColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// EDITORIAL TEXT FIELD
// =============================================================================

class _EditorialTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? suffixText;
  final void Function(String?) onChanged;

  const _EditorialTextField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.suffixText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: EditorialTypography.bodyLarge,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: EditorialTypography.bodyLarge
            .copyWith(color: EditorialColors.outlineVariant),
        suffixText: suffixText,
        suffixStyle: EditorialTypography.labelLarge
            .copyWith(color: EditorialColors.onSurfaceVariant),
        filled: true,
        fillColor: EditorialColors.surfaceContainerLowest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: EditorialRadius.borderRadiusStandard,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: EditorialRadius.borderRadiusStandard,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: EditorialRadius.borderRadiusStandard,
          borderSide: BorderSide(
              color: EditorialColors.outline.withOpacity(0.4), width: 1),
        ),
      ),
    );
  }
}

// =============================================================================
// EDITORIAL DROPDOWN
// =============================================================================

class _CategoryItemLabel extends StatelessWidget {
  final String name;
  final String? colorHex;

  const _CategoryItemLabel({required this.name, this.colorHex});

  @override
  Widget build(BuildContext context) {
    final color = _parseHexColor(colorHex) ?? EditorialColors.outlineVariant;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

Color? _parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final normalized = hex.replaceAll('#', '');
  if (normalized.length != 6) return null;
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

class _EditorialDropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;

  const _EditorialDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: EditorialRadius.borderRadiusStandard,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint,
              style: EditorialTypography.bodyLarge
                  .copyWith(color: EditorialColors.outlineVariant)),
          isExpanded: true,
          icon: const Icon(Icons.expand_more,
              color: EditorialColors.outlineVariant),
          style: EditorialTypography.bodyLarge,
          dropdownColor: EditorialColors.surfaceContainerLowest,
          borderRadius: EditorialRadius.borderRadiusStandard,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// =============================================================================
// MORE OPTIONS SECTION
// =============================================================================

class _MoreOptionsSection extends StatelessWidget {
  final ExpenseFormState formState;
  final ExpenseFormNotifier notifier;
  final TextEditingController purchaseOrderCtrl;

  const _MoreOptionsSection({
    required this.formState,
    required this.notifier,
    required this.purchaseOrderCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Document type
        _FieldLabel(icon: Icons.description_outlined, label: 'Document type'),
        const SizedBox(height: 8),
        _EditorialDropdown<String>(
          value: formState.documentType,
          hint: 'Detect automatically',
          items: const [
            DropdownMenuItem(value: null, child: Text('Detect automatically')),
            DropdownMenuItem(value: 'invoice', child: Text('Invoice')),
            DropdownMenuItem(
                value: 'expense_ticket', child: Text('Expense Ticket')),
            DropdownMenuItem(
                value: 'delivery_note', child: Text('Delivery Note')),
          ],
          onChanged: notifier.setDocumentType,
        ),
        const SizedBox(height: 22),

        // Payment method
        _FieldLabel(icon: Icons.credit_card_outlined, label: 'Payment method'),
        const SizedBox(height: 8),
        _EditorialDropdown<String>(
          value: formState.paymentMethod,
          hint: 'Select a payment method',
          items: const [
            DropdownMenuItem(value: null, child: Text('None')),
            DropdownMenuItem(
                value: 'company_card', child: Text('Company Card')),
            DropdownMenuItem(
                value: 'personal_cash', child: Text('Personal Cash')),
            DropdownMenuItem(
                value: 'bank_transfer', child: Text('Bank Transfer')),
          ],
          onChanged: notifier.setPaymentMethod,
        ),
        const SizedBox(height: 22),

        // Purchase order
        _FieldLabel(
            icon: Icons.shopping_cart_outlined, label: 'Purchase number'),
        const SizedBox(height: 8),
        _EditorialTextField(
          controller: purchaseOrderCtrl,
          hint: 'Search and select a purchase order',
          onChanged: notifier.setPurchaseOrderId,
        ),
        const SizedBox(height: 22),

        // Incident
        _FieldLabel(icon: Icons.warning_amber_outlined, label: 'Incident'),
        const SizedBox(height: 8),
        _EditorialDropdown<String>(
          value: formState.incident,
          hint: 'Select an option',
          items: const [
            DropdownMenuItem(value: null, child: Text('None')),
            DropdownMenuItem(
                value: 'missing_receipt', child: Text('Missing receipt')),
            DropdownMenuItem(
                value: 'incorrect_amount', child: Text('Incorrect amount')),
            DropdownMenuItem(value: 'duplicate', child: Text('Duplicate')),
          ],
          onChanged: notifier.setIncident,
        ),
        const SizedBox(height: 22),

        // Paid toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: EditorialColors.surfaceContainerLowest,
            borderRadius: EditorialRadius.borderRadiusStandard,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Paid',
                  style: EditorialTypography.titleSmall
                      .copyWith(color: EditorialColors.onSurfaceVariant)),
              Switch.adaptive(
                value: formState.isPaid,
                onChanged: notifier.setIsPaid,
                activeColor: EditorialColors.accent,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// STICKY CTA
// =============================================================================

class _StickyCTA extends StatelessWidget {
  final bool isSubmitting;
  final VoidCallback? onPressed;
  final bool isHighlighted;
  final bool disableAnimations;

  const _StickyCTA({
    required this.isSubmitting,
    this.onPressed,
    required this.isHighlighted,
    required this.disableAnimations,
  });

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + safePadding),
      color: const Color(0xFFF9F9F9).withOpacity(0.92),
      child: AnimatedScale(
        scale: isHighlighted && !disableAnimations ? 1.02 : 1,
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Container(
          height: 94,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: const Color(0x12000000),
                blurRadius: isHighlighted ? 34 : 22,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Material(
              color: const Color(0xFF151515),
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  height: 94,
                  child: Center(
                    child: isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: EditorialColors.onPrimary,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.file_upload_outlined,
                                color: EditorialColors.onPrimary,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Upload Expense',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: EditorialColors.onPrimary,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
