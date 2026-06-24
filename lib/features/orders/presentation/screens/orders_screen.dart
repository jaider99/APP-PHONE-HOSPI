import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/shared/ui/ui.dart';

/// Orders screen — editorial placeholder for supplier orders.
class OrdersScreen extends ConsumerStatefulWidget {
  final String? orderId;

  const OrdersScreen({super.key, this.orderId});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _filter = 'All';

  static const _filters = <String>['All', 'Pending', 'Confirmed', 'Delivered'];

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      clampContent: false,
      topBar: const AppTopBar(
        eyebrow: 'fulfilment',
        title: 'Orders',
      ),
      body: CustomScrollView(
        slivers: [
          // ── Status filter chips ───────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final label = _filters[i];
                  return CategoryChip(
                    label: label,
                    selected: _filter == label,
                    onTap: () => setState(() => _filter = label),
                  );
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

          // ── Empty state ───────────────────────────────────────────────
          const SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No orders yet',
              message:
                  'Track supplier orders here. Use the New order button to create your first one.',
            ),
          ),
        ],
      ),
    );
  }
}
