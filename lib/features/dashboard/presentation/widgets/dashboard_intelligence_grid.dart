import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hospi_dash/core/theme/app_spacing.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/features/dashboard/data/models/dashboard_grid_metrics.dart';
import 'package:intl/intl.dart';

class DashboardIntelligenceGrid extends StatelessWidget {
  const DashboardIntelligenceGrid({
    required this.metrics,
    required this.currencySymbol,
    required this.onExpensesTap,
    required this.onResultsTap,
    required this.onSalesTap,
    required this.onDocumentsTap,
    super.key,
    this.onRetry,
  });

  final AsyncValue<DashboardGridMetrics?> metrics;
  final String currencySymbol;
  final VoidCallback onExpensesTap;
  final VoidCallback onResultsTap;
  final VoidCallback onSalesTap;
  final VoidCallback onDocumentsTap;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final value = metrics.valueOrNull;
    final isLoading = metrics.isLoading && value == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: metrics.when(
        loading: () => const _DashboardGridSkeleton(),
        error: (_, __) => _DashboardGridError(onRetry: onRetry),
        data: (data) {
          if (isLoading || data == null) return const _DashboardGridSkeleton();
          return _DashboardGridContent(
            metrics: data,
            currencySymbol: currencySymbol,
            onExpensesTap: onExpensesTap,
            onResultsTap: onResultsTap,
            onSalesTap: onSalesTap,
            onDocumentsTap: onDocumentsTap,
          );
        },
      ),
    );
  }
}

class _DashboardGridContent extends StatelessWidget {
  const _DashboardGridContent({
    required this.metrics,
    required this.currencySymbol,
    required this.onExpensesTap,
    required this.onResultsTap,
    required this.onSalesTap,
    required this.onDocumentsTap,
  });

  final DashboardGridMetrics metrics;
  final String currencySymbol;
  final VoidCallback onExpensesTap;
  final VoidCallback onResultsTap;
  final VoidCallback onSalesTap;
  final VoidCallback onDocumentsTap;

  @override
  Widget build(BuildContext context) {
    final resultTone = metrics.resultTotal > 0
        ? _TileTone.positive
        : metrics.resultTotal < 0
            ? _TileTone.negative
            : _TileTone.neutral;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth < 340 ? 12.0 : 14.0;
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _AnimatedTileShell(
                    index: 0,
                    child: _DashboardGridTile(
                      icon: Icons.receipt_long_outlined,
                      label: 'Expenses',
                      value: _formatMoney(metrics.expensesTotal),
                      meta: metrics.expensesTotal == 0
                          ? 'Scan first expense'
                          : _expenseTrendLabel(metrics),
                      status: metrics.vatTotal > 0
                          ? 'VAT ${_formatMoney(metrics.vatTotal)}'
                          : null,
                      onTap: onExpensesTap,
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: _AnimatedTileShell(
                    index: 1,
                    child: _DashboardGridTile(
                      icon: Icons.insights_outlined,
                      label: 'Results',
                      value: metrics.hasSales
                          ? _formatMoney(metrics.resultTotal)
                          : metrics.expensesTotal > 0
                              ? _formatMoney(metrics.resultTotal)
                              : _formatMoney(0),
                      meta: metrics.hasSales
                          ? 'Sales minus expenses'
                          : metrics.expensesTotal > 0
                              ? 'No sales imported'
                              : 'Waiting for data',
                      status: switch (resultTone) {
                        _TileTone.positive => 'Positive',
                        _TileTone.negative => 'Negative',
                        _TileTone.neutral => null,
                      },
                      tone: resultTone,
                      onTap: onResultsTap,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: gap),
            Row(
              children: [
                Expanded(
                  child: _AnimatedTileShell(
                    index: 2,
                    child: _DashboardGridTile(
                      icon: Icons.trending_up_rounded,
                      label: 'Sales',
                      value: _formatMoney(metrics.salesTotal),
                      meta: metrics.salesRecordCount > 0
                          ? '${metrics.salesRecordCount} record${metrics.salesRecordCount == 1 ? '' : 's'}'
                          : 'Import sales',
                      onTap: onSalesTap,
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: _AnimatedTileShell(
                    index: 3,
                    child: _DashboardGridTile(
                      icon: Icons.description_outlined,
                      label: 'Documents',
                      value: '${metrics.processedDocumentsCount} processed',
                      meta: _documentsMeta(metrics),
                      status: metrics.failedDocumentsCount > 0
                          ? '${metrics.failedDocumentsCount} failed'
                          : metrics.pendingDocumentsCount > 0
                              ? '${metrics.pendingDocumentsCount} extracting'
                              : null,
                      tone: metrics.failedDocumentsCount > 0
                          ? _TileTone.negative
                          : _TileTone.neutral,
                      onTap: onDocumentsTap,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _formatMoney(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'de_DE',
      symbol: currencySymbol,
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  String _expenseTrendLabel(DashboardGridMetrics metrics) {
    final change = metrics.expensesChangePercent;
    if (change == null || change.abs() < 0.1) return 'Same as last period';
    final sign = change > 0 ? '+' : '-';
    return '$sign${change.abs().toStringAsFixed(1)}% vs last period';
  }

  String _documentsMeta(DashboardGridMetrics metrics) {
    if (metrics.failedDocumentsCount > 0) {
      return '${metrics.failedDocumentsCount} need review';
    }
    if (metrics.pendingDocumentsCount > 0) {
      return '${metrics.pendingDocumentsCount} extracting';
    }
    if (metrics.documentsCount == 0) return 'Upload document';
    return metrics.periodLabel;
  }
}

class _AnimatedTileShell extends StatelessWidget {
  const _AnimatedTileShell({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = (index * 30).clamp(0, 120);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 190 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final delayFraction = delay / (190 + delay);
        final progress = delayFraction >= 1
            ? 1.0
            : ((value - delayFraction) / (1 - delayFraction)).clamp(0.0, 1.0);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * 8),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _DashboardGridTile extends StatefulWidget {
  const _DashboardGridTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.meta,
    required this.onTap,
    this.status,
    this.tone = _TileTone.neutral,
  });

  final IconData icon;
  final String label;
  final String value;
  final String meta;
  final String? status;
  final VoidCallback onTap;
  final _TileTone tone;

  @override
  State<_DashboardGridTile> createState() => _DashboardGridTileState();
}

class _DashboardGridTileState extends State<_DashboardGridTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final toneColor = switch (widget.tone) {
      _TileTone.positive => EditorialColors.success,
      _TileTone.negative => EditorialColors.error,
      _TileTone.neutral => EditorialColors.onSurfaceVariant,
    };

    return Semantics(
      button: true,
      label: '${widget.label}, ${widget.value}, ${widget.meta}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.975 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AspectRatio(
            aspectRatio: 1.04,
            child: Container(
              constraints: const BoxConstraints(minHeight: 132),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: EditorialColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A1C1C).withValues(alpha: 0.055),
                    blurRadius: 34,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        widget.icon,
                        color: EditorialColors.primary,
                        size: 22,
                      ),
                      const Spacer(),
                      if (widget.status != null)
                        Flexible(
                          child: Text(
                            widget.status!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: GoogleFonts.manrope(
                              color: toneColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      widget.value,
                      key: ValueKey(widget.value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: widget.tone == _TileTone.neutral
                            ? EditorialColors.onSurface
                            : toneColor,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    widget.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      color: EditorialColors.onSurfaceVariant,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      color: EditorialColors.onSurface,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardGridSkeleton extends StatelessWidget {
  const _DashboardGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth < 340 ? 12.0 : 14.0;
        return Column(
          children: [
            Row(
              children: [
                const Expanded(child: _SkeletonTile()),
                SizedBox(width: gap),
                const Expanded(child: _SkeletonTile()),
              ],
            ),
            SizedBox(height: gap),
            Row(
              children: [
                const Expanded(child: _SkeletonTile()),
                SizedBox(width: gap),
                const Expanded(child: _SkeletonTile()),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.04,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: EditorialColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A1C1C).withValues(alpha: 0.04),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBlock(width: 22, height: 22),
            Spacer(),
            _SkeletonBlock(width: 70, height: 12),
            SizedBox(height: 10),
            _SkeletonBlock(width: 92, height: 18),
            SizedBox(height: 10),
            _SkeletonBlock(width: 110, height: 10),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerHigh.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _DashboardGridError extends StatelessWidget {
  const _DashboardGridError({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 156),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1C1C).withValues(alpha: 0.045),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Dashboard metrics unavailable',
            style: GoogleFonts.manrope(
              color: EditorialColors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try again when the connection is stable.',
            style: GoogleFonts.manrope(
              color: EditorialColors.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: EditorialColors.onSurface,
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                'Try again',
                style: GoogleFonts.manrope(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _TileTone { neutral, positive, negative }
