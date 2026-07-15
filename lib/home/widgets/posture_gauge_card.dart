import 'dart:math' as math;

import 'package:correctv1/home/widgets/staggered_fade_slide.dart';
import 'package:correctv1/home/widgets/surface_card.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:flutter/material.dart';

const _kPrimaryGreen = AppTheme.goodPostureEnd;
const _kBadPostureRed = AppTheme.destructive;

class PostureGaugeCard extends StatelessWidget {
  final double postureAngle;
  final String postureStatus;
  final bool isBadPosture;
  final int difficultyDeg;
  final Animation<double> controller;

  const PostureGaugeCard({
    super.key,
    required this.postureAngle,
    required this.postureStatus,
    required this.isBadPosture,
    required this.difficultyDeg,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = isBadPosture ? _kBadPostureRed : _kPrimaryGreen;
    final clampedAngle = postureAngle.clamp(-90.0, 90.0);

    return HomeSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Real-time Posture',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              height: 220,
              width: 220,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 130),
                curve: Curves.linear,
                tween: Tween<double>(end: clampedAngle),
                builder: (context, value, child) {
                  return CustomPaint(
                    painter: PostureGaugePainter(
                      angle: value,
                      accentColor: accentColor,
                      difficultyDeg: difficultyDeg,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          StaggeredFadeSlide(
            controller: controller,
            delayMs: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accentColor.withValues(alpha: 0.9), accentColor],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      'Posture Status: $postureStatus',
                      key: ValueKey(postureStatus),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Bad posture above ${difficultyDeg}°',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PostureGaugePainter extends CustomPainter {
  final double angle;
  final Color accentColor;
  final int difficultyDeg;

  PostureGaugePainter({
    required this.angle,
    required this.accentColor,
    required this.difficultyDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 14.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw background ring (full circle)
    paint.color = const Color(0xFFE5E7EB);
    canvas.drawCircle(center, radius, paint);

    // Draw division markers at 0°, 90°, and -90°
    final markerPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw marker at top (0°)
    final topMarker = Offset(center.dx, center.dy - radius);
    canvas.drawLine(
      Offset(topMarker.dx - 8, topMarker.dy),
      Offset(topMarker.dx + 8, topMarker.dy),
      markerPaint,
    );

    // Draw marker at right (90°)
    final rightMarker = Offset(center.dx + radius, center.dy);
    canvas.drawLine(
      Offset(rightMarker.dx, rightMarker.dy - 8),
      Offset(rightMarker.dx, rightMarker.dy + 8),
      markerPaint,
    );

    // Draw marker at left (-90°)
    final leftMarker = Offset(center.dx - radius, center.dy);
    canvas.drawLine(
      Offset(leftMarker.dx, leftMarker.dy - 8),
      Offset(leftMarker.dx, leftMarker.dy + 8),
      markerPaint,
    );

    // Clamp angle to -90 to 90 range
    final clampedAngle = angle.clamp(-90.0, 90.0);

    // Convert angle to radians
    final angleRad = clampedAngle * math.pi / 180.0;

    // Start angle is at the top (-π/2 in canvas coordinates)
    const startAngle = -math.pi / 2;

    // Calculate sweep angle based on positive or negative angle
    // In canvas.drawArc: positive sweep = clockwise, negative sweep = anticlockwise
    double sweepAngle;
    if (clampedAngle >= 0) {
      // Positive angle: 0 to 90, draw clockwise (right side)
      // Sweep from top (0°) to the right
      sweepAngle = angleRad; // Positive sweep = clockwise
    } else {
      // Negative angle: 0 to -90, draw anticlockwise (left side)
      // Sweep from top (0°) to the left (negative direction)
      sweepAngle =
          angleRad; // angleRad is already negative, so this gives anticlockwise
    }

    // Draw the arc with gradient
    final gradient = LinearGradient(
      colors: [accentColor.withValues(alpha: 0.8), accentColor],
    ).createShader(Rect.fromCircle(center: center, radius: radius));

    paint.shader = gradient;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );

    // Draw needle/indicator at the current angle position
    final needleRadius = radius;
    final needleAngle = startAngle + sweepAngle;
    final needleEnd = Offset(
      center.dx + needleRadius * math.cos(needleAngle),
      center.dy + needleRadius * math.sin(needleAngle),
    );

    final needlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw shadow for depth
    canvas.drawCircle(
      needleEnd.translate(0, 2),
      7,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Draw needle circle
    canvas.drawCircle(needleEnd, 7, needlePaint);
    canvas.drawCircle(
      needleEnd,
      7,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Draw red threshold marker at the difficulty angle (bad-posture cutoff)
    final thresholdRad = difficultyDeg.abs() * math.pi / 180.0;
    final thresholdAngle = startAngle + thresholdRad;
    final outerRadius = radius + strokeWidth / 2 + 10;
    final thresholdPoint = Offset(
      center.dx + outerRadius * math.cos(thresholdAngle),
      center.dy + outerRadius * math.sin(thresholdAngle),
    );
    final trianglePath = Path();
    const triSize = 9.0;
    final dirX = math.cos(thresholdAngle);
    final dirY = math.sin(thresholdAngle);
    final tipX = thresholdPoint.dx - dirX * (triSize * 0.6);
    final tipY = thresholdPoint.dy - dirY * (triSize * 0.6);
    final baseX = thresholdPoint.dx + dirX * (triSize * 0.6);
    final baseY = thresholdPoint.dy + dirY * (triSize * 0.6);
    final perpX = -dirY * triSize * 0.6;
    final perpY = dirX * triSize * 0.6;

    trianglePath.moveTo(tipX, tipY);
    trianglePath.lineTo(baseX + perpX, baseY + perpY);
    trianglePath.lineTo(baseX - perpX, baseY - perpY);
    trianglePath.close();

    canvas.drawPath(
      trianglePath,
      Paint()
        ..color = AppTheme.destructive
        ..style = PaintingStyle.fill,
    );

    // Draw angle value in center (as integer)
    final valuePainter = TextPainter(
      text: TextSpan(
        text: "${clampedAngle.round()}°",
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w600,
          color: accentColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    valuePainter.layout();

    final labelPainter = TextPainter(
      text: const TextSpan(
        text: 'Angle',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFF94A3B8),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final totalHeight = valuePainter.height + 6 + labelPainter.height;
    final startY = center.dy - totalHeight / 2;

    valuePainter.paint(
      canvas,
      Offset(center.dx - valuePainter.width / 2, startY),
    );
    labelPainter.paint(
      canvas,
      Offset(
        center.dx - labelPainter.width / 2,
        startY + valuePainter.height + 6,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is PostureGaugePainter &&
        (oldDelegate.angle != angle ||
            oldDelegate.accentColor != accentColor ||
            oldDelegate.difficultyDeg != difficultyDeg);
  }
}
