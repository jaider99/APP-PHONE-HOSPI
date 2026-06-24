import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/documents/presentation/widgets/add_options_sheet.dart';
import 'package:hospi_dash/features/documents/presentation/widgets/document_card.dart';
import 'package:hospi_dash/features/documents/presentation/widgets/document_detail_sheet.dart';
import 'package:hospi_dash/features/documents/presentation/widgets/document_search_bar.dart';
import 'package:hospi_dash/features/documents/presentation/widgets/document_stats_row.dart';
import 'package:hospi_dash/features/documents/presentation/widgets/filter_chip_row.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:hospi_dash/providers/documents_provider.dart';
import 'package:hospi_dash/services/camera_upload_service.dart';
import 'package:hospi_dash/shared/ui/ui.dart';

/// Documents screen — Quiet Hospitality editorial inbox.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key, this.documentId});

  final String? documentId;

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  bool _hasPreloaded = false;
  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    if (widget.documentId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        DocumentDetailSheet.show(context, widget.documentId!);
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── Upload paths ───────────────────────────────────────────────────────

  Future<void> _handlePhoto() async {
    await CameraUploadService.handleCameraCapture(context, ref);
  }

  Future<void> _handleAdd() async {
    if (!mounted) return;
    final option = await AddOptionsSheet.show(context);
    if (!mounted || option == null) return;
    switch (option) {
      case AddOption.photoLibrary:
        await CameraUploadService.handleGalleryPick(context, ref);
      case AddOption.chooseFile:
        await CameraUploadService.handleFilePick(context, ref);
    }
  }

  void _handleManual() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Coming soon — manual entry will be available shortly',
          style: EditorialTypography.bodySmall.copyWith(
            fontSize: 13,
            color: Colors.white,
          ),
        ),
        backgroundColor: EditorialColors.onSurface,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(EditorialRadius.md),
          ),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ),
    );
  }

  Future<void> _openUploadSheet() {
    return BottomActionSheet.show(
      context,
      title: 'New document',
      actions: [
        SheetAction(
          label: 'Take photo',
          subtitle: 'Capture an invoice or receipt',
          icon: Icons.photo_camera_outlined,
          onTap: _handlePhoto,
        ),
        SheetAction(
          label: 'Upload from library',
          subtitle: 'Pick an image or PDF',
          icon: Icons.upload_outlined,
          onTap: _handleAdd,
        ),
        SheetAction(
          label: 'Enter manually',
          subtitle: 'Type the details yourself',
          icon: Icons.edit_outlined,
          onTap: _handleManual,
        ),
      ],
    );
  }

  // ── Document open with precaching ────────────────────────────────────────

  Future<void> _openDocument(DocumentModel doc) async {
    if (!doc.isPdf) {
      String? imageUrl;
      if (doc.filePath != null && doc.filePath!.isNotEmpty) {
        imageUrl = await ref.read(
          documentPreviewUrlProvider(doc.filePath!).future,
        );
      } else if (doc.fileUrl.isNotEmpty && doc.fileUrl.contains('token=')) {
        imageUrl = doc.fileUrl;
      }
      if (imageUrl != null && mounted) {
        await precacheImage(NetworkImage(imageUrl), context).timeout(
          const Duration(milliseconds: 150),
          onTimeout: () {},
        );
      }
    }
    if (mounted) DocumentDetailSheet.show(context, doc.id);
  }

  void _preloadDocuments(List<DocumentModel> docs) {
    for (final doc in docs) {
      if (doc.isPdf) continue;
      if (doc.filePath != null && doc.filePath!.isNotEmpty) {
        ref.read(documentPreviewUrlProvider(doc.filePath!).future).then((url) {
          if (url != null && mounted) {
            precacheImage(NetworkImage(url), context);
          }
        });
      } else if (doc.fileUrl.isNotEmpty && doc.fileUrl.contains('token=')) {
        precacheImage(NetworkImage(doc.fileUrl), context);
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value.trim().toLowerCase();
      });
    });
  }

  List<DocumentModel> _applySearch(List<DocumentModel> documents) {
    if (_searchQuery.isEmpty) return documents;

    return documents.where((document) {
      final fields = [
        document.displayTitle,
        document.displaySubtitle,
        document.supplierName,
        document.documentNumber,
        document.fileName,
        document.documentType.displayName,
        document.documentType.dbValue.replaceAll('_', ' '),
      ];

      return fields.any(
        (field) => (field ?? '').toLowerCase().contains(_searchQuery),
      );
    }).toList(growable: false);
  }

  double _pageHorizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 380) return 16;
    if (width >= 768) return 32;
    return 24;
  }

  @override
  Widget build(BuildContext context) {
    final documentsAsync = ref.watch(documentsProvider);
    final uploadProgress = ref.watch(uploadProgressProvider);
    final reviewCountAsync = ref.watch(documentMergeReviewCountProvider);
    final horizontalPadding = _pageHorizontalPadding(context);
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width >= 768 ? 32.0 : 28.0;

    return AppScaffold(
      clampContent: false,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 14)),

            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Text(
                  'Documents',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: const Color(0xFF1B1B1B),
                    height: 1.1,
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 22)),

            SliverToBoxAdapter(
              child: Column(
                children: [
                  DocumentSearchBar(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    horizontalPadding: horizontalPadding,
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Invoices, delivery notes, and expenses.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: EditorialColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            SliverToBoxAdapter(
              child: reviewCountAsync.when(
                data: (count) {
                  if (count == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      0,
                      horizontalPadding,
                      AppSpacing.md,
                    ),
                    child: _ReviewQueueBanner(
                      count: count,
                      onTap: () => context.push(AppRoutes.documentReviewQueue),
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            SliverToBoxAdapter(
              child: DocumentStatsRow(horizontalPadding: horizontalPadding),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            SliverToBoxAdapter(
              child: FilterChipRow(horizontalPadding: horizontalPadding),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            SliverToBoxAdapter(
              child: documentsAsync.maybeWhen(
                data: (documents) {
                  final visibleDocuments = _applySearch(documents);
                  final resultText = _searchQuery.isEmpty
                      ? '${documents.length} document${documents.length == 1 ? '' : 's'}'
                      : '${visibleDocuments.length} of ${documents.length} shown';
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Text(
                      resultText,
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: EditorialColors.onSurfaceVariant,
                        letterSpacing: 0.15,
                      ),
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            if (uploadProgress != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    AppSpacing.md,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: EditorialColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.all(
                        Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x0D1A1C1C),
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Uploading document',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: EditorialColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(999),
                          ),
                          child: LinearProgressIndicator(
                            value: uploadProgress,
                            backgroundColor: EditorialColors.surfaceContainer,
                            valueColor: const AlwaysStoppedAnimation(
                              EditorialColors.accent,
                            ),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            documentsAsync.when(
              data: (documents) {
                final visibleDocuments = _applySearch(documents);
                if (!_hasPreloaded && documents.isNotEmpty) {
                  _hasPreloaded = true;
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _preloadDocuments(documents.take(5).toList()),
                  );
                }
                if (documents.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _DocumentsEmptyState(onAction: _openUploadSheet),
                  );
                }
                if (visibleDocuments.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _SearchEmptyState(
                      query: _searchController.text.trim(),
                    ),
                  );
                }
                return SliverList.builder(
                  itemCount: visibleDocuments.length,
                  itemBuilder: (context, index) {
                    final doc = visibleDocuments[index];
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(
                        milliseconds: 180 + (index * 24).clamp(0, 180),
                      ),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * 10),
                            child: child,
                          ),
                        );
                      },
                      child: DocumentCard(
                        document: doc,
                        onTap: () => _openDocument(doc),
                        horizontalPadding: horizontalPadding,
                      ),
                    );
                  },
                );
              },
              loading: () => SliverList.builder(
                itemCount: 6,
                itemBuilder: (_, __) => DocumentCardShimmer(
                  horizontalPadding: horizontalPadding,
                ),
              ),
              error: (error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ErrorState(
                    message: 'We couldn’t load your documents. Try again.',
                    onRetry: () => ref.invalidate(documentsProvider),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class _ReviewQueueBanner extends StatelessWidget {
  const _ReviewQueueBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D1A1C1C),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: EditorialColors.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              color: EditorialColors.onSurface,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review queue',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: EditorialColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count document${count == 1 ? '' : 's'} waiting for a quick check.',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EditorialColors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: EditorialColors.accent,
              textStyle: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class _DocumentsEmptyState extends StatelessWidget {
  const _DocumentsEmptyState({required this.onAction});

  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: EditorialColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(36),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F1A1C1C),
                blurRadius: 30,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: EditorialColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: EditorialColors.onSurface,
                  size: 28,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No documents yet',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: EditorialColors.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Upload an invoice, delivery note, or receipt and the data will be extracted automatically.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: EditorialColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: EditorialColors.primary,
                  foregroundColor: EditorialColors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  'Upload document',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No matching documents',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: EditorialColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try another supplier name, document number, filename, or document type for "$query".',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: EditorialColors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
