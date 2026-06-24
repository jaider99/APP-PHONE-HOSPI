import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:hospi_dash/core/theme/editorial_theme.dart';

class AppBackButton extends StatefulWidget {
  const AppBackButton({
    super.key,
    this.fallbackRoute,
    this.onPressed,
    this.tooltip = 'Back',
    this.semanticLabel = 'Go back',
    this.useCloseIcon = false,
    this.size = 52,
  });

  final String? fallbackRoute;
  final VoidCallback? onPressed;
  final String tooltip;
  final String semanticLabel;
  final bool useCloseIcon;
  final double size;

  @override
  State<AppBackButton> createState() => _AppBackButtonState();
}

class _AppBackButtonState extends State<AppBackButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    HapticFeedback.selectionClick();

    if (widget.onPressed != null) {
      widget.onPressed!();
      return;
    }

    if (context.canPop()) {
      context.pop();
      return;
    }

    final fallbackRoute = widget.fallbackRoute;
    if (fallbackRoute != null && fallbackRoute.isNotEmpty) {
      context.go(fallbackRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final effectiveScale = disableAnimations ? 1.0 : (_pressed ? 0.96 : 1.0);

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(
              child: AnimatedScale(
                scale: effectiveScale,
                duration: disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: EditorialColors.surfaceContainerLowest,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(26, 28, 28, 0.06),
                        blurRadius: 40,
                        offset: Offset(0, 20),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: Icon(
                      widget.useCloseIcon
                          ? Icons.close_rounded
                          : Icons.arrow_back_ios_new_rounded,
                      size: widget.useCloseIcon ? 22 : 18,
                      color: const Color(0xFF151515),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}