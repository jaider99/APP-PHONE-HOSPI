import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/app_colors.dart';

/// Shimmer skeleton loader for loading states
/// Uses AnimatedContainer with alternating opacity for shimmer effect
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  
  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });
  
  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh.withOpacity(_animation.value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// Skeleton for KPI cards
class KpiCardSkeleton extends StatelessWidget {
  const KpiCardSkeleton({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 120,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.04),
            blurRadius: 40,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SkeletonLoader(width: 80, height: 12, borderRadius: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLoader(width: 100, height: 28, borderRadius: 6),
              SizedBox(height: 8),
              SkeletonLoader(width: 60, height: 14, borderRadius: 4),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton for revenue chart
class ChartSkeleton extends StatelessWidget {
  const ChartSkeleton({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.04),
            blurRadius: 40,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonLoader(width: 120, height: 16, borderRadius: 4),
              Row(
                children: [
                  SkeletonLoader(width: 60, height: 28, borderRadius: 14),
                  SizedBox(width: 8),
                  SkeletonLoader(width: 60, height: 28, borderRadius: 14),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(
                12,
                (index) => Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    child: SkeletonLoader(
                      width: double.infinity,
                      height: 40 + (index % 4) * 30,
                      borderRadius: 4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for insight banner
class InsightSkeleton extends StatelessWidget {
  const InsightSkeleton({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.04),
            blurRadius: 40,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          SkeletonLoader(width: 40, height: 40, borderRadius: 20),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(width: double.infinity, height: 14, borderRadius: 4),
                SizedBox(height: 8),
                SkeletonLoader(width: 180, height: 14, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for category list item
class CategoryListSkeleton extends StatelessWidget {
  final int count;
  
  const CategoryListSkeleton({super.key, this.count = 4});
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SkeletonLoader(width: 120, height: 14, borderRadius: 4),
                  Row(
                    children: [
                      const SkeletonLoader(width: 80, height: 16, borderRadius: 4),
                      const SizedBox(width: 8),
                      SkeletonLoader(width: 40, height: 12, borderRadius: 4),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SkeletonLoader(
                width: double.infinity,
                height: 8,
                borderRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for top products list
class TopProductsSkeleton extends StatelessWidget {
  const TopProductsSkeleton({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        5,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              SkeletonLoader(width: 32, height: 32, borderRadius: 8),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(width: 140, height: 14, borderRadius: 4),
                    SizedBox(height: 4),
                    SkeletonLoader(width: 80, height: 12, borderRadius: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for payment pill
class PaymentPillSkeleton extends StatelessWidget {
  const PaymentPillSkeleton({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SkeletonLoader(
          width: double.infinity,
          height: 48,
          borderRadius: 24,
        ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SkeletonLoader(width: 80, height: 32, borderRadius: 16),
            SkeletonLoader(width: 80, height: 32, borderRadius: 16),
            SkeletonLoader(width: 80, height: 32, borderRadius: 16),
          ],
        ),
      ],
    );
  }
}
