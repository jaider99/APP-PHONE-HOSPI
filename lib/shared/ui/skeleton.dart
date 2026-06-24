import 'package:flutter/material.dart';

import 'package:hospi_dash/core/theme/app_motion.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

/// Single skeleton primitive. Construct directly for arbitrary shapes, or use
/// the convenience constructors [SkeletonBlock.line], [SkeletonBlock.box],
/// [SkeletonBlock.circle].
///
/// Animation is a slow opacity pulse — no shimmer sweep, no gradient.
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  const SkeletonBlock.line({
    super.key,
    this.width = double.infinity,
    this.height = 12,
  })  : borderRadius = const BorderRadius.all(Radius.circular(4)),
        shape = BoxShape.rectangle;

  const SkeletonBlock.box({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius =
        const BorderRadius.all(Radius.circular(EditorialRadius.sm)),
  }) : shape = BoxShape.rectangle;

  const SkeletonBlock.circle({super.key, required double size})
      : width = size,
        height = size,
        borderRadius = null,
        shape = BoxShape.circle;

  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AppMotion.skeletonPulse,
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: EditorialColors.surfaceContainer,
          shape: widget.shape,
          borderRadius:
              widget.shape == BoxShape.rectangle ? widget.borderRadius : null,
        ),
      ),
    );
  }
}
