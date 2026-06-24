import 'package:flutter/material.dart';

import 'package:hospi_dash/core/theme/app_colors.dart';

class AiProcessingIndicator extends StatefulWidget {
  const AiProcessingIndicator({
    super.key,
    this.size = 30,
  });

  final double size;

  @override
  State<AiProcessingIndicator> createState() => _AiProcessingIndicatorState();
}

class _AiProcessingIndicatorState extends State<AiProcessingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _breathController;
  late final Animation<double> _turns;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _turns = CurvedAnimation(
      parent: _rotationController,
      curve: Curves.easeInOutCubic,
    );
    _opacity = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(
        parent: _breathController,
        curve: Curves.easeInOutSine,
      ),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: RotationTransition(
              turns: _turns,
              child: Icon(
                Icons.sync_rounded,
                size: widget.size * 0.5,
                color: AppColors.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
