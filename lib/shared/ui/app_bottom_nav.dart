import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:hospi_dash/core/theme/app_motion.dart';

/// Floating glass navigation bar.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.hasCenterFab = true,
    super.key,
  }) : assert(items.length == 4, 'AppBottomNav supports exactly 4 items');

  final List<AppBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool hasCenterFab;

  static const double _barHeight = 70;
  static const double _centerGap = 84;
  static const double _hMargin = 20;
  static const double _vMargin = 14;

  @override
  Widget build(BuildContext context) {
    if (!hasCenterFab) {
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _hMargin,
              vertical: _vMargin,
            ),
            child: SizedBox(
              height: _barHeight,
              child: _GlassNavSegment(
                children: [
                  for (int i = 0; i < items.length; i++)
                    _NavCell(
                      item: items[i],
                      selected: currentIndex == i,
                      onTap: () => onTap(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return _CenterGapHitTestPassThrough(
      gapWidth: _centerGap + 12,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _hMargin,
              vertical: _vMargin,
            ),
            child: SizedBox(
              height: _barHeight,
              child: Row(
                children: [
                  Expanded(
                    child: _GlassNavSegment(
                      children: [
                        _NavCell(
                          item: items[0],
                          selected: currentIndex == 0,
                          onTap: () => onTap(0),
                        ),
                        _NavCell(
                          item: items[1],
                          selected: currentIndex == 1,
                          onTap: () => onTap(1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: _centerGap),
                  Expanded(
                    child: _GlassNavSegment(
                      children: [
                        _NavCell(
                          item: items[2],
                          selected: currentIndex == 2,
                          onTap: () => onTap(2),
                        ),
                        _NavCell(
                          item: items[3],
                          selected: currentIndex == 3,
                          onTap: () => onTap(3),
                        ),
                      ],
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

class _CenterGapHitTestPassThrough extends SingleChildRenderObjectWidget {
  const _CenterGapHitTestPassThrough({
    required this.gapWidth,
    required super.child,
  });

  final double gapWidth;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCenterGapHitTestPassThrough(gapWidth);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCenterGapHitTestPassThrough renderObject,
  ) {
    renderObject.gapWidth = gapWidth;
  }
}

class _RenderCenterGapHitTestPassThrough extends RenderProxyBox {
  _RenderCenterGapHitTestPassThrough(this._gapWidth);

  double _gapWidth;

  set gapWidth(double value) {
    if (_gapWidth == value) return;
    _gapWidth = value;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final center = size.width / 2;
    final halfGap = _gapWidth / 2;
    final insideCenterGap =
        position.dx >= center - halfGap && position.dx <= center + halfGap;
    if (insideCenterGap) return false;
    return super.hitTest(result, position: position);
  }
}

class AppBottomNavItem {
  const AppBottomNavItem({
    required this.icon,
    required this.label,
    this.activeIcon,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;
}

class _GlassNavSegment extends StatelessWidget {
  const _GlassNavSegment({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(999)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A151515),
            blurRadius: 44,
            spreadRadius: -8,
            offset: Offset(0, 24),
          ),
          BoxShadow(
            color: Color(0x0D151515),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppBottomNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected
      ? const Color(0xFF151515)
      : const Color(0xFF777777);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Center(
            child: AnimatedScale(
              scale: selected ? 1.05 : 1,
              duration: AppMotion.fast,
              curve: AppMotion.enter,
              child: Icon(
                selected ? (item.activeIcon ?? item.icon) : item.icon,
                size: 28,
                color: color,
                weight: selected ? 500 : 400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
