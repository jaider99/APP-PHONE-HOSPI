import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:hospi_dash/shared/animations/ai_processing_indicator.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

/// Document card that renders differently based on status
class DocumentCard extends StatelessWidget {
  final DocumentModel document;
  final VoidCallback? onTap;
  final double horizontalPadding;

  const DocumentCard({
    required this.document,
    super.key,
    this.onTap,
    this.horizontalPadding = AppSpacing.screenPadding,
  });

  @override
  Widget build(BuildContext context) {
    return switch (document.status) {
      DocumentStatus.processing =>
        _ProcessingCard(
          document: document,
          onTap: onTap,
          horizontalPadding: horizontalPadding,
        ),
      DocumentStatus.completed =>
        _CompletedCard(
          document: document,
          onTap: onTap,
          horizontalPadding: horizontalPadding,
        ),
      DocumentStatus.flagged ||
      DocumentStatus.failed =>
        _FlaggedCard(
          document: document,
          onTap: onTap,
          horizontalPadding: horizontalPadding,
        ),
    };
  }
}

// =============================================================================
// PROCESSING CARD — monochrome shimmer + breathing animation
// =============================================================================

class _ProcessingCard extends StatefulWidget {
  final DocumentModel document;
  final VoidCallback? onTap;
  final double horizontalPadding;

  const _ProcessingCard({
    required this.document,
    required this.horizontalPadding,
    this.onTap,
  });

  @override
  State<_ProcessingCard> createState() => _ProcessingCardState();
}

class _ProcessingCardState extends State<_ProcessingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _dotAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    // Used to drive the animated dots (0 → 3 dots cycling)
    _dotAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      onTap: widget.onTap,
      tone: const Color(0xFFF1F1F1),
      horizontalPadding: widget.horizontalPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Shimmer.fromColors(
                baseColor: const Color(0xFFE7E7E7),
                highlightColor: EditorialColors.surfaceContainerLowest,
                child: const _LeadingIconShell(
                  color: Color(0xFFEDEDED),
                  icon: Icons.description_outlined,
                  iconColor: EditorialColors.onSurfaceVariant,
                ),
              ),
              AppSpacing.horizontalMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.document.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: EditorialColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const AiProcessingIndicator(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _dotAnimation,
                            builder: (context, _) {
                              final dots =
                                  '.' * ((_dotAnimation.value * 3).floor() + 1);
                              return Text(
                                'AI extracting$dots',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: EditorialColors.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _MetaWrap(
                      children: [
                        _SoftMetaPill(label: widget.document.documentType.displayName),
                        const _StatusPill(
                          label: 'AI extracting',
                          background: Color(0xFFEAEAEA),
                          foreground: EditorialColors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// COMPLETED CARD — supplier, amount, date
// =============================================================================

class _CompletedCard extends StatelessWidget {
  final DocumentModel document;
  final VoidCallback? onTap;
  final double horizontalPadding;

  const _CompletedCard({
    required this.document,
    required this.horizontalPadding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      onTap: onTap,
      horizontalPadding: horizontalPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trailingWidth = constraints.maxWidth < 420 ? 92.0 : 120.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LeadingIconShell(
                color: _typeColor(document.documentType).withValues(alpha: 0.14),
                icon: _typeIcon(document.documentType),
                iconColor: _typeColor(document.documentType),
              ),
              AppSpacing.horizontalMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: EditorialColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      document.displaySubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: EditorialColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MetaWrap(
                      children: [
                        _SoftMetaPill(label: document.documentType.displayName),
                        if (document.mergeStatus != DocumentMergeStatus.none)
                          _StatusPill(
                            label: _mergeLabel(document),
                            background: _mergeBackground(document),
                            foreground: _mergeForeground(document),
                          ),
                        if (document.isDuplicate &&
                            document.mergeStatus == DocumentMergeStatus.none)
                          const _StatusPill(
                            label: 'Duplicate',
                            background: Color(0xFFFCEAEA),
                            foreground: Color(0xFF9E2B25),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: trailingWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (document.totalAmount != null)
                      Text(
                        _formatAmount(document.totalAmount!, document.currency),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: EditorialColors.onSurface,
                        ),
                      )
                    else
                      Text(
                        _formatDate(document.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: EditorialColors.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: EditorialColors.onSurface,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _typeIcon(DocumentType type) {
    return switch (type) {
      DocumentType.invoice => Icons.receipt_long_rounded,
      DocumentType.deliveryNote => Icons.local_shipping_rounded,
      DocumentType.expenseTicket => Icons.receipt_rounded,
      DocumentType.unknown => Icons.description_rounded,
    };
  }

  Color _typeColor(DocumentType type) {
    return switch (type) {
      DocumentType.invoice => const Color(0xFF4B6EF5),
      DocumentType.deliveryNote => const Color(0xFF2E8B57),
      DocumentType.expenseTicket => const Color(0xFFC27A12),
      DocumentType.unknown => EditorialColors.onSurface,
    };
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

// =============================================================================
// FLAGGED CARD — warning accent
// =============================================================================

class _FlaggedCard extends StatelessWidget {
  final DocumentModel document;
  final VoidCallback? onTap;
  final double horizontalPadding;

  const _FlaggedCard({
    required this.document,
    required this.horizontalPadding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      onTap: onTap,
      tone: const Color(0xFFFFF8F7),
      horizontalPadding: horizontalPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LeadingIconShell(
            color: Color(0xFFFDECEC),
            icon: Icons.flag_rounded,
            iconColor: Color(0xFFB24139),
          ),
          AppSpacing.horizontalMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: EditorialColors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  document.notes ?? 'Needs manual review',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF9E2B25),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _MetaWrap(
                  children: [
                    _SoftMetaPill(label: document.documentType.displayName),
                    const _StatusPill(
                      label: 'Needs attention',
                      background: Color(0xFFFDECEC),
                      foreground: Color(0xFFB24139),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF8E9E8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFB24139),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SHARED CARD SHELL
// =============================================================================

class _CardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? tone;
  final double horizontalPadding;

  const _CardShell({
    required this.child,
    this.onTap,
    this.tone,
    this.horizontalPadding = AppSpacing.screenPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 3,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tone ?? EditorialColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F1A1C1C),
                  blurRadius: 30,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Placeholder shimmer card shown during initial loading
class DocumentCardShimmer extends StatelessWidget {
  const DocumentCardShimmer({
    super.key,
    this.horizontalPadding = AppSpacing.screenPadding,
  });

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 4,
      ),
      child: Shimmer.fromColors(
        baseColor: const Color(0xFFEDEDED),
        highlightColor: EditorialColors.surfaceContainerLowest,
        child: Container(
          height: 98,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(26),
          ),
        ),
      ),
    );
  }
}

class _LeadingIconShell extends StatelessWidget {
  const _LeadingIconShell({
    required this.color,
    required this.icon,
    required this.iconColor,
  });

  final Color color;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: iconColor, size: 22),
    );
  }
}

class _SoftMetaPill extends StatelessWidget {
  const _SoftMetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: EditorialColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

class _MetaWrap extends StatelessWidget {
  const _MetaWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: children,
    );
  }
}

String _mergeLabel(DocumentModel document) {
  switch (document.mergeStatus) {
    case DocumentMergeStatus.merged:
      return 'Merged';
    case DocumentMergeStatus.review:
      return 'Review';
    case DocumentMergeStatus.none:
      return '';
  }
}

Color _mergeBackground(DocumentModel document) {
  switch (document.mergeStatus) {
    case DocumentMergeStatus.merged:
      return const Color(0xFFECE8FF);
    case DocumentMergeStatus.review:
      return const Color(0xFFFFF0D8);
    case DocumentMergeStatus.none:
      return const Color(0xFFF4F4F4);
  }
}

Color _mergeForeground(DocumentModel document) {
  switch (document.mergeStatus) {
    case DocumentMergeStatus.merged:
      return const Color(0xFF5D46B0);
    case DocumentMergeStatus.review:
      return const Color(0xFF9A5A00);
    case DocumentMergeStatus.none:
      return EditorialColors.onSurfaceVariant;
  }
}

String _formatDate(DateTime date) {
  return DateFormat('d MMM yyyy').format(date);
}
