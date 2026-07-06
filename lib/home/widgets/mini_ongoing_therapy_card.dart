import 'dart:async';
import 'dart:math' as math;

import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/home/widgets/surface_card.dart';
import 'package:correctv1/services/therapy_pattern_names.dart';
import 'package:flutter/material.dart';

class MiniOngoingTherapyCard extends StatefulWidget {
  final AlignEyeDeviceService deviceService;
  final int totalMinutes;
  final VoidCallback onTap;

  const MiniOngoingTherapyCard({
    super.key,
    required this.deviceService,
    required this.totalMinutes,
    required this.onTap,
  });

  @override
  State<MiniOngoingTherapyCard> createState() => _MiniOngoingTherapyCardState();
}

class _MiniOngoingTherapyCardState extends State<MiniOngoingTherapyCard>
    with TickerProviderStateMixin {
  late final AnimationController _breathController;
  late final AnimationController _wavesController;

  // Timer state mirrors the immersive page so the home mini card reads
  // exactly the same values. Seeded with -1 / 0 until the first therapy
  // frame lands.
  StreamSubscription<PostureReading>? _readingSub;
  Timer? _localTicker;

  int _totalRemainingSeconds = -1;
  int _totalElapsedSeconds = 0;
  int _totalDurationSeconds = 0;
  int _frameRemainingSeconds = -1;

  int _lastPatternStartElapsed = 0;
  String _lastPatternName = '';
  int? _lastKnownPatternDurationSeconds;

  // Real-time pattern progress and posture state variables (V5)
  int _patternElapsedSecondsState = 0;
  int _patternRemainingSecondsState = -1;
  bool _hasPatternProgress = false;

  @override
  void initState() {
    super.initState();
    _totalDurationSeconds = widget.totalMinutes * 60;
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _wavesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();

    // Seed from the service's sticky cache so opening a fresh home page
    // mid-session doesn't flash zeros.
    final cachedPattern = widget.deviceService.latestTherapyPatternName;
    if (cachedPattern.isNotEmpty) {
      _lastPatternName = _stripSessionMeta(cachedPattern);
    }

    _consumeReading(widget.deviceService.currentReading.value);
    _readingSub = widget.deviceService.readings.listen(_handleReading);

    widget.deviceService.connectionStatus.addListener(_handleConnectionStatus);
    _syncLocalTickerWithConnection();
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    _localTicker?.cancel();
    widget.deviceService.connectionStatus.removeListener(
      _handleConnectionStatus,
    );
    _breathController.dispose();
    _wavesController.dispose();
    super.dispose();
  }

  void _handleConnectionStatus() {
    _syncLocalTickerWithConnection();
  }

  void _syncLocalTickerWithConnection() {
    final connected =
        widget.deviceService.connectionStatus.value ==
        DeviceConnectionStatus.connected;
    if (connected) {
      _ensureLocalTicker();
    } else {
      _localTicker?.cancel();
      _localTicker = null;
      if (mounted) setState(() {});
    }
  }

  void _ensureLocalTicker() {
    if (_localTicker != null) return;
    // Align to the next wall-clock second boundary so this timer fires at
    // the same real-world instant as the immersive page's — zero visible
    // drift between the two surfaces.
    final now = DateTime.now();
    final msToNextSecond = 1000 - now.millisecond;
    _localTicker = Timer(Duration(milliseconds: msToNextSecond), () {
      if (!mounted) return;
      _runTick();
      _localTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          _localTicker?.cancel();
          _localTicker = null;
          return;
        }
        _runTick();
      });
    });
  }

  void _runTick() {
    if (_frameRemainingSeconds < 0) return;
    if (widget.deviceService.connectionStatus.value !=
        DeviceConnectionStatus.connected) {
      return;
    }
    final anchoredRemaining = widget.deviceService.therapyRemainingSecondsNow;
    final anchoredElapsed = widget.deviceService.therapyElapsedSecondsNow;
    final anchoredPatternRemaining =
        widget.deviceService.therapyPatternRemainingSecondsNow;
    final anchoredPatternElapsed =
        widget.deviceService.therapyPatternElapsedSecondsNow;

    setState(() {
      if (anchoredRemaining >= 0) {
        _totalRemainingSeconds = anchoredRemaining;
      } else if (_totalRemainingSeconds > 0) {
        _totalRemainingSeconds -= 1;
      }
      if (anchoredElapsed > _totalElapsedSeconds) {
        _totalElapsedSeconds = anchoredElapsed;
      } else {
        _totalElapsedSeconds += 1;
      }

      if (_hasPatternProgress) {
        if (anchoredPatternRemaining >= 0) {
          _patternRemainingSecondsState = anchoredPatternRemaining;
        } else if (_patternRemainingSecondsState > 0) {
          _patternRemainingSecondsState -= 1;
        }
        if (anchoredPatternElapsed >= 0) {
          _patternElapsedSecondsState = anchoredPatternElapsed;
        } else {
          _patternElapsedSecondsState += 1;
        }
      }
    });
  }

  void _handleReading(PostureReading reading) {
    _consumeReading(reading);
  }

  void _consumeReading(PostureReading? reading) {
    if (reading == null || !mounted) return;
    final isTherapy = reading.mode.toUpperCase() == 'THERAPY';
    if (!isTherapy) return;

    final elapsed = reading.therapyElapsedSeconds;
    final remaining = reading.therapyRemainingSeconds;
    final cleanPatternName = _stripSessionMeta(reading.therapyPattern.trim());

    setState(() {
      _frameRemainingSeconds = remaining;
      _totalElapsedSeconds = elapsed;
      _totalRemainingSeconds = remaining;
      final firmwareTotal = reading.therapyTotalDurationSeconds > 0
          ? reading.therapyTotalDurationSeconds
          : (elapsed + remaining);
      if (firmwareTotal > 0) {
        _totalDurationSeconds = firmwareTotal;
      }
      _ensureLocalTicker();

      if (cleanPatternName != _lastPatternName) {
        if (_lastPatternName.isNotEmpty) {
          final prevDuration = elapsed - _lastPatternStartElapsed;
          if (prevDuration > 0) {
            _lastKnownPatternDurationSeconds = prevDuration;
          }
        }
        _lastPatternName = cleanPatternName;
        _lastPatternStartElapsed = elapsed;
      }

      if (reading.therapyPatternRemainingSeconds > 0 ||
          reading.therapyPatternElapsedSeconds > 0) {
        _patternElapsedSecondsState = reading.therapyPatternElapsedSeconds;
        _patternRemainingSecondsState = reading.therapyPatternRemainingSeconds;
        _hasPatternProgress = true;
      } else {
        _hasPatternProgress = false;
      }

      // Removed posture/angle mapping (not sent in TL telemetry)
    });
  }

  String _stripSessionMeta(String raw) {
    final bracket = raw.indexOf('[');
    if (bracket <= 0) return raw;
    return raw.substring(0, bracket).trim();
  }

  int get _patternElapsedSeconds {
    if (_hasPatternProgress) {
      return _patternElapsedSecondsState;
    }
    if (_totalElapsedSeconds <= 0) return 0;
    return math.max(0, _totalElapsedSeconds - _lastPatternStartElapsed);
  }

  int get _patternDurationSeconds {
    if (_hasPatternProgress) {
      return _patternElapsedSecondsState + _patternRemainingSecondsState;
    }
    final guess =
        _lastKnownPatternDurationSeconds ?? (_totalDurationSeconds ~/ 7);
    return math.max(20, guess);
  }

  String _formatMMSS(int totalSeconds) {
    final safe = math.max(0, totalSeconds);
    final m = (safe ~/ 60).toString().padLeft(2, '0');
    final s = (safe % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final sessionProgress = _totalDurationSeconds == 0
        ? 0.0
        : (_totalElapsedSeconds / _totalDurationSeconds).clamp(0.0, 1.0);
    final remainingForUi = _totalRemainingSeconds >= 0
        ? _totalRemainingSeconds
        : _totalDurationSeconds;
    final totalMinutesForUi = _totalDurationSeconds > 0
        ? (_totalDurationSeconds / 60).round()
        : widget.totalMinutes;
    final patternElapsed = _patternElapsedSeconds;
    final patternProgress = (patternElapsed / _patternDurationSeconds).clamp(
      0.0,
      1.0,
    );

    final cachedId = widget.deviceService.latestTherapyPatternId;
    final friendlyPattern = cachedId >= 0
        ? therapyPatternName(cachedId)
        : friendlyTherapyPatternLabel(_lastPatternName);
    final pillLabel =
        friendlyPattern.isEmpty ||
            friendlyPattern.toLowerCase() == 'preparing pattern...' ||
            friendlyPattern.toLowerCase() == 'waiting for therapy'
        ? 'Preparing pattern…'
        : friendlyPattern;

    return HomeSurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Therapy in Progress',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Center(
                child: SizedBox(
                  height: 260,
                  width: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _breathController,
                          _wavesController,
                        ]),
                        builder: (context, _) {
                          return CustomPaint(
                            size: const Size(260, 260),
                            painter: _MiniTherapyOrbPainter(
                              breathValue: _breathController.value,
                              wavesValue: _wavesController.value,
                              sessionProgress: sessionProgress.clamp(0.0, 1.0),
                              patternProgress: patternProgress,
                            ),
                          );
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'SESSION LEFT',
                              style: TextStyle(
                                color: Color(0xFFFF2B62),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatMMSS(remainingForUi),
                              style: const TextStyle(
                                color: Color(0xFF1F2937),
                                fontSize: 42,
                                fontWeight: FontWeight.w300,
                                height: 1.0,
                                letterSpacing: -1.0,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'of ${totalMinutesForUi}m',
                              style: const TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: 32,
                              height: 1,
                              color: const Color(0xFFFCE7F3),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _formatMMSS(patternElapsed),
                              style: const TextStyle(
                                color: Color(0xFFFF2B62),
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                height: 1.0,
                                letterSpacing: 0.2,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'current pattern',
                              style: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _NowPatternPill(label: pillLabel),
              // Removed posture badge layout (not sent in TL telemetry)
            ],
          ),
        ),
      ),
    );
  }
}

/// Pink `NOW <pattern>` capsule that sits below the orb, mirroring the
/// reference UI shot. `NOW` is a white chip on a saturated pink pill; the
/// current pattern name sits next to it in bold white.
class _NowPatternPill extends StatelessWidget {
  final String label;

  const _NowPatternPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 18, 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF3B75), Color(0xFFED2CA6)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF43F5E).withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'NOW',
              style: TextStyle(
                color: Color(0xFFFF2B62),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTherapyOrbPainter extends CustomPainter {
  final double breathValue;
  final double wavesValue;
  final double sessionProgress;
  final double patternProgress;

  _MiniTherapyOrbPainter({
    required this.breathValue,
    required this.wavesValue,
    required this.sessionProgress,
    required this.patternProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Layered layout mirrors the immersive page: outer session ring, inner
    // pattern ring, then the breathing orb itself.
    final outerRadius = size.width * 0.46;
    final innerRadius = outerRadius - 14;
    final baseRadius = innerRadius - 12;

    final breath = Curves.easeInOut.transform(breathValue);

    const ringCount = 5;
    for (int i = 0; i < ringCount; i++) {
      final phase = (wavesValue + i / ringCount) % 1.0;
      final eased = Curves.easeOut.transform(phase);
      final waveRadius = baseRadius * (0.96 + eased * 0.60);
      final aliveFade = math.sin(phase * math.pi);
      final opacity = (aliveFade * 0.18).clamp(0.0, 1.0);
      final wavePaint = Paint()
        ..color = const Color(0xFFFF7DA0).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      canvas.drawCircle(center, waveRadius, wavePaint);
    }

    final resonancePaint = Paint()
      ..color = const Color(0xFFFF2B62).withValues(alpha: 0.08 + breath * 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(
      center,
      baseRadius * (1.10 + breath * 0.05),
      resonancePaint,
    );

    final breathRadius = baseRadius * (1.0 + breath * 0.045);

    final ambientHaloPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFFFFB4C5).withValues(alpha: 0.28),
              const Color(0xFFFFB4C5).withValues(alpha: 0.0),
            ],
            stops: const [0.25, 1.0],
          ).createShader(
            Rect.fromCircle(center: center, radius: breathRadius * 1.7),
          );
    canvas.drawCircle(center, breathRadius * 1.7, ambientHaloPaint);

    final orbRect = Rect.fromCircle(center: center, radius: breathRadius);
    final orbPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.15, -0.20),
        radius: 1.05,
        colors: [Color(0xFFFFF5F7), Color(0xFFFFE4E6), Color(0xFFFDD5E0)],
        stops: [0.0, 0.55, 1.0],
      ).createShader(orbRect);
    canvas.drawCircle(center, breathRadius, orbPaint);

    final highlightPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        radius: 0.7,
        colors: [
          Colors.white.withValues(alpha: 0.7),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(orbRect);
    canvas.drawCircle(center, breathRadius, highlightPaint);

    final orbBorderPaint = Paint()
      ..color = const Color(0xFFFF2B62).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, breathRadius, orbBorderPaint);

    // Inner ring — current-pattern progress.
    _drawRing(
      canvas,
      center,
      innerRadius,
      patternProgress.clamp(0.0, 1.0),
      strokeWidth: 4,
      trackColor: const Color(0xFFFCE7F3),
      gradientColors: const [Color(0xFFFF7DA0), Color(0xFFFF2B62)],
    );

    // Outer ring — total session progress.
    _drawRing(
      canvas,
      center,
      outerRadius,
      sessionProgress.clamp(0.0, 1.0),
      strokeWidth: 6,
      trackColor: const Color(0xFFFFE4E6),
      gradientColors: const [Color(0xFFFF1F5B), Color(0xFFED2CA6)],
    );
  }

  void _drawRing(
    Canvas canvas,
    Offset center,
    double radius,
    double progress, {
    required double strokeWidth,
    required Color trackColor,
    required List<Color> gradientColors,
  }) {
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + 2 * math.pi,
        colors: gradientColors,
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniTherapyOrbPainter oldDelegate) {
    return oldDelegate.breathValue != breathValue ||
        oldDelegate.wavesValue != wavesValue ||
        oldDelegate.sessionProgress != sessionProgress ||
        oldDelegate.patternProgress != patternProgress;
  }
}
