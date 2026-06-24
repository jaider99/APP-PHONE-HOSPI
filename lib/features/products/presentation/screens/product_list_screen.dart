import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/shared/ui/ui.dart';

import '../../data/models/product_intelligence_summary_model.dart';
import '../../providers/product_providers.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      ref.read(productSearchQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productIntelligenceProvider);
    final categoriesAsync = ref.watch(productCategoriesProvider);
    final selectedCategory = ref.watch(productCategoryFilterProvider);
    final selectedFilter = ref.watch(productCatalogueFilterProvider);

    return AppScaffold(
      clampContent: false,
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header(),
            _FadeUp(
              delay: const Duration(milliseconds: 40),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _pageHorizontalPadding(context),
                  18,
                  _pageHorizontalPadding(context),
                  16,
                ),
                child: _SearchBar(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                ),
              ),
            ),
            categoriesAsync.maybeWhen(
              data: (categories) => _FadeUp(
                delay: const Duration(milliseconds: 80),
                child: _FilterRail(
                  categories: categories,
                  selectedCategory: selectedCategory,
                  selectedFilter: selectedFilter,
                  onAll: () {
                    ref.read(productCategoryFilterProvider.notifier).state =
                        null;
                    ref.read(productCatalogueFilterProvider.notifier).state =
                        ProductCatalogueFilter.all;
                  },
                  onCategory: (category) {
                    ref.read(productCategoryFilterProvider.notifier).state =
                        category;
                    ref.read(productCatalogueFilterProvider.notifier).state =
                        ProductCatalogueFilter.all;
                  },
                  onFilter: (filter) {
                    ref.read(productCategoryFilterProvider.notifier).state =
                        null;
                    ref.read(productCatalogueFilterProvider.notifier).state =
                        filter;
                  },
                ),
              ),
              orElse: () => const SizedBox(height: 42),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: productsAsync.when(
                loading: () => const _LoadingList(),
                error: (error, stackTrace) => ErrorState(
                  title: 'Products unavailable',
                  message: 'We could not load product intelligence. Try again.',
                  onRetry: () => ref.invalidate(productIntelligenceProvider),
                ),
                data: (products) {
                  if (products.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No products yet',
                      message:
                          'Upload an invoice and HospiDash will build your product catalogue.',
                    );
                  }
                  return _ProductIntelligenceList(products: products);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _pageHorizontalPadding(context),
        28,
        _pageHorizontalPadding(context),
        8,
      ),
      child: _FadeUp(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Products',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFF1B1B1B),
                fontSize: 32,
                height: 1.15,
                letterSpacing: -0.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Price intelligence & stock signals',
              style: GoogleFonts.manrope(
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4C4546),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1C1C).withValues(alpha: 0.05),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            color: Color(0xFF7E7576),
            size: 23,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textAlignVertical: TextAlignVertical.center,
              style: GoogleFonts.manrope(
                color: const Color(0xFF1B1B1B),
                fontSize: 16,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: const Color(0xFF1B1B1B),
              decoration: InputDecoration(
                hintText: 'Search products...',
                hintStyle: GoogleFonts.manrope(
                  color: const Color(0xFF7E7576),
                  fontSize: 16,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return AnimatedOpacity(
                duration: disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                opacity: 1,
                child: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: const Color(0xFF7E7576),
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterRail extends StatelessWidget {
  const _FilterRail({
    required this.categories,
    required this.selectedCategory,
    required this.selectedFilter,
    required this.onAll,
    required this.onCategory,
    required this.onFilter,
  });

  final List<String> categories;
  final String? selectedCategory;
  final ProductCatalogueFilter selectedFilter;
  final VoidCallback onAll;
  final ValueChanged<String> onCategory;
  final ValueChanged<ProductCatalogueFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final orderedCategories = _orderedCategories(categories);
    final chips = <Widget>[
      _FilterChipButton(
        label: 'All',
        selected: selectedCategory == null &&
            selectedFilter == ProductCatalogueFilter.all,
        onTap: onAll,
      ),
      for (final category in orderedCategories)
        _FilterChipButton(
          label: category,
          selected: selectedCategory == category,
          onTap: () => onCategory(category),
        ),
      _FilterChipButton(
        label: 'Uncategorized',
        selected: selectedFilter == ProductCatalogueFilter.uncategorized,
        onTap: () => onFilter(ProductCatalogueFilter.uncategorized),
      ),
      _FilterChipButton(
        label: 'Price changes',
        selected: selectedFilter == ProductCatalogueFilter.priceChanges,
        onTap: () => onFilter(ProductCatalogueFilter.priceChanges),
      ),
      _FilterChipButton(
        label: 'Needs review',
        selected: selectedFilter == ProductCatalogueFilter.needsReview,
        onTap: () => onFilter(ProductCatalogueFilter.needsReview),
      ),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: _pageHorizontalPadding(context)),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }

  List<String> _orderedCategories(List<String> source) {
    const priority = [
      'Drinks',
      'Raw Materials',
      'Cleaning',
      'Consumables',
    ];
    final seen = <String>{};
    final result = <String>[];
    for (final category in priority) {
      if (source.contains(category) && seen.add(category)) result.add(category);
    }
    for (final category in source) {
      if (seen.add(category)) result.add(category);
    }
    return result;
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          height: 44,
          duration: disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF151515) : const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                color: selected ? Colors.white : const Color(0xFF4C4546),
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductIntelligenceList extends StatelessWidget {
  const _ProductIntelligenceList({required this.products});

  final List<ProductIntelligenceSummaryModel> products;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        _pageHorizontalPadding(context),
        0,
        _pageHorizontalPadding(context),
        120,
      ),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _FadeUp(
        delay: Duration(milliseconds: 120 + (index.clamp(0, 8) * 28)),
        child: _ProductIntelligenceCard(summary: products[index]),
      ),
    );
  }
}

double _pageHorizontalPadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 360) return 20;
  if (width >= 600) return 32;
  return 24;
}

class _ProductIntelligenceCard extends StatefulWidget {
  const _ProductIntelligenceCard({required this.summary});

  final ProductIntelligenceSummaryModel summary;

  @override
  State<_ProductIntelligenceCard> createState() =>
      _ProductIntelligenceCardState();
}

class _ProductIntelligenceCardState extends State<_ProductIntelligenceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final scale = !disableAnimations && _pressed ? 0.97 : 1.0;

    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      scale: scale,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () => context.push('/products/${summary.id}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _pressed ? const Color(0xFFF7F7F7) : Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: EditorialShadows.whisper,
          ),
          child: Row(
            children: [
              _InitialsAvatar(name: summary.name),
              const SizedBox(width: 18),
              Expanded(child: _ProductIdentity(summary: summary)),
              const SizedBox(width: 12),
              _PriceSignal(summary: summary),
            ],
          ),
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: const BoxDecoration(
        color: Color(0xFFE8E8E8),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: EditorialTypography.labelLarge.copyWith(
          color: const Color(0xFF4C4546),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '--';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _ProductIdentity extends StatelessWidget {
  const _ProductIdentity({required this.summary});

  final ProductIntelligenceSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          summary.name,
          style: EditorialTypography.titleLarge.copyWith(
            color: const Color(0xFF1B1B1B),
            fontSize: 19,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Text(
          _contextLine(summary),
          style: EditorialTypography.bodyMedium.copyWith(
            color: const Color(0xFF4C4546),
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (summary.needsReview || _lowStock(summary)) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (summary.needsReview)
                const _SignalBadge(
                  label: 'Needs review',
                  tone: _SignalTone.warning,
                ),
              if (_lowStock(summary))
                const _SignalBadge(label: 'Low', tone: _SignalTone.error),
            ],
          ),
        ],
      ],
    );
  }

  String _contextLine(ProductIntelligenceSummaryModel summary) {
    final category = summary.category ?? 'Uncategorized';
    if (summary.supplierName != null && summary.supplierName!.isNotEmpty) {
      return '$category - ${summary.supplierName}';
    }
    if (summary.lastPurchasedAt != null) {
      return '$category - ${DateFormat('d MMM').format(summary.lastPurchasedAt!)}';
    }
    return category;
  }

  bool _lowStock(ProductIntelligenceSummaryModel summary) {
    final current = summary.product.currentStock;
    final minimum = summary.product.minStockLevel;
    if (current == null || minimum == null) return false;
    return current <= minimum;
  }
}

class _PriceSignal extends StatelessWidget {
  const _PriceSignal({required this.summary});

  final ProductIntelligenceSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    final latestPrice = summary.latestPrice;
    if (latestPrice == null) {
      return const SizedBox(
        width: 94,
        child: Text(
          'No price yet',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontFamily: EditorialTypography.bodyFont,
            fontSize: 13,
            color: Color(0xFF4C4546),
          ),
        ),
      );
    }

    final variation = summary.variationVsPreviousPercent;
    final tone = _toneFor(summary);
    final price = NumberFormat.currency(
      locale: 'en_US',
      symbol: '${summary.currency ?? 'EUR'} ',
      decimalDigits: 2,
    ).format(latestPrice);

    return SizedBox(
      width: 106,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            price,
            textAlign: TextAlign.right,
            style: EditorialTypography.currencySmall.copyWith(
              color: const Color(0xFF1B1B1B),
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          if (variation == null)
            const _SignalBadge(label: 'New', tone: _SignalTone.neutral)
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconFor(summary.direction), size: 15, color: tone.color),
                const SizedBox(width: 3),
                Text(
                  '${variation.abs().toStringAsFixed(1)}%',
                  style: EditorialTypography.percentageChange.copyWith(
                    color: tone.color,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          if (_showSeverity(summary)) ...[
            const SizedBox(height: 7),
            _SignalBadge(label: _severityLabel(summary), tone: tone.tone),
          ],
        ],
      ),
    );
  }

  _SignalToneSpec _toneFor(ProductIntelligenceSummaryModel summary) {
    if (summary.needsReview) {
      return const _SignalToneSpec(Color(0xFFB07A1A), _SignalTone.warning);
    }
    switch (summary.direction) {
      case ProductPriceDirection.up:
        return summary.severity == ProductPriceSeverity.critical ||
                summary.severity == ProductPriceSeverity.high
            ? const _SignalToneSpec(Color(0xFFB23A3A), _SignalTone.error)
            : const _SignalToneSpec(Color(0xFF1F8F5C), _SignalTone.success);
      case ProductPriceDirection.down:
        return const _SignalToneSpec(Color(0xFF1F8F5C), _SignalTone.success);
      case ProductPriceDirection.stable:
        return const _SignalToneSpec(Color(0xFF4C4546), _SignalTone.neutral);
      case ProductPriceDirection.unknown:
        return const _SignalToneSpec(Color(0xFF4C4546), _SignalTone.neutral);
    }
  }

  IconData _iconFor(ProductPriceDirection direction) {
    switch (direction) {
      case ProductPriceDirection.up:
        return Icons.arrow_upward_rounded;
      case ProductPriceDirection.down:
        return Icons.arrow_downward_rounded;
      case ProductPriceDirection.stable:
        return Icons.remove_rounded;
      case ProductPriceDirection.unknown:
        return Icons.remove_rounded;
    }
  }

  bool _showSeverity(ProductIntelligenceSummaryModel summary) {
    return summary.needsReview ||
        summary.severity == ProductPriceSeverity.watch ||
        summary.severity == ProductPriceSeverity.high ||
        summary.severity == ProductPriceSeverity.critical;
  }

  String _severityLabel(ProductIntelligenceSummaryModel summary) {
    if (summary.needsReview) return 'Review';
    switch (summary.severity) {
      case ProductPriceSeverity.stable:
        return 'Stable';
      case ProductPriceSeverity.watch:
        return 'Watch';
      case ProductPriceSeverity.high:
        return 'High';
      case ProductPriceSeverity.critical:
        return 'Critical';
      case ProductPriceSeverity.noPrice:
        return 'No price';
    }
  }
}

enum _SignalTone { neutral, success, warning, error }

class _SignalToneSpec {
  const _SignalToneSpec(this.color, this.tone);

  final Color color;
  final _SignalTone tone;
}

class _SignalBadge extends StatelessWidget {
  const _SignalBadge({required this.label, required this.tone});

  final String label;
  final _SignalTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsFor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.$2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: EditorialTypography.labelSmall.copyWith(
          color: colors.$1,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }

  (Color, Color) _colorsFor(_SignalTone tone) {
    switch (tone) {
      case _SignalTone.neutral:
        return (const Color(0xFF4C4546), const Color(0xFFF1F1F1));
      case _SignalTone.success:
        return (const Color(0xFF1F8F5C), const Color(0xFFE6F4EC));
      case _SignalTone.warning:
        return (const Color(0xFF8A5E12), const Color(0xFFFBF1DD));
      case _SignalTone.error:
        return (const Color(0xFFB23A3A), const Color(0xFFFCEAEA));
    }
  }
}

class _FadeUp extends StatelessWidget {
  const _FadeUp({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + delay.inMilliseconds),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final delayed = delay.inMilliseconds == 0
            ? value
            : ((value * (220 + delay.inMilliseconds) - delay.inMilliseconds) /
                    220)
                .clamp(0.0, 1.0);
        return Opacity(
          opacity: delayed,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - delayed)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 120),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, __) => Container(
        height: 112,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
        ),
        child: const Row(
          children: [
            SkeletonBlock.circle(size: 58),
            SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBlock.line(width: 150, height: 16),
                  SizedBox(height: 10),
                  SkeletonBlock.line(width: 210),
                ],
              ),
            ),
            SizedBox(width: 18),
            SkeletonBlock.line(width: 74, height: 16),
          ],
        ),
      ),
    );
  }
}
