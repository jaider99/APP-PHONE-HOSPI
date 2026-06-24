import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

class ReviewNotificationButton extends StatefulWidget {
  const ReviewNotificationButton({
    required this.openCount,
    required this.onTap,
    super.key,
  });

  final int openCount;
  final VoidCallback onTap;

  @override
  State<ReviewNotificationButton> createState() =>
      _ReviewNotificationButtonState();
}

class _ReviewNotificationButtonState extends State<ReviewNotificationButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = widget.openCount > 0;
    final label = hasItems
        ? 'Review Center. ${widget.openCount} items need review.'
        : 'Review Center. No items need review.';

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: hasItems ? '${widget.openCount} items need review' : 'All clear',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            HapticFeedback.selectionClick();
            _setPressed(true);
          },
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: SizedBox.square(
              dimension: 44,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const PremiumBellIcon(
                    size: 25,
                    color: EditorialColors.primary,
                  ),
                  if (hasItems)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: _ReviewCountBadge(count: widget.openCount),
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

class PremiumBellIcon extends StatelessWidget {
  const PremiumBellIcon({
    super.key,
    this.size = 24,
    this.color = const Color(0xFF151515),
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PremiumBellPainter(color: color),
    );
  }
}

class _PremiumBellPainter extends CustomPainter {
  const _PremiumBellPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final width = size.width;
    final height = size.height;

    final bell = Path()
      ..moveTo(width * 0.20, height * 0.74)
      ..cubicTo(
        width * 0.31,
        height * 0.63,
        width * 0.30,
        height * 0.49,
        width * 0.32,
        height * 0.36,
      )
      ..cubicTo(
        width * 0.35,
        height * 0.18,
        width * 0.48,
        height * 0.10,
        width * 0.50,
        height * 0.10,
      )
      ..cubicTo(
        width * 0.52,
        height * 0.10,
        width * 0.65,
        height * 0.18,
        width * 0.68,
        height * 0.36,
      )
      ..cubicTo(
        width * 0.70,
        height * 0.49,
        width * 0.69,
        height * 0.63,
        width * 0.80,
        height * 0.74,
      )
      ..lineTo(width * 0.20, height * 0.74);

    canvas.drawPath(bell, stroke);

    final clapper = Path()
      ..moveTo(width * 0.42, height * 0.86)
      ..quadraticBezierTo(width * 0.50, height * 0.93, width * 0.58, height * 0.86);
    canvas.drawPath(clapper, stroke);
  }

  @override
  bool shouldRepaint(covariant _PremiumBellPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ReviewCountBadge extends StatelessWidget {
  const _ReviewCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : count.toString();

    return Container(
      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: EditorialColors.primary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: EditorialColors.background,
          width: 1.5,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          color: EditorialColors.onPrimary,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
