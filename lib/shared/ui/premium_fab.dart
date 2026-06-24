import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hospi_dash/core/theme/app_motion.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Neobank-grade primary action.
///
/// A charcoal circular control that sits above the floating nav. Press scales
/// to 0.96 with `easeOutCubic` for instant tactile feedback. Drop shadow
/// is a single soft ambient layer (no glow, no border, no Material default).
///
/// The public API ([label], [icon], [onPressed], [heroTag]) is preserved so
/// every existing call site keeps compiling.
class PremiumFAB extends StatefulWidget {
  const PremiumFAB({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.heroTag,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Object? heroTag;

  @override
  State<PremiumFAB> createState() => _PremiumFABState();
}

class _PremiumFABState extends State<PremiumFAB> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final bool disabled = widget.onPressed == null;
    final width = MediaQuery.sizeOf(context).width;
    final size = width >= 600 ? 64.0 : 60.0;
    final iconSize = width >= 600 ? 30.0 : 28.0;

    final Color fill = disabled
        ? EditorialColors.surfaceContainerHigh
        : const Color(0xFF151515);
    final Color ink =
        disabled ? EditorialColors.onSurfaceVariant : EditorialColors.onPrimary;

    final Widget content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        boxShadow: disabled
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x2E000000),
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
      ),
      child: Center(
        child: Icon(
          widget.icon ?? Icons.add_rounded,
          size: iconSize,
          color: ink,
          weight: 800,
        ),
      ),
    );

    final Object tag = widget.heroTag ?? 'premium_fab_${widget.label.hashCode}';

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      hint: widget.label == 'Add' ? 'Open quick actions' : null,
      child: Hero(
        tag: tag,
        createRectTween: (a, b) => MaterialRectArcTween(begin: a, end: b),
        child: GestureDetector(
          onTapDown: (_) {
            if (!disabled) HapticFeedback.lightImpact();
            _setPressed(true);
          },
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _pressed && !disabled ? 0.96 : 1.0,
            duration: _pressed
                ? const Duration(milliseconds: 80)
                : const Duration(milliseconds: 140),
            curve: AppMotion.enter,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
