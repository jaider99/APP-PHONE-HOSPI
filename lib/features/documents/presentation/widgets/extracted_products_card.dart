import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/models/document_model.dart';
import 'package:intl/intl.dart';

class ExtractedProductsCard extends StatelessWidget {
  const ExtractedProductsCard({
    required this.items,
    required this.currencyCode,
    super.key,
    this.onEdit,
    this.onRetry,
    this.isProcessing = false,
    this.hasExtractionError = false,
  });

  final List<DocumentLineItem> items;
  final String currencyCode;
  final VoidCallback? onEdit;
  final VoidCallback? onRetry;
  final bool isProcessing;
  final bool hasExtractionError;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Extracted products',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 8),
              child: child,
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
          decoration: BoxDecoration(
            color: EditorialColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Extracted Products',
                style: GoogleFonts.plusJakartaSans(
                  color: EditorialColors.onSurface,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 22),
              if (isProcessing)
                const _ExtractedProductsSkeleton()
              else if (hasExtractionError)
                _ExtractedProductsMessage(
                  title: 'Products could not be extracted',
                  body: 'Review the document or retry extraction.',
                  actionLabel: onRetry == null ? null : 'Retry extraction',
                  onAction: onRetry,
                )
              else if (items.isEmpty)
                _ExtractedProductsMessage(
                  title: 'No products extracted',
                  body:
                      'The document was processed, but no line items were detected.',
                  actionLabel: onEdit == null ? null : 'Edit manually',
                  onAction: onEdit,
                )
              else
                _ExtractedProductsList(
                  items: items,
                  currencyCode: currencyCode,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtractedProductsList extends StatelessWidget {
  const _ExtractedProductsList({
    required this.items,
    required this.currencyCode,
  });

  final List<DocumentLineItem> items;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 330;
        final columnGap = compact ? 8.0 : 12.0;

        return Column(
          children: [
            _ExtractedProductsHeader(columnGap: columnGap),
            const SizedBox(height: 10),
            for (var index = 0; index < items.length; index++) ...[
              _AnimatedExtractedProductRow(
                item: items[index],
                currencyCode: currencyCode,
                columnGap: columnGap,
                index: index,
              ),
              if (index != items.length - 1) const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _ExtractedProductsHeader extends StatelessWidget {
  const _ExtractedProductsHeader({required this.columnGap});

  final double columnGap;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.plusJakartaSans(
      color: EditorialColors.onSurfaceVariant,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('Item', style: style)),
          SizedBox(width: columnGap),
          Expanded(
            child: Text('Qty', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: columnGap),
          Expanded(
            flex: 2,
            child: Text('Price', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: columnGap),
          Expanded(
            flex: 2,
            child: Text('Total', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _AnimatedExtractedProductRow extends StatelessWidget {
  const _AnimatedExtractedProductRow({
    required this.item,
    required this.currencyCode,
    required this.columnGap,
    required this.index,
  });

  final DocumentLineItem item;
  final String currencyCode;
  final double columnGap;
  final int index;

  @override
  Widget build(BuildContext context) {
    final delay = Duration(milliseconds: (index * 25).clamp(0, 150));

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 180 + delay.inMilliseconds),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final delayFraction = delay.inMilliseconds /
            (180 + delay.inMilliseconds).clamp(1, double.infinity);
        final progress = delayFraction >= 1
            ? 1.0
            : ((value - delayFraction) / (1 - delayFraction)).clamp(0.0, 1.0);
        return AnimatedOpacity(
          opacity: progress,
          duration: Duration.zero,
          child: AnimatedSlide(
            offset: Offset(0, (1 - progress) * 0.04),
            duration: Duration.zero,
            child: child,
          ),
        );
      },
      child: _ExtractedProductRow(
        item: item,
        currencyCode: currencyCode,
        columnGap: columnGap,
      ),
    );
  }
}

class _ExtractedProductRow extends StatelessWidget {
  const _ExtractedProductRow({
    required this.item,
    required this.currencyCode,
    required this.columnGap,
  });

  final DocumentLineItem item;
  final String currencyCode;
  final double columnGap;

  @override
  Widget build(BuildContext context) {
    final description = item.description.trim().isEmpty
        ? 'Unnamed product'
        : item.description.trim();
    final quantity = _formatQuantity(item.quantity);
    final price = _formatCurrency(item.unitPrice, currencyCode);
    final total = _formatCurrency(item.lineTotal, currencyCode);

    return Semantics(
      label: '$description, quantity $quantity, price $price, total $total',
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: EditorialColors.surfaceContainerLow.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  color: const Color(0xFF1A1A1A),
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  height: 1.22,
                ),
              ),
            ),
            SizedBox(width: columnGap),
            Expanded(child: _NumericText(quantity)),
            SizedBox(width: columnGap),
            Expanded(flex: 2, child: _NumericText(price)),
            SizedBox(width: columnGap),
            Expanded(flex: 2, child: _NumericText(total, isTotal: true)),
          ],
        ),
      ),
    );
  }

  String _formatQuantity(double quantity) {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toStringAsFixed(0);
    }
    final formatter = NumberFormat.decimalPatternDigits(
      locale: 'es_ES',
      decimalDigits: 2,
    );
    return formatter.format(quantity);
  }

  String _formatCurrency(double? value, String currencyCode) {
    if (value == null) return '—';
    final formatter = NumberFormat.currency(
      locale: 'es_ES',
      symbol: _currencySymbol(currencyCode),
      decimalDigits: 2,
    );
    return formatter.format(value);
  }

  String _currencySymbol(String code) {
    return switch (code.toUpperCase()) {
      'EUR' => '€',
      'USD' => r'$',
      'GBP' => '£',
      _ => code.toUpperCase(),
    };
  }
}

class _NumericText extends StatelessWidget {
  const _NumericText(this.value, {this.isTotal = false});

  final String value;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: GoogleFonts.manrope(
        color: isTotal ? EditorialColors.onSurface : const Color(0xFF20201E),
        fontSize: isTotal ? 15.5 : 14.5,
        fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
        height: 1,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}

class _ExtractedProductsMessage extends StatelessWidget {
  const _ExtractedProductsMessage({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLow.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              color: EditorialColors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.manrope(
              color: EditorialColors.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.38,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            Semantics(
              button: true,
              label: actionLabel,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: EditorialColors.onSurface,
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExtractedProductsSkeleton extends StatelessWidget {
  const _ExtractedProductsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SkeletonHeader(),
        const SizedBox(height: 10),
        for (var index = 0; index < 3; index++) ...[
          const _SkeletonRow(),
          if (index != 2) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SkeletonHeader extends StatelessWidget {
  const _SkeletonHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(flex: 5, child: _SkeletonBlock(widthFactor: 0.42)),
          SizedBox(width: 12),
          Expanded(child: _SkeletonBlock()),
          SizedBox(width: 12),
          Expanded(flex: 2, child: _SkeletonBlock()),
          SizedBox(width: 12),
          Expanded(flex: 2, child: _SkeletonBlock()),
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLow.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        children: [
          Expanded(flex: 5, child: _SkeletonBlock(widthFactor: 0.86)),
          SizedBox(width: 12),
          Expanded(child: _SkeletonBlock()),
          SizedBox(width: 12),
          Expanded(flex: 2, child: _SkeletonBlock()),
          SizedBox(width: 12),
          Expanded(flex: 2, child: _SkeletonBlock()),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({this.widthFactor = 1});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: EditorialColors.surfaceContainerHigh.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
