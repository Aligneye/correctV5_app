import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Upright-style posture avatar, fully hand-drawn with CustomPainter,
/// traced directly from the reference icon: a floating head (gap, no
/// neck connector) above a torso silhouette with a diagonal crossed-arm
/// band ending in a rounded hand, both with a subtle back-to-front
/// gradient. Body faces left (flipped from the reference). The torso
/// stays planted; the head rounds forward from the shoulder/apex pivot
/// as [liveAngle] rises — matching how people actually slouch. Fill
/// color eases from good to bad-posture color as it crosses
/// [thresholdAngle].
///
/// [liveAngle] is expected to already be an animated/smoothed value (e.g.
/// the frame value from the caller's own TweenAnimationBuilder driving the
/// gauge needle) so this avatar's tilt stays perfectly in sync with it —
/// this widget does not run its own separate animation on top.
class AlignPodPostureAvatar extends StatelessWidget {
  final double liveAngle; // 0-90 degrees from sensor
  final double thresholdAngle; // user's bad-posture cutoff
  final bool isCalibrated;
  final double width;
  final double height;

  const AlignPodPostureAvatar({
    super.key,
    required this.liveAngle,
    required this.thresholdAngle,
    this.isCalibrated = true,
    this.width = 68,
    this.height = 124,
  });

  // Visual tilt scale: keeps the lean readable without looking exaggerated
  // at the sensor's max angle (90°).
  static const double _tiltScale = 0.5;

  static const _goodColor = Color(0xFF01A975);
  static const _badColor = Color(0xFFEF4444);
  static const _disconnectedColor = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final clamped = liveAngle.clamp(0.0, 90.0);
    final threshold = thresholdAngle.clamp(1.0, 90.0);
    // Hard cutoff — no in-between blend. Green until the threshold is
    // reached, then red, same as the ring's own good/bad posture switch.
    final color = !isCalibrated
        ? _disconnectedColor
        : (clamped >= threshold ? _badColor : _goodColor);

    final tiltRad = clamped * math.pi / 180.0 * _tiltScale;

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _PostureFigurePainter(
          tiltRad: tiltRad,
          color: color,
          isCalibrated: isCalibrated,
        ),
      ),
    );
  }
}

class _PostureFigurePainter extends CustomPainter {
  final double tiltRad;
  final Color color;
  final bool isCalibrated;

  _PostureFigurePainter({
    required this.tiltRad,
    required this.color,
    required this.isCalibrated,
  });

  // --- Traced silhouette data ---------------------------------------
  // Points are fractions (fx, fy) of the torso's own bounding box, traced
  // from the reference icon: fx 0→1 spans back-edge to front-edge, fy 0→1
  // spans the torso's top apex to its bottom hem.

  // Plain body: rounded shoulder dome, straight parallel sides, flat
  // bottom — no chest/waist curve, no bulge. _front mirrors _back (fx ->
  // 1 - fx) so both sides stay perfectly symmetric.
  static const List<Offset> _back = [
    Offset(0.4300, 0.0000),
    Offset(0.2600, 0.0150),
    Offset(0.1200, 0.0600),
    Offset(0.0400, 0.1300),
    Offset(0.0100, 0.2100),
    Offset(0.0000, 0.3000),
    Offset(0.0000, 0.6000),
    Offset(0.0000, 0.9000),
    Offset(0.0000, 1.0000),
  ];

  static const List<Offset> _front = [
    Offset(0.5700, 0.0000),
    Offset(0.7400, 0.0150),
    Offset(0.8800, 0.0600),
    Offset(0.9600, 0.1300),
    Offset(0.9900, 0.2100),
    Offset(1.0000, 0.3000),
    Offset(1.0000, 0.6000),
    Offset(1.0000, 0.9000),
    Offset(1.0000, 1.0000),
  ];

  // Aspect ratio of the traced torso bounding box (width/height) and head
  // geometry — relative to the torso box.
  static const double _torsoAspect = 0.50;
  static const double _headRFrac = 0.1874; // of torsoH
  static const double _apexFx = 0.379, _apexFy = 0.0;
  static const double _headFx = 0.4294, _headFy = -0.2644;

  Offset _local(Offset frac, double torsoW, double torsoH) {
    final lx = (frac.dx - 0.5) * torsoW;
    final ly = -(1 - frac.dy) * torsoH;
    return Offset(lx, ly);
  }

  // Applies a natural waist bend instead of rotating the entire portrait.
  // The lower body stays planted while the upper body, shoulders and head
  // bend together around the waist.
  Offset _waistBend(
      Offset point,
      double torsoH,
      double bendRad,
      ) {
    final waistY = -torsoH * 0.43;
    final topY = -torsoH * 1.08;

    // Points below the waist remain fixed. Points above the waist gradually
    // receive the bend, creating a softer and more human-looking transition.
    final rawT = ((waistY - point.dy) / (waistY - topY)).clamp(0.0, 1.0);
    final t = rawT * rawT * (3.0 - 2.0 * rawT); // smoothstep
    final localAngle = bendRad * t;

    if (localAngle.abs() < 0.0001) return point;

    final c = math.cos(localAngle);
    final si = math.sin(localAngle);
    final relative = point - Offset(0, waistY);

    final rotated = Offset(
      relative.dx * c - relative.dy * si,
      relative.dx * si + relative.dy * c,
    );

    return rotated + Offset(0, waistY);
  }

  // Smooth polyline through a set of points: each point is a Bezier
  // control, curving to the midpoint of it and the next — rounds the
  // shoulder dome instead of leaving faceted straight-line corners.
  void _smoothLineTo(Path path, List<Offset> pts) {
    for (var i = 0; i < pts.length; i++) {
      final ctrl = pts[i];
      final end =
          i == pts.length - 1 ? ctrl : Offset.lerp(ctrl, pts[i + 1], 0.5)!;
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
    }
  }

  Path _makeBodyPath(
      List<Offset> points,
      double torsoW,
      double torsoH,
      double bendRad,
      ) {
    final first = _waistBend(_local(points.first, torsoW, torsoH), torsoH, bendRad);
    final path = Path()..moveTo(first.dx, first.dy);

    for (final f in points.skip(1)) {
      final point = _waistBend(_local(f, torsoW, torsoH), torsoH, bendRad);
      path.lineTo(point.dx, point.dy);
    }

    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width / 2, size.height * 0.86);
    final torsoH = size.height * 0.60;
    final torsoW = torsoH * _torsoAspect;
    final headR = torsoH * _headRFrac;

    final lighter = Color.lerp(color, Colors.white, 0.20)!;
    final darker = Color.lerp(color, Colors.black, 0.22)!;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.13)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(pivot.dx, pivot.dy + 4),
        width: torsoW * 0.55,
        height: 8,
      ),
      shadowPaint,
    );

    // Only the upper body bends around the waist. The pelvis/lower body
    // remains stable, like a person bending from the middle of the back.
    final bendRad = tiltRad * 0.85;

    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);

    final body = Path();
    final back = _back
        .map((f) => _waistBend(_local(f, torsoW, torsoH), torsoH, bendRad))
        .toList(growable: false);
    final front = _front
        .map((f) => _waistBend(_local(f, torsoW, torsoH), torsoH, bendRad))
        .toList(growable: false);

    body.moveTo(back.first.dx, back.first.dy);
    _smoothLineTo(body, [...back.skip(1), ...front.reversed]);
    body.close();

    canvas.drawPath(body, Paint()..color = color);
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = darker.withValues(alpha: 0.4),
    );

    // Head follows the upper torso's bend, rather than rotating the whole
    // portrait around the base.
    final headLocal = _local(const Offset(_headFx, _headFy), torsoW, torsoH);
    final bentHead = _waistBend(headLocal, torsoH, bendRad);

    canvas.drawCircle(bentHead, headR, Paint()..color = lighter);
    canvas.drawCircle(
      bentHead,
      headR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = darker.withValues(alpha: 0.3),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: bentHead + Offset(headR * 0.3, -headR * 0.35),
        width: headR * 0.5,
        height: headR * 0.32,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PostureFigurePainter oldDelegate) {
    return oldDelegate.tiltRad != tiltRad ||
        oldDelegate.color != color ||
        oldDelegate.isCalibrated != isCalibrated;
  }
}
