import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Flat cartoon side-view figure (boy facing right: quiff hair, t-shirt,
/// shorts, sneakers), hand-drawn with CustomPainter. Legs and shoes stay
/// planted; the upper back and head round forward from the shoulders as
/// [liveAngle] rises. The t-shirt carries the posture status colour: good
/// until [thresholdAngle], bad past it, grey when not calibrated.
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

  // Figure is drawn in a fixed 68x124 design box and scaled to the widget.
  static const double _designW = 68, _designH = 124;
  static const Offset _shoulderPivot = Offset(34, 58);
  static const Offset _shoulder = Offset(34.5, 50);

  static const _skin = Color(0xFFF5C27A);
  static const _skinShade = Color(0xFFE0A860);
  static const _hair = Color(0xFF26262A);
  static const _shorts = Color(0xFF1E5BB8);
  static const _shoe = Color(0xFF1A1A1A);

  Paint _fill(Color c) => Paint()..color = c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _designW, size.height / _designH);

    final shirtLight = Color.lerp(color, Colors.white, 0.18)!;
    final shirtDark = Color.lerp(color, Colors.black, 0.20)!;

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(34, 120), width: 30, height: 6),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // --- Planted lower body -------------------------------------------
    // Back leg (shaded) then front leg.
    canvas.drawRRect(
      RRect.fromLTRBR(28, 86, 34, 114, const Radius.circular(2.5)),
      _fill(_skinShade),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(31, 86, 37, 114, const Radius.circular(2.5)),
      _fill(_skin),
    );

    // Sneakers pointing right, with two white stripes.
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        25, 111, 44, 118,
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(6),
        bottomLeft: const Radius.circular(1.5),
        bottomRight: const Radius.circular(2.5),
      ),
      _fill(_shoe),
    );
    final stripe = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(31, 116), const Offset(33, 113), stripe);
    canvas.drawLine(const Offset(34, 116), const Offset(36, 113), stripe);

    // Shorts.
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        25, 72, 43, 92,
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
      ),
      _fill(_shorts),
    );

    // --- Upper body: rounds forward from the shoulders ---------------
    // The shirt is one outline whose points bend progressively (none at
    // the hem, full at the shoulders), so the back curves smoothly instead
    // of splitting at a joint. Head and neck ride the full bend.
    final bend = tiltRad * 0.85;
    void rotateFull() {
      canvas.translate(_shoulderPivot.dx, _shoulderPivot.dy);
      canvas.rotate(bend);
      canvas.translate(-_shoulderPivot.dx, -_shoulderPivot.dy);
    }

    // Neck (behind the shirt collar).
    canvas.save();
    rotateFull();
    canvas.drawRect(const Rect.fromLTRB(31, 37, 37, 47), _fill(_skinShade));
    canvas.restore();

    final shirt = _bent(
      Path()
        ..addRRect(RRect.fromLTRBAndCorners(
          24, 44, 44, 80,
          topLeft: const Radius.circular(9),
          topRight: const Radius.circular(8),
          bottomLeft: const Radius.circular(3),
          bottomRight: const Radius.circular(3),
        )),
      bend,
    );
    canvas.drawPath(shirt, _fill(color));
    canvas.save();
    canvas.clipPath(shirt);
    canvas.drawPath(
      _bent(Path()..addRect(const Rect.fromLTRB(20, 40, 28, 84)), bend),
      _fill(shirtDark),
    );
    canvas.restore();

    canvas.save();
    rotateFull();

    // Head and ear.
    canvas.drawOval(const Rect.fromLTRB(25, 18, 45, 41), _fill(_skin));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(31.5, 30), width: 5, height: 7),
      _fill(_skinShade),
    );

    // Hair: quiff sweeping up and forward, covering top and back of head.
    final hair = Path()
      ..moveTo(26, 35)
      ..quadraticBezierTo(21, 22, 27, 13)
      ..quadraticBezierTo(34, 4, 43, 9)
      ..quadraticBezierTo(47, 13, 44, 19)
      ..lineTo(37, 20)
      ..quadraticBezierTo(31, 21, 30, 27)
      ..lineTo(29, 35)
      ..close();
    canvas.drawPath(hair, _fill(_hair));

    // Face: brow, eye, smile.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = _hair;
    canvas.drawPath(
      Path()
        ..moveTo(38.8, 23.6)
        ..quadraticBezierTo(41, 22.6, 43.2, 23.6),
      line,
    );
    canvas.drawCircle(const Offset(41, 27), 2.2, _fill(Colors.white));
    canvas.drawCircle(const Offset(41.7, 27), 1.3, _fill(_hair));
    canvas.drawPath(
      Path()
        ..moveTo(39.5, 33.5)
        ..quadraticBezierTo(41.8, 35.6, 43.8, 33),
      line..color = const Color(0xFF8A4B2A),
    );

    canvas.restore();

    // Arm hangs straight down from wherever the shoulder moved to.
    final moved = _bendPoint(_shoulder, bend);
    canvas.save();
    canvas.translate(moved.dx - _shoulder.dx, moved.dy - _shoulder.dy);
    canvas.drawRRect(
      RRect.fromLTRBR(30, 46, 39, 61, const Radius.circular(4)),
      _fill(shirtLight),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(32, 58, 37, 80, const Radius.circular(2.5)),
      _fill(_skin),
    );
    canvas.drawCircle(const Offset(34.8, 80.5), 3, _fill(_skin));
    canvas.restore();

    canvas.restore();
  }

  // Upper-body points bend around [_shoulderPivot]: not at all below
  // [_bendStartY], fully above [_bendEndY], smoothstepped in between.
  static const double _bendStartY = 70, _bendEndY = 48;

  Offset _bendPoint(Offset p, double bend) {
    final raw =
        ((_bendStartY - p.dy) / (_bendStartY - _bendEndY)).clamp(0.0, 1.0);
    final a = bend * raw * raw * (3 - 2 * raw);
    if (a == 0) return p;
    final r = p - _shoulderPivot;
    return _shoulderPivot +
        Offset(
          r.dx * math.cos(a) - r.dy * math.sin(a),
          r.dx * math.sin(a) + r.dy * math.cos(a),
        );
  }

  // Resamples [src] every design unit and bends each point.
  Path _bent(Path src, double bend) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      for (double d = 0; d < m.length; d += 1) {
        final p = _bendPoint(m.getTangentForOffset(d)!.position, bend);
        d == 0 ? out.moveTo(p.dx, p.dy) : out.lineTo(p.dx, p.dy);
      }
      out.close();
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _PostureFigurePainter oldDelegate) {
    return oldDelegate.tiltRad != tiltRad ||
        oldDelegate.color != color ||
        oldDelegate.isCalibrated != isCalibrated;
  }
}
