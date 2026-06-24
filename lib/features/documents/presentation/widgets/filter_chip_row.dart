import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:hospi_dash/providers/documents_provider.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium horizontally scrollable document filters.
class FilterChipRow extends ConsumerWidget {
  const FilterChipRow({
    super.key,
    this.horizontalPadding = AppSpacing.screenPadding,
  });

  final double horizontalPadding;

  static const _filters = [
    (DocumentFilter.all, 'All Docs'),
    (DocumentFilter.processing, 'Processing'),
    (DocumentFilter.completed, 'Completed'),
    (DocumentFilter.flagged, 'Flagged'),
    (DocumentFilter.invoices, 'Invoices'),
    (DocumentFilter.deliveryNotes, 'Delivery notes'),
    (DocumentFilter.expenseTickets, 'Expenses'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeFilter = ref.watch(documentFilterProvider);

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
        ),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (filter, label) = _filters[index];
          final selected = activeFilter == filter;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              ref.read(documentFilterProvider.notifier).state = filter;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? EditorialColors.primary
                    : EditorialColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(999),
                boxShadow: selected
                    ? const []
                    : const [
                        BoxShadow(
                          color: Color(0x0D1A1C1C),
                          blurRadius: 14,
                          offset: Offset(0, 7),
                        ),
                      ],
              ),
              child: Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? EditorialColors.onPrimary
                      : EditorialColors.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
