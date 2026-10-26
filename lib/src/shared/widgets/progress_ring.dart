import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A ring that fills clockwise from the top, for goal and debt progress.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.value,
    required this.color,
    required this.trackColor,
    this.size = 52,
    this.strokeWidth = 6,
    this.semanticsLabel,
    this.child,
    super.key,
  });

  /// From 0 to 1; values outside are clamped.
  final double value;
  final Color color;
  final Color trackColor;
  final double size;
  final double strokeWidth;
  final String? semanticsLabel;

  /// Shown in the middle, such as a percentage.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            value: value.clamp(0, 1).toDouble(),
            color: color,
            trackColor: trackColor,
            strokeWidth: strokeWidth,
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = trackColor);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        stroke..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
