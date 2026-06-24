import 'package:flutter/material.dart';

import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Flat editorial card.
///
/// Originally a soft "ethereal" floating surface. Now collapsed to the
/// project-wide editorial language: hairline border, no shadow, modest radius.
/// Every dashboard card that imports this widget inherits the new look
/// automatically.
class EtherealCard extends StatelessWidget {
  const EtherealCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.onTap,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ??
        const BorderRadius.all(Radius.circular(EditorialRadius.lg));

    final card = Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor ?? EditorialColors.surfaceContainerLowest,
        borderRadius: radius,
        border: Border.all(
          color: EditorialColors.hairline,
          width: 1,
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: card,
      );
    }

    return card;
  }
}

/// Quiet floating chip surface (kept for back-compat; flat now).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ??
        const BorderRadius.all(Radius.circular(EditorialRadius.full));
    return Container(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainerLowest,
        borderRadius: radius,
        border: Border.all(
          color: EditorialColors.hairline,
          width: 1,
        ),
      ),
      child: child,
    );
  }
}

/// Tonal section container (kept for back-compat; flat now).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: EditorialColors.surfaceContainer,
        borderRadius: const BorderRadius.all(
          Radius.circular(EditorialRadius.lg),
        ),
      ),
      child: child,
    );
  }
}
