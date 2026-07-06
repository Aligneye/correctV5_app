import 'dart:async';
import 'dart:math' as math;

import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:flutter/material.dart';

class TopHeaderBar extends StatefulWidget {
  final DeviceConnectionStatus status;
  final bool isFindingDevice;
  final bool isSyncing;
  final bool isLive;
  final int batteryLevel;
  final String profile;
  final VoidCallback onTap;

  const TopHeaderBar({
    super.key,
    required this.status,
    required this.isFindingDevice,
    required this.isSyncing,
    required this.isLive,
    required this.batteryLevel,
    required this.profile,
    required this.onTap,
  });

  @override
  State<TopHeaderBar> createState() => _TopHeaderBarState();
}

class _TopHeaderBarState extends State<TopHeaderBar>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // ── Connection celebration animation ──────────────────────────────
  late final AnimationController _connectCtrl;
  late final Animation<double> _connectScale;
  late final Animation<double> _connectGlow;

  // ── Rotating border for pending states ────────────────────────────
  late final AnimationController _spinCtrl;

  DeviceConnectionStatus? _prevStatus;

  // ── Motivational word pool (shown with typewriter effect) ──────────
  static const _motivationalWords = [
    'Focus',
    'Breathe',
    'Balance',
    'Keep Going',
    'Stand tall',
    'Be present',
    'Reset',
    'Own it',
    'Redefining posture',
    'Stay aligned',
    'Be in the moment',
    'Posture Matters',
    'Just do it',
    'Move Better',
    'Build Good Habits',
    'Rise Above Limits',
    'Sit Like Human',
    'Straighten Up Champ',
    'Posture Police Watching',
    'Neck Says Ouch',
    'Look Less Potato',
  ];

  String _chosenText = '';
  String _displayedText = '';
  Timer? _typewriterTimer;
  Timer? _cycleTimer;
  int _charIndex = 0;
  int _cycleCount = 0;
  static const _maxCyclesPerBurst = 3;
  static const _delayBetweenCycles = Duration(seconds: 5);
  static const _burstInterval = Duration(seconds: 60);

  String _pickTextForSession() {
    final rand = math.Random();
    final now = DateTime.now();
    final h = now.hour;

    // ~30 % chance to show a time-aware greeting instead of motivational word
    if (rand.nextDouble() < 0.30) {
      if (h >= 5 && h < 12) return 'Good morning';
      if (h >= 12 && h < 17) return 'Good afternoon';
      if (h >= 17 && h < 21) return 'Good evening';
      return 'Welcome back';
    }
    return _motivationalWords[rand.nextInt(_motivationalWords.length)];
  }

  // ── Typewriter engine ─────────────────────────────────────────────
  void _startTypewriterCycle() {
    _cycleCount = 0;
    _runSingleTypewrite();
  }

  void _runSingleTypewrite() {
    _charIndex = 0;
    _displayedText = '';
    if (mounted) setState(() {});

    _typewriterTimer?.cancel();
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 80), (
      timer,
    ) {
      if (_charIndex < _chosenText.length) {
        _charIndex++;
        _displayedText = _chosenText.substring(0, _charIndex);
        if (mounted) setState(() {});
      } else {
        timer.cancel();
        _cycleCount++;
        if (_cycleCount < _maxCyclesPerBurst) {
          Future.delayed(_delayBetweenCycles, () {
            if (mounted) _runSingleTypewrite();
          });
        }
      }
    });
  }

  void _scheduleBursts() {
    _startTypewriterCycle();
    _cycleTimer?.cancel();
    _cycleTimer = Timer.periodic(_burstInterval, (_) {
      if (mounted) _startTypewriterCycle();
    });
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.35,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _connectCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _connectScale = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _connectCtrl, curve: Curves.easeOutBack));
    _connectGlow = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _connectCtrl, curve: Curves.easeOut));

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _prevStatus = widget.status;
    _chosenText = _pickTextForSession();
    _scheduleBursts();
  }

  @override
  void didUpdateWidget(covariant TopHeaderBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      if (widget.status == DeviceConnectionStatus.connected &&
          _prevStatus != DeviceConnectionStatus.connected) {
        _connectCtrl.forward().then((_) => _connectCtrl.reverse());
      }
      _prevStatus = widget.status;
    }
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _cycleTimer?.cancel();
    _pulseCtrl.dispose();
    _connectCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.status == DeviceConnectionStatus.connected;
    final isConnecting = widget.status == DeviceConnectionStatus.connecting;
    final isPending =
        isConnecting || widget.isFindingDevice || widget.isSyncing;

    final Color accentColor;
    final IconData statusIcon;
    final String statusLabel;

    if (widget.isFindingDevice) {
      accentColor = const Color(0xFFF59E0B);
      statusIcon = Icons.bluetooth_searching_rounded;
      statusLabel = 'Finding…';
    } else if (isConnecting) {
      accentColor = const Color(0xFFF59E0B);
      statusIcon = Icons.bluetooth_searching_rounded;
      statusLabel = 'Connecting…';
    } else if (widget.isSyncing) {
      accentColor = const Color(0xFF3B82F6);
      statusIcon = Icons.sync_rounded;
      statusLabel = 'Syncing';
    } else if (isConnected && widget.isLive) {
      accentColor = const Color(0xFFEF4444);
      statusIcon = Icons.sensors_rounded;
      statusLabel = 'Live';
    } else if (isConnected) {
      accentColor = const Color(0xFF22C55E);
      statusIcon = Icons.bluetooth_connected_rounded;
      statusLabel = 'Connected';
    } else {
      accentColor = AppTheme.textMuted;
      statusIcon = Icons.bluetooth_rounded;
      statusLabel = 'Tap to connect';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Left: logo + tagline ────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRect(
                child: Transform.translate(
                  offset: const Offset(-25, 0),
                  child: Image.asset(
                    'assets/newLogo.png',
                    height: 30,
                    fit: BoxFit.fitHeight,
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppTheme.trainingGradient.createShader(
                      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                    ),
                blendMode: BlendMode.srcIn,
                child: Text(
                  _displayedText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // ── Right: connection chip ──────────────────────────────────
        GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _connectScale,
              _connectGlow,
              _pulseAnim,
              _spinCtrl,
            ]),
            builder: (context, child) {
              return Transform.scale(
                scale: _connectScale.value,
                child: _buildConnectionChip(
                  context: context,
                  accentColor: accentColor,
                  statusIcon: statusIcon,
                  statusLabel: statusLabel,
                  isConnected: isConnected,
                  isPending: isPending,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionChip({
    required BuildContext context,
    required Color accentColor,
    required IconData statusIcon,
    required String statusLabel,
    required bool isConnected,
    required bool isPending,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final batteryIcon = widget.batteryLevel > 70
        ? Icons.battery_full_rounded
        : widget.batteryLevel > 30
        ? Icons.battery_5_bar_rounded
        : Icons.battery_alert_rounded;
    final batteryColor = widget.batteryLevel > 30
        ? scheme.onSurfaceVariant
        : const Color(0xFFEF4444);

    final glowOpacity = _connectGlow.value * 0.5;
    final breathe = isConnected ? 0.04 * _pulseAnim.value : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(alpha: isPending ? 0.35 : 0.15),
          width: 1,
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
          if (glowOpacity > 0)
            BoxShadow(
              color: accentColor.withValues(alpha: glowOpacity),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          if (isConnected)
            BoxShadow(
              color: accentColor.withValues(alpha: 0.04 + breathe),
              blurRadius: 14,
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Animated icon with spinner ──────────────────────────
          SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isPending)
                  Transform.rotate(
                    angle: _spinCtrl.value * 2 * math.pi,
                    child: CustomPaint(
                      size: const Size(24, 24),
                      painter: ArcPainter(color: accentColor),
                    ),
                  ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10 + breathe),
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      statusIcon,
                      key: ValueKey(statusIcon),
                      size: 13,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Status label + battery below ────────────────────────
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  statusLabel,
                  key: ValueKey(statusLabel),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topLeft,
                clipBehavior: Clip.hardEdge,
                child: isConnected
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(batteryIcon, size: 12, color: batteryColor),
                            const SizedBox(width: 3),
                            Text(
                              '${widget.batteryLevel}%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: batteryColor,
                              ),
                            ),
                            if (widget.profile.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '· ${widget.profile}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: batteryColor.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

class ArcPainter extends CustomPainter {
  final Color color;
  const ArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    canvas.drawArc(rect, 0, math.pi * 1.2, false, paint);
  }

  @override
  bool shouldRepaint(covariant ArcPainter old) => old.color != color;
}
