import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hospi_dash/core/router/app_router.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/providers/data/models/supplier_intelligence_model.dart';
import 'package:hospi_dash/features/providers/providers/supplier_intelligence_providers.dart';
import 'package:hospi_dash/shared/ui/ui.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SUPPLIERS LIST — editorial pass
// ─────────────────────────────────────────────────────────────────────────────

class ProvidersScreen extends ConsumerStatefulWidget {
  final String? providerId;

  const ProvidersScreen({super.key, this.providerId});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(supplierIntelligenceListProvider);

    return AppScaffold(
      clampContent: false,
      topBar: const AppTopBar(
        eyebrow: 'directory',
        title: 'Suppliers',
      ),
      body: CustomScrollView(
        slivers: [
          // ── Search ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: EditorialColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(EditorialRadius.md),
                  border: Border.all(color: EditorialColors.hairline),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) =>
                      ref.read(supplierSearchQueryProvider.notifier).state = v,
                  style: EditorialTypography.bodyMedium.copyWith(
                    color: EditorialColors.onSurface,
                  ),
                  cursorColor: EditorialColors.accent,
                  decoration: InputDecoration(
                    hintText: 'Search suppliers…',
                    hintStyle: EditorialTypography.bodyMedium.copyWith(
                      color: EditorialColors.onSurfaceVariant,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: EditorialColors.onSurfaceVariant,
                      size: 20,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Supplier count badge ──────────────────────────────────────
          suppliersAsync.maybeWhen(
            data: (list) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: StatusBadge(
                  label:
                      '${list.length} supplier${list.length == 1 ? '' : 's'}',
                  tone: BadgeTone.neutral,
                ),
              ),
            ),
            orElse: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // ── Supplier list ─────────────────────────────────────────────
          suppliersAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: _SuppliersSkeleton(),
            ),
            error: (e, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                message: "We couldn't load your suppliers. Try again.",
                onRetry: () =>
                    ref.invalidate(supplierIntelligenceListProvider),
              ),
            ),
            data: (suppliers) {
              if (suppliers.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No suppliers yet',
                    message:
                        'Upload invoices and your suppliers will appear here automatically.',
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                sliver: SliverToBoxAdapter(
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (int i = 0; i < suppliers.length; i++)
                          _SupplierRow(
                            supplier: suppliers[i],
                            showDivider: i < suppliers.length - 1,
                            onTap: () => context.push(
                              '${AppRoutes.providers}/${suppliers[i].id}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUPPLIER ROW
// ─────────────────────────────────────────────────────────────────────────────

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({
    required this.supplier,
    required this.showDivider,
    required this.onTap,
  });

  final SupplierIntelligence supplier;
  final bool showDivider;
  final VoidCallback onTap;

  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff}d ago';
    if (diff < 30) return '${(diff / 7).floor()}w ago';
    if (diff < 365) return '${(diff / 30).floor()}mo ago';
    return '${(diff / 365).floor()}y ago';
  }

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (supplier.totalOrders > 0) {
      parts.add(
          '${supplier.totalOrders} doc${supplier.totalOrders == 1 ? '' : 's'}');
    }
    if (supplier.lastOrderDate != null) {
      parts.add(_relativeDate(supplier.lastOrderDate!));
    }
    if (supplier.category != null) parts.add(supplier.category!);
    final secondary = parts.join(' · ');

    final trailing = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (supplier.totalSpent > 0)
          FinancialValue(
            amount: supplier.totalSpent,
            size: MetricSize.small,
            locale: 'es_ES',
            symbol: '€',
          )
        else
          Text(
            '—',
            style: EditorialTypography.bodyMedium.copyWith(
              color: EditorialColors.onSurfaceVariant,
            ),
          ),
        if (supplier.hasTrend) ...[
          const SizedBox(height: 4),
          PriceTrendIndicator(
            deltaPercent: _trendPct(supplier),
            upIsGood: false,
          ),
        ],
      ],
    );

    final container = Container(
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: EditorialColors.hairline),
              ),
            )
          : null,
      child: DataRowItem(
        leading: _SupplierAvatar(initials: supplier.initials),
        primary: supplier.name,
        secondary: secondary.isEmpty ? null : secondary,
        trailing: trailing,
        onTap: onTap,
        dividerBelow: false,
      ),
    );

    return container;
  }

  double _trendPct(SupplierIntelligence s) {
    if (s.priorMonthSpent == 0) return 0;
    return ((s.currentMonthSpent - s.priorMonthSpent) / s.priorMonthSpent) *
        100;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AVATAR (flat tonal square)
// ─────────────────────────────────────────────────────────────────────────────

class _SupplierAvatar extends StatelessWidget {
  const _SupplierAvatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainer,
        borderRadius: BorderRadius.circular(EditorialRadius.sm),
        border: Border.all(color: EditorialColors.hairline),
      ),
      child: Center(
        child: Text(
          initials,
          style: EditorialTypography.labelLarge.copyWith(
            color: EditorialColors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SKELETON
// ─────────────────────────────────────────────────────────────────────────────

class _SuppliersSkeleton extends StatelessWidget {
  const _SuppliersSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        children: [
          for (int i = 0; i < 6; i++) ...[
            SkeletonBlock.box(width: double.infinity, height: 64),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
