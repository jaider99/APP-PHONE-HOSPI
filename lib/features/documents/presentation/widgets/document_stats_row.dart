import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:hospi_dash/providers/documents_provider.dart';

/// Compact stats row for the documents overview.
class DocumentStatsRow extends ConsumerWidget {
  const DocumentStatsRow({
    super.key,
    this.horizontalPadding = AppSpacing.screenPadding,
  });

  final double horizontalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(documentCountsProvider);

    return countsAsync.when(
      data: (counts) =>
          _StatsContent(counts: counts, horizontalPadding: horizontalPadding),
      loading: () => _StatsContent(
        counts: const DocumentCounts(),
        horizontalPadding: horizontalPadding,
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _StatsContent extends StatelessWidget {
  final DocumentCounts counts;
  final double horizontalPadding;

  const _StatsContent({
    required this.counts,
    this.horizontalPadding = AppSpacing.screenPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Wrap(
        spacing: 6,
        runSpacing: AppSpacing.xs,
        children: [
          _StatPill(
            label: '${counts.processing} processing',
            dotColor: EditorialColors.onSurfaceVariant,
            background: const Color(0xFFF3F2EF),
            foreground: EditorialColors.onSurfaceVariant,
          ),
          _StatPill(
            label: '${counts.completed} completed',
            dotColor: const Color(0xFF4EAE83),
            background: const Color(0xFFE9F6EF),
            foreground: const Color(0xFF2F9A67),
          ),
          _StatPill(
            label: '${counts.flagged} flagged',
            dotColor: const Color(0xFF8A6A21),
            background: const Color(0xFFF9EFD9),
            foreground: const Color(0xFF7B5C18),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.dotColor,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color dotColor;
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
