import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bluetooth/aligneye_device_service.dart';
import '../bluetooth/pod_disconnected_dialog.dart';

class TrainingPage extends StatefulWidget {

  final AlignEyeDeviceService deviceService;
  const TrainingPage({super.key,required this.deviceService,});
  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  late StreamSubscription<PostureReading> _angleSub;
  double _liveAngle = 0.0;

  String _level = 'Advanced';
  double _sensitivity = 20;
  String _timing = 'Instant';
  int _delaySeconds = 5;
  bool _isRunning = false;

  static const _levels = <_TrainingLevel>[
    _TrainingLevel(
      name: 'Basic',
      gradient: [Color(0xFF4ADE80), Color(0xFF10B981)],
    ),
    _TrainingLevel(
      name: 'Intermediate',
      gradient: [Color(0xFF60A5FA), Color(0xFF06B6D4)],
    ),
    _TrainingLevel(
      name: 'Advanced',
      gradient: [Color(0xFFA855F7), Color(0xFFEC4899)],
    ),
  ];

  static const _timings = ['Instant', 'Delayed', 'No alert'];
  static const _delayOptions = [1, 2, 3, 4, 5, 10, 20, 30, 45, 60];

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _applyDefaultsForLevel(_level);
    _angleSub = widget.deviceService.readings.listen((r) {
      if (mounted) setState(() => _liveAngle = r.angle);
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    _angleSub.cancel();
    super.dispose();
  }

  Future<void> _toggleTraining() async {
    // Only show disconnect dialog when trying to START (not stop)
    if (!_isRunning &&
        widget.deviceService.connectionStatus.value !=
            DeviceConnectionStatus.connected) {
      await showPodDisconnectedDialog(
        context,
        subtitle:
        'Connect your Align Pod to start a training session.',
      );
      return;
    }
    HapticFeedback.mediumImpact();
    final newState = !_isRunning;
    setState(() => _isRunning = newState);

    final service = widget.deviceService;
    if (newState) {
      // Training start — sub_mode + difficulty_angle + delay_ms ek saath bhejo
      final subMode = switch (_timing) {
        'Delayed'  => 'DELAYED',
        'No alert' => 'NO_ALERTS',
        _          => 'INSTANT',
      };
      unawaited(service.sendTrainingStart(
        subMode: subMode,
        difficultyAngle: _sensitivity.round(),
        delayMs: _timing == 'Delayed' ? _delaySeconds * 1000 : 5000,
      ));
    } else {
      // Training stop — device idle mode mein chala jaata hai
      unawaited(service.sendTrainingStop());
    }
  }

  void _applyDefaultsForLevel(String level) {
    switch (level) {
      case 'Basic':
        _sensitivity = 45;
        _timing = 'Delayed';
        _delaySeconds = 5;
      case 'Intermediate':
        _sensitivity = 30;
        _timing = 'Delayed';
        _delaySeconds = 3;
      default: // Advanced
        _sensitivity = 20;
        _timing = 'Instant';
    }
  }

  Future<void> _showSensitivityWarning(double degrees) async {
    if (!mounted) return;
    final isTooBasic = degrees > 60;
    final title = isTooBasic ? 'This may be too basic' : 'This may be too hard';
    final message = isTooBasic
        ? 'A sensitivity above 60° may miss posture changes. Try a lower angle for better correction.'
        : 'A sensitivity below 10° may trigger alerts too often. Try increasing it if training feels too strict.';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _handleSensitivityChangeEnd(double value) {
    if (value > 60 || value < 10) {
      unawaited(_showSensitivityWarning(value));
    }
  }

  Future<void> _showDelayPicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _DelayPickerSheet(
        delayOptions: _delayOptions,
        currentDelay: _delaySeconds,
      ),
    );
    if (selected == null || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _delaySeconds = selected);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
        ),
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(28, 20, 21, 22),
            children: [
              _StaggeredEntrance(
                controller: _entryController,
                delay: 0,
                dy: -20,
                child: _TrainingHeader(
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 34),
              _StaggeredEntrance(
                controller: _entryController,
                delay: 0.10,
                child: _OptionSection(
                  title: 'Training Level',
                  child: Row(
                    children: _levels.map((level) {
                      final isSelected = _level == level.name;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: level == _levels.last ? 0 : 10,
                          ),
                          child: _ChoiceButton(
                            label: level.name,
                            isSelected: isSelected,
                            selectedGradient: level.gradient,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _level = level.name;
                                _applyDefaultsForLevel(level.name);
                              });
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _StaggeredEntrance(
                controller: _entryController,
                delay: 0.20,
                child: _GlassPanel(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Sensitivity',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${_sensitivity.round()}°',
                            style: const TextStyle(
                              color: Color(0xFFA855F7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: const Color(0xFF22C55E),
                          inactiveTrackColor: const Color(0xFFEF4444),
                          thumbColor: const Color(0xFFA855F7),
                          overlayColor: Colors.transparent,
                          trackHeight: 6,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          min: 0,
                          max: 90,
                          divisions: 18,
                          value: _sensitivity,
                          onChanged: (value) {
                            HapticFeedback.selectionClick();
                            setState(() => _sensitivity = value);
                          },
                          onChangeEnd: _handleSensitivityChangeEnd,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '0°',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '90°',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const _LegendDot(color: Color(0xFF22C55E)),
                          const SizedBox(width: 6),
                          Text(
                            'Good posture',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 18),
                          const _LegendDot(color: Color(0xFFEF4444)),
                          const SizedBox(width: 6),
                          Text(
                            'Bad posture',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _StaggeredEntrance(
                controller: _entryController,
                delay: 0.30,
                child: _OptionSection(
                  title: 'Correction Timing',
                  child: Row(
                    children: _timings.map((timing) {
                      final isSelected = _timing == timing;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: timing == _timings.last ? 0 : 10,
                          ),
                          child: _ChoiceButton(
                            label: timing,
                            isSelected: isSelected,
                            selectedGradient: const [
                              Color(0xFFA855F7),
                              Color(0xFFEC4899),
                            ],
                            fontSize: 13,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _timing = timing);
                              if (timing == 'Delayed') {
                                unawaited(_showDelayPicker());
                              }
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (_timing == 'Instant') ...[
                const SizedBox(height: 18),
                _StaggeredEntrance(
                  controller: _entryController,
                  delay: 0.34,
                  child: const _InstantAlertCard(),
                ),
              ],
              if (_timing == 'Delayed') ...[
                const SizedBox(height: 18),
                _StaggeredEntrance(
                  controller: _entryController,
                  delay: 0.34,
                  child: _DelayedAlertCard(
                    delaySeconds: _delaySeconds,
                    onChangeDelay: _showDelayPicker,
                  ),
                ),
              ],
              if (_timing == 'No alert') ...[
                const SizedBox(height: 18),
                _StaggeredEntrance(
                  controller: _entryController,
                  delay: 0.34,
                  child: const _TrackingOnlyCard(),
                ),
              ],
              const SizedBox(height: 23),
              _StaggeredEntrance(
                controller: _entryController,
                delay: 0.40,
                child: _GlassPanel(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Posture Graph',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _LiveGraph(
                        pulseController: _pulseController,
                        liveAngle: _liveAngle,
                        difficultyDeg: widget.deviceService.currentReading.value?.difficultyDeg.toDouble() ?? _sensitivity,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Past',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            'Real-time',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 21),
              _StaggeredEntrance(
                controller: _entryController,
                delay: 0.50,
                scaleFrom: 0.90,
                child: _StartButton(
                  isRunning: _isRunning,
                  onTap: _toggleTraining,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _TrainingHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            onBack();
          },
          icon: const Icon(Icons.arrow_back_rounded),
          color: scheme.onSurfaceVariant,
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 34),
        ),
        const SizedBox(height: 12),
        Hero(
          tag: 'mode_icon_training',
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF34D399), Color(0xFF14B8A6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.accessibility_new_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF8B00FF), Color(0xFFEC4899)],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: const Text(
            'Training Mode',
            style: TextStyle(
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Builder(
          builder: (context) => Text(
            'Build your posture awareness',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _OptionSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final List<Color> selectedGradient;
  final VoidCallback onTap;
  final double fontSize;

  const _ChoiceButton({
    required this.label,
    required this.isSelected,
    required this.selectedGradient,
    required this.onTap,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 46,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selectedGradient,
              )
                  : null,
              color: isSelected ? null : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
              border: isSelected
                  ? null
                  : Border.all(color: scheme.outline),
              boxShadow: isSelected
                  ? [
                BoxShadow(
                  color: selectedGradient.last.withValues(alpha: 0.23),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ]
                  : null,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : scheme.onSurface,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DelayedAlertCard extends StatelessWidget {
  final int delaySeconds;
  final VoidCallback onChangeDelay;

  const _DelayedAlertCard({
    required this.delaySeconds,
    required this.onChangeDelay,
  });

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      icon: Icons.hourglass_top_rounded,
      title: 'Delayed vibration alert',
      message:
      'You will receive a vibration alert after $delaySeconds seconds of poor posture.',
      trailing: TextButton(
        onPressed: onChangeDelay,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(54, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text('${delaySeconds}s'),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;

  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _InstantAlertCard extends StatelessWidget {
  const _InstantAlertCard();

  @override
  Widget build(BuildContext context) {
    return const _InfoCard(
      icon: Icons.electric_bolt_rounded,
      title: 'Instant vibration alert',
      message:
      'You will receive a vibration alert the moment poor posture is detected.',
    );
  }
}

class _TrackingOnlyCard extends StatelessWidget {
  const _TrackingOnlyCard();

  @override
  Widget build(BuildContext context) {
    return const _InfoCard(
      icon: Icons.timeline_rounded,
      title: 'Tracking only',
      message:
      'It will only track your posture. There will be no vibration alert.',
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? trailing;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFA855F7).withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: trailing!,
            ),
          ],
        ],
      ),
    );
  }
}

class _DelayChip extends StatelessWidget {
  final int seconds;
  final bool isSelected;
  final VoidCallback onTap;

  const _DelayChip({
    required this.seconds,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
              colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
            )
                : null,
            color: isSelected ? null : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
            border: isSelected
                ? null
                : Border.all(color: scheme.outline),
          ),
          child: Text(
            '${seconds}s',
            style: TextStyle(
              color: isSelected ? Colors.white : scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveGraph extends StatelessWidget {
  final AnimationController pulseController;
  final double liveAngle;
  final double difficultyDeg;

  const _LiveGraph({
    required this.pulseController,
    required this.liveAngle,
    required this.difficultyDeg,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 126,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
          ),
          child: AnimatedBuilder(
            animation: pulseController,
            builder: (context, _) {
              return CustomPaint(
                painter: _LiveGraphPainter(
                  progress: pulseController.value,
                  liveAngle: liveAngle,
                  difficultyDeg: difficultyDeg,
                ),
                child: Center(
                  child: Icon(
                    Icons.show_chart_rounded,
                    size: 34,
                    color: const Color(0xFFA855F7).withValues(alpha: 0.30),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LiveGraphPainter extends CustomPainter {
  final double progress;
  final double liveAngle;
  final double difficultyDeg;

  const _LiveGraphPainter({
    required this.progress,
    required this.liveAngle,
    required this.difficultyDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Angle ko 0..1 range mein convert karo (-90 to +90 → 0 to 1)
    final normalized = ((liveAngle + 90) / 180).clamp(0.0, 1.0);
    // 0.3 = good posture zone, normalized se actual Y position
    final y = size.height * (0.2 + normalized * 0.6);

    final path = Path();
    path.moveTo(0, y);
    path.lineTo(size.width, y);  // simple baseline pehle

    // Animated wave effect real angle ke around
    final wavePath = Path();
    for (int i = 0; i <= 100; i++) {
      final x = size.width * (i / 100);
      final wave = math.sin((progress * math.pi * 2) + (i / 10)) * 4;
      final pointY = y + wave;
      if (i == 0) {
        wavePath.moveTo(x, pointY);
      } else {
        wavePath.lineTo(x, pointY);
      }
    }

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Bad posture zone — red background
    if (liveAngle > difficultyDeg) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFFEF4444).withValues(alpha: 0.08),
      );
    }

    // Threshold line — difficultyDeg degree pe
    final thresholdY = size.height * (0.2 + ((difficultyDeg + 90) / 180) * 0.6);
    canvas.drawLine(
      Offset(0, thresholdY),
      Offset(size.width, thresholdY),
      Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    // Main wave line
    final paint = Paint()
      ..shader = LinearGradient(
        colors: liveAngle > difficultyDeg
            ? [const Color(0xFFEF4444), const Color(0xFFE11D48)]
            : [const Color(0xFFA855F7), const Color(0xFF22C55E)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(wavePath, paint);
  }

  @override
  bool shouldRepaint(covariant _LiveGraphPainter old) =>
      old.progress != progress ||
          old.liveAngle != liveAngle ||
          old.difficultyDeg != difficultyDeg;
}


class _StartButton extends StatelessWidget {
  final bool isRunning;
  final VoidCallback onTap;

  const _StartButton({required this.isRunning, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isRunning
                  ? [const Color(0xFFEF4444), const Color(0xFFE11D48)]
                  : [const Color(0xFFA855F7), const Color(0xFFEC4899)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color:
                (isRunning
                    ? const Color(0xFFEF4444)
                    : const Color(0xFFEC4899))
                    .withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bolt_rounded, color: Colors.white, size: 25),
              const SizedBox(width: 12),
              Text(
                isRunning ? 'Stop Training' : 'Start Training',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassPanel({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.20)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x15000000),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StaggeredEntrance extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final double dy;
  final double scaleFrom;
  final Widget child;

  const _StaggeredEntrance({
    required this.controller,
    required this.delay,
    required this.child,
    this.dy = 20,
    this.scaleFrom = 1,
  });

  @override
  Widget build(BuildContext context) {
    final start = delay.clamp(0.0, 0.85);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final value = animation.value;
        final scale = scaleFrom + (1 - scaleFrom) * value;
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, dy * (1 - value)),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}

class _TrainingLevel {
  final String name;
  final List<Color> gradient;

  const _TrainingLevel({required this.name, required this.gradient});
}

// Proper StatefulWidget so TextEditingController is disposed with the widget,
// not with the caller — avoids the _dependents.isEmpty crash.
class _DelayPickerSheet extends StatefulWidget {
  final List<int> delayOptions;
  final int currentDelay;

  const _DelayPickerSheet({
    required this.delayOptions,
    required this.currentDelay,
  });

  @override
  State<_DelayPickerSheet> createState() => _DelayPickerSheetState();
}

class _DelayPickerSheetState extends State<_DelayPickerSheet> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          4,
          22,
          22 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose alert delay',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pick how long poor posture should continue before vibration starts.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: widget.delayOptions.map((seconds) {
                final isSelected = widget.currentDelay == seconds;
                return _DelayChip(
                  seconds: seconds,
                  isSelected: isSelected,
                  onTap: () => Navigator.of(context).pop(seconds),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Custom seconds',
                hintText: 'Enter 1 to 300',
                errorText: _errorText,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final value = int.tryParse(_controller.text.trim());
                  if (value == null || value < 1 || value > 300) {
                    setState(() {
                      _errorText = 'Enter a value from 1 to 300 seconds';
                    });
                    return;
                  }
                  Navigator.of(context).pop(value);
                },
                child: const Text('Use custom delay'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}