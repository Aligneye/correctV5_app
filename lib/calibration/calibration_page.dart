import 'dart:async';
import 'package:lottie/lottie.dart';
import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/services/angle_history_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _CalibrationStage {
  intro,
  starting,
  getReady,
  holdStill,
  failed,
  success,
  disconnected,
}

class CalibrationPage extends StatefulWidget {
  // Profile name to assign on calibration success
  final String profileName;

  const CalibrationPage({
    super.key,
    required this.deviceService,
    this.autoStart = false,
    this.profileName = 'Profile',
  });

  final AlignEyeDeviceService deviceService;
  final bool autoStart;

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage>
    with TickerProviderStateMixin {
  // Fallback durations — used when device hasn't sent c_tot yet
  static const int _fallbackGetReadyMs = 2000;
  static const int _fallbackHoldStillMs = 5000;
  static const Duration _startDetectTimeout = Duration(seconds: 10);

  late final AnimationController _pulseController;
  late final AnimationController _scaleController;
  late final AnimationController _successBarController;
  late final AnimationController _failedBarController;
  StreamSubscription<PostureReading>? _readingSubscription;
  Timer? _ticker;
  Timer? _successAutoCloseTimer;

  _CalibrationStage _stage = _CalibrationStage.intro;
  DateTime? _startRequestedAt;
  bool _closing = false;
  bool _completionHandled = false;
  late String _profileName;

  // BLE-reported values (may be sparse — firmware only sends on start/end)
  int _deviceElapsedMs = 0;
  String _devicePhase = 'IDLE';
  int _deviceHoldStartMs = 0;
  int _cancelMissCount = 0;
  // Result details from DONE packet
  int _calibrationQuality = 0;
  String _failReason = '';

  // Wall-clock anchor for smooth progress when BLE packets are sparse
  DateTime? _getReadyStartedAt;
  DateTime? _holdStillStartedAt;
  // Bug 3 fix: set true when BLE drives the getReady→holdStill transition so
  // the wall-clock fallback in _onTick() doesn't fire a second time.
  bool _bleHoldStillReceived = false;
  @override
  void initState() {
    super.initState();
    _profileName = widget.profileName;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _successBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _failedBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _readingSubscription = widget.deviceService.readings.listen(_onReading);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _onTick(),
    );

    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startCalibration());
      });
    }

  }

  @override
  void dispose() {
    _ticker?.cancel();
    _successAutoCloseTimer?.cancel();
    _readingSubscription?.cancel();
    _pulseController.dispose();
    _scaleController.dispose();
    _successBarController.dispose();
    _failedBarController.dispose();
    super.dispose();
  }

  bool get _isConnected =>
      widget.deviceService.connectionStatus.value ==
      DeviceConnectionStatus.connected;

  Future<void> _startCalibration() async {
    if (!_isConnected) {
      setState(() => _stage = _CalibrationStage.disconnected);
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _stage = _CalibrationStage.starting;
      _startRequestedAt = DateTime.now();
      _completionHandled = false;
      _deviceElapsedMs = 0;
      _devicePhase = 'IDLE';
      _deviceHoldStartMs = 0;
      _cancelMissCount = 0;
      _getReadyStartedAt = null;
      _holdStillStartedAt = null;
      _bleHoldStillReceived = false;
    });

    final sent = await widget.deviceService.sendCalibrationStartJson(
      name: _profileName,
    );
    if (!mounted) return;
    if (!sent) {
      setState(() => _stage = _CalibrationStage.failed);
      _failedBarController.forward();
    }
  }

  void _onReading(PostureReading reading) {
    // if (reading.isCalibrating ||
    //     reading.calibrationResult.isNotEmpty ||
    //     reading.calibrationPhase != 'IDLE') {
    //   debugPrint(
    //     'CAL_DEBUG: stage=$_stage, isCalibrating=${reading.isCalibrating}, '
    //     'result="${reading.calibrationResult}", phase=${reading.calibrationPhase}, '
    //     'elapsed=${reading.calibrationElapsedMs}',
    //   );
    // }
    if (reading.calibrationResult == 'cancelled') {
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    if (_stage == _CalibrationStage.success || _completionHandled) return;

    if (!_isConnected && _stage != _CalibrationStage.intro) {
      setState(() => _stage = _CalibrationStage.disconnected);
      return;
    }

    // Sync progress from device
    _deviceElapsedMs = reading.calibrationElapsedMs;
    _devicePhase = reading.calibrationPhase;

    // Bug 1 fix: handle complete/failed immediately regardless of stage or elapsed
    // time. The old guard (stage != starting && elapsed > 2000ms) caused the UI
    // to stick on "Starting" forever when calibration failed in under 2 seconds.
    if (reading.calibrationResult.isNotEmpty && _startRequestedAt != null) {
      // Capture quality score and fail reason before transitioning
      _calibrationQuality = reading.calibrationQuality;
      _failReason = reading.calibrationFailReason;
      _handleCalibrationResult(reading.calibrationResult == 'complete');
      return;
    }
    // Bug 2 fix: duplicate 'cancelled' check removed (was dead code here;
    // already handled at the top of _onReading before this block).

    // Transition to getReady when device starts calibrating and phase is GET_READY
    if ((_stage == _CalibrationStage.starting ||
            _stage == _CalibrationStage.intro) &&
        reading.isCalibrating &&
        (reading.calibrationPhase == 'GET_READY' ||
            reading.calibrationPhase.isEmpty)) {
      _getReadyStartedAt ??= DateTime.now();
      setState(() => _stage = _CalibrationStage.getReady);
      return;
    }

    // Phase transitions from device (BLE-driven)
    // Bug 3 fix: set _bleHoldStillReceived so _onTick() wall-clock fallback
    // does not fire a second advance after BLE has already done it.
    if (_stage == _CalibrationStage.getReady && _devicePhase == 'HOLD_STILL') {
      _bleHoldStillReceived = true;
      _deviceHoldStartMs = _deviceElapsedMs;
      _holdStillStartedAt ??= DateTime.now();
      setState(() => _stage = _CalibrationStage.holdStill);
    }

    // Calibration cancelled from device
    if ((_stage == _CalibrationStage.getReady ||
            _stage == _CalibrationStage.holdStill) &&
        !reading.isCalibrating &&
        reading.calibrationResult.isEmpty) {
      _cancelMissCount++;
      if (_cancelMissCount >= 3) {
        if (mounted) Navigator.of(context).pop(false);
      }
    } else {
      _cancelMissCount = 0;
    }
  }

  void _handleCalibrationResult(bool success) {
    if (_completionHandled) return;
    _completionHandled = true;

    setState(() {
      _stage = success ? _CalibrationStage.success : _CalibrationStage.failed;
    });

    if (success) {
      HapticFeedback.lightImpact();
      // Save current angle as calibrated reference for deviation tracking
      AngleHistoryService().setReferenceAngle(
        widget.deviceService.currentAngle,
      );
      _successBarController.forward();

      _successAutoCloseTimer?.cancel();
      _successAutoCloseTimer = Timer(const Duration(milliseconds: 2200), () {
        if (!mounted || _closing) return;
        _closing = true;
        Navigator.of(context).pop(true);
      });
    } else {
      HapticFeedback.heavyImpact();
      _failedBarController.reset();
      _failedBarController.forward();
    }
  }

  void _onTick() {
    if (!mounted) return;
    if (_stage == _CalibrationStage.success || _completionHandled) return;

    if (!_isConnected && _stage != _CalibrationStage.intro) {
      setState(() => _stage = _CalibrationStage.disconnected);
      return;
    }

    if (_stage == _CalibrationStage.starting) {
      // Real-time disconnect check
      if (!_isConnected) {
        setState(() => _stage = _CalibrationStage.disconnected);
        return;
      }
      final elapsed = DateTime.now().difference(
        _startRequestedAt ?? DateTime.now(),
      );
      if (elapsed >= _startDetectTimeout) {
        setState(() => _stage = _CalibrationStage.failed);
        _failedBarController.forward();
      }
    }

    // Wall-clock auto-advance: firmware sends packets only at start/end,
    // so we drive phase transitions and progress locally.
    // Bug 3 fix: only advance via wall-clock when BLE has not already driven
    // the getReady→holdStill transition. Additionally, give BLE a 3-second
    // grace window after getReady started before the wall-clock fires, so a
    // late BLE packet is always preferred over the wall-clock fallback.
    if (_stage == _CalibrationStage.getReady) {
      final anchor = _getReadyStartedAt;
      if (anchor != null) {
        final wallElapsed = DateTime.now().difference(anchor).inMilliseconds;
        // 3-second grace beyond the normal getReady window gives BLE priority.
        if (!_bleHoldStillReceived && wallElapsed >= _getReadyMs + 3000) {
          // GET_READY timer expired and BLE gave no signal — advance via wall-clock
          _holdStillStartedAt = DateTime.now();
          setState(() => _stage = _CalibrationStage.holdStill);
          return;
        }
      }
      setState(() {});
    }

    if (_stage == _CalibrationStage.holdStill) {
      // If device stops sending packets and holdStill timer expires → fail
      final anchor = _holdStillStartedAt;
      if (anchor != null) {
        final wallElapsed = DateTime.now().difference(anchor).inMilliseconds;
        if (wallElapsed >= _holdStillMs + 15000) {
          // 15 sec grace beyond expected holdStill duration — device likely silent/disconnected
          _handleCalibrationResult(false);
          return;
        }
      }
      setState(() {});
    }
  }

  void _cancelCalibrationOnExit() {
    final inProgress =
        _stage == _CalibrationStage.starting ||
        _stage == _CalibrationStage.getReady ||
        _stage == _CalibrationStage.holdStill;
    if (inProgress && _isConnected) {
      widget.deviceService.sendCalibrationCancel();
    }
  }

  int get _getReadyMs => _fallbackGetReadyMs;
  int get _holdStillMs => _fallbackHoldStillMs;

  int? get _currentStep {
    switch (_stage) {
      case _CalibrationStage.intro:
        return 1;
      case _CalibrationStage.starting:
        return 2;
      case _CalibrationStage.getReady:
        return 3;
      case _CalibrationStage.holdStill:
        return 4;
      default:
        return null;
    }
  }

  String _buildFailMessage(String reason) {
    switch (reason) {
      case 'MOVEMENT_TOO_HIGH':
      case 'Too much movement':
      case 'Bad movement':
        return 'Movement detected during calibration.\nSit still and try again.';
      case 'LOW_BATTERY':
        return 'Battery too low.\nPlease charge your device first.';
      case 'SENSOR_NOT_INITIALIZED':
        return 'Sensor not ready.\nPlease restart the device.';
      case 'MOTOR_ACTIVE':
        return 'Therapy is running.\nStop therapy before calibrating.';
      case 'DEVICE_MOVING':
        return 'Device is moving.\nSit still before starting calibration.';
      case 'LOW_QUALITY':
        return 'Calibration quality too low.\nSit still and retry.';
      case 'CALIBRATION_UNSTABLE':
        return 'Calibration was unstable.\nSit upright and retry.';
      case 'Timeout':
        return 'Calibration timed out.\nPlease try again.';
      default:
        return 'Calibration failed.\nPlease try again.';
    }
  }

  String _qualityLabel(int quality) {
    if (quality >= 85) return 'Excellent';
    if (quality >= 70) return 'Good';
    if (quality >= 50) return 'Acceptable';
    return 'Low';
  }

  // Wall-clock elapsed for GET_READY phase
  int get _getReadyWallElapsedMs {
    final anchor = _getReadyStartedAt;
    if (anchor == null) return 0;
    return DateTime.now()
        .difference(anchor)
        .inMilliseconds
        .clamp(0, _getReadyMs);
  }

  // Wall-clock elapsed for HOLD_STILL phase
  int get _holdStillWallElapsedMs {
    final anchor = _holdStillStartedAt;
    if (anchor == null) return 0;
    return DateTime.now()
        .difference(anchor)
        .inMilliseconds
        .clamp(0, _holdStillMs);
  }

  int _getReadyRemainingSeconds() {
    final elapsedMs = _devicePhase == 'GET_READY' && _deviceElapsedMs > 0
        ? _deviceElapsedMs
        : _getReadyWallElapsedMs;
    final remainingMs = _getReadyMs - elapsedMs;
    if (remainingMs <= 0) return 0;
    return (remainingMs / 1000).ceil();
  }

  double _getReadyProgress() {
    final elapsedMs = _devicePhase == 'GET_READY' && _deviceElapsedMs > 0
        ? _deviceElapsedMs
        : _getReadyWallElapsedMs;
    return (elapsedMs / _getReadyMs).clamp(0.0, 1.0);
  }

  double _getHoldStillProgress() {
    final elapsedMs =
        _devicePhase == 'HOLD_STILL' && _deviceElapsedMs > _deviceHoldStartMs
        ? _deviceElapsedMs - _deviceHoldStartMs
        : _holdStillWallElapsedMs;
    return (elapsedMs / _holdStillMs).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final step = _currentStep;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _cancelCalibrationOnExit();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1A1D),
        body: SafeArea(
          child: Column(
            children: [
              if (step != null) _CalibrationStepBar(currentStep: step),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _buildStage(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    switch (_stage) {
      case _CalibrationStage.intro:
        return _IntroScreen(
          key: const ValueKey('intro'),
          initialName: _profileName,
          onStart: (name) {
            setState(() {
              _profileName = name;
            });
            unawaited(_startCalibration());
          },
          onCancel: () => Navigator.of(context).pop(false),
        );
      case _CalibrationStage.starting:
        return _StatusScreen(
          key: const ValueKey('starting'),
          title: 'Starting',
          message: 'Preparing your device...',
          icon: Icons.bluetooth_searching_rounded,
          color: const Color(0xFF008090),
        );
      case _CalibrationStage.getReady:
        return _GetReadyScreen(
          key: const ValueKey('get_ready'),
          countdown: _getReadyRemainingSeconds(),
          progress: _getReadyProgress(),
          pulse: _pulseController,
        );
      case _CalibrationStage.holdStill:
        return _HoldStillScreen(
          key: const ValueKey('hold_still'),
          progress: _getHoldStillProgress(),
          pulse: _pulseController,
        );
      case _CalibrationStage.failed:
        return _ResultScreen(
          key: const ValueKey('failed'),
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFEF4444),
          title: 'Calibration Failed',
          message: _buildFailMessage(_failReason),
          showFailedBar: true,
          barProgress: _failedBarController,
          primaryLabel: 'Retry Calibration',
          onPrimary: () {
            _failedBarController.reset();
            unawaited(_startCalibration());
          },
        );
      case _CalibrationStage.success:
        return _ResultScreen(
          key: const ValueKey('success'),
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF14B8A6),
          title: 'Calibration Complete',
          message:
              'Your ideal posture has been saved.\nPosture tracking started.',
          subText: _calibrationQuality > 0
              ? 'Quality: ${_qualityLabel(_calibrationQuality)} ($_calibrationQuality%)'
              : 'Auto return → Training Screen',
          showSuccessBar: true,
          barProgress: _successBarController,
        );
      case _CalibrationStage.disconnected:
        return _ResultScreen(
          key: const ValueKey('disconnected'),
          icon: Icons.bluetooth_disabled_rounded,
          color: const Color(0xFFEF4444),
          title: 'Device Disconnected',
          message: 'Reconnect your device to continue calibration.',
          primaryLabel: 'Back',
          onPrimary: () => Navigator.of(context).pop(false),
        );
    }
  }
}

// ── Step indicator bar ──────────────────────────────────────────────────────

class _CalibrationStepBar extends StatelessWidget {
  const _CalibrationStepBar({required this.currentStep});

  final int currentStep; // 1-based, max 4

  static const _labels = ['Setup', 'Connecting', 'Get Ready', 'Hold Still'];
  static const _totalSteps = 4;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (int i = 1; i <= _totalSteps; i++) ...[
                _StepDot(index: i, currentStep: currentStep),
                if (i < _totalSteps)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        gradient: i < currentStep
                            ? const LinearGradient(
                                colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
                              )
                            : null,
                        color: i >= currentStep
                            ? Colors.white.withValues(alpha: 0.12)
                            : null,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Step $currentStep of $_totalSteps',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '— ${_labels[currentStep - 1]}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFA855F7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.index, required this.currentStep});

  final int index;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final isDone = index < currentStep;
    final isActive = index == currentStep;

    final bg = isDone
        ? const Color(0xFFA855F7)
        : isActive
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.06);
    final border = isActive
        ? const Color(0xFFA855F7)
        : Colors.transparent;
    final size = isActive ? 24.0 : 20.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: border, width: 2),
      ),
      child: isDone
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : isActive
              ? Center(
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFA855F7),
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
    );
  }
}

// ── Calibration screens ─────────────────────────────────────────────────────

class _IntroScreen extends StatefulWidget {
  const _IntroScreen({
    super.key,
    required this.initialName,
    required this.onStart,
    required this.onCancel,
  });

  final String initialName;
  final ValueChanged<String> onStart;
  final VoidCallback onCancel;

  @override
  State<_IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<_IntroScreen> {
  late final TextEditingController _nameController;
  final List<String> _defaults = const ['Office', 'Home', 'Car', 'Gym'];
  String _selectedDefault = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    if (_defaults.contains(widget.initialName)) {
      _selectedDefault = widget.initialName;
    }
    _nameController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _nameController.text.trim();
    if (_defaults.contains(text)) {
      if (_selectedDefault != text) {
        setState(() {
          _selectedDefault = text;
        });
      }
    } else {
      if (_selectedDefault.isNotEmpty) {
        setState(() {
          _selectedDefault = '';
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 60),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    'Calibrate Posture',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Set your ideal sitting posture for accurate tracking.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.65),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.airline_seat_recline_normal_rounded,
                          size: 44,
                          color: const Color(0xFF008090).withValues(alpha: 0.9),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Sit comfortably in your natural upright posture.\nKeep your back straight and shoulders relaxed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.8),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Calibration Name',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    maxLength: 23,
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    decoration: InputDecoration(
                      hintText: 'Enter name (e.g. Office)',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF008090),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _defaults.map((name) {
                        final isSelected = _selectedDefault == name;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _nameController.text = name;
                            _nameController.selection =
                                TextSelection.fromPosition(
                                  TextPosition(offset: name.length),
                                );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFFA855F7),
                                        Color(0xFFEC4899),
                                      ],
                                    )
                                  : null,
                              color: isSelected
                                  ? null
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.transparent
                                    : Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Text(
                              name,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () {
                            final name = _nameController.text.trim();
                            widget.onStart(name.isEmpty ? 'Profile' : name);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: const Center(
                            child: Text(
                              'Start Calibration',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusScreen extends StatelessWidget {
  const _StatusScreen({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: key,
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _GetReadyScreen extends StatelessWidget {
  const _GetReadyScreen({
    super.key,
    required this.countdown,
    required this.progress,
    required this.pulse,
  });

  final int countdown;
  final double progress;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final cue = countdown >= 3
        ? 'Find your natural upright posture'
        : countdown == 2
        ? 'Relax your shoulders'
        : countdown == 1
        ? 'Tiny movements are okay. Big shifts are not.'
        : 'Starting now';

    return Container(
      key: key,
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Get Ready',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Sit how you want AlignEye to remember you.\nThis becomes your posture baseline.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          _CalibrationCoachCard(
            icon: Icons.self_improvement_rounded,
            label: 'Before we measure',
            message: cue,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 28),
          ScaleTransition(
            scale: Tween<double>(
              begin: 0.97,
              end: 1.03,
            ).animate(CurvedAnimation(parent: pulse, curve: Curves.easeInOut)),
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                  width: 3,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 130,
                    height: 130,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 4,
                      color: const Color(0xFFF59E0B),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  Text(
                    countdown > 0 ? '$countdown' : '',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              countdown > 0 ? 'Measuring in $countdown' : 'Here we go',
              key: ValueKey(countdown),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.68),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldStillScreen extends StatelessWidget {
  const _HoldStillScreen({
    super.key,
    required this.progress,
    required this.pulse,
  });

  final double progress;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final progressPercent = (progress.clamp(0.0, 1.0) * 100).round();
    final cue = progress < 0.25
        ? 'Stay easy. No need to freeze.'
        : progress < 0.50
        ? 'Soft jaw, relaxed shoulders.'
        : progress < 0.75
        ? 'Nice. Keep your neck in the same spot.'
        : progress < 1.0
        ? 'Almost saved. Hold this posture.'
        : 'Saving your baseline.';

    return Container(
      key: key,
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Hold Still',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Align pod is learning your neutral angle.\nBreathe normally and keep your head steady.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          _CalibrationCoachCard(
            icon: Icons.tips_and_updates_rounded,
            label: 'Calibration cue',
            message: cue,
            color: const Color(0xFF22C55E),
          ),
          const SizedBox(height: 28),
          ScaleTransition(
            scale: Tween<double>(
              begin: 0.98,
              end: 1.02,
            ).animate(CurvedAnimation(parent: pulse, curve: Curves.easeInOut)),
            child: SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      color: const Color(0xFF22C55E),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.accessibility_new_rounded,
                        size: 56,
                        color: const Color(0xFF22C55E).withValues(alpha: 0.9),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        progress >= 1.0 ? 'Saving...' : 'Calibrating...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$progressPercent%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalibrationCoachCard extends StatelessWidget {
  const _CalibrationCoachCard({
    required this.icon,
    required this.label,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(message),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.26)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.14),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color.withValues(alpha: 0.95),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: Colors.white.withValues(alpha: 0.86),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultScreen extends StatelessWidget {
  const _ResultScreen({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.subText,
    this.showSuccessBar = false,
    this.showFailedBar = false,
    this.barProgress,
    this.primaryLabel,
    this.onPrimary,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String? subText;
  final bool showSuccessBar;
  final bool showFailedBar;
  final AnimationController? barProgress;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Center(
      child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showSuccessBar) ...[
            Lottie.asset(
              'assets/animations/sucess.json',
              width: 160,
              height: 160,
              repeat: true,
            ),
          ],
          if (showFailedBar) ...[
            Lottie.asset(
              'assets/animations/Failed.json',
              width: 160,
              height: 160,
              repeat: true,
            ),
          ],
          if (!showFailedBar && !showSuccessBar)
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: color, size: 44),
            ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.5,
            ),
          ),
          if (subText != null) ...[
            const SizedBox(height: 10),
            Text(
              subText!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
          const SizedBox(height: 32),
          if (primaryLabel != null && onPrimary != null)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF008090),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  primaryLabel!,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    )));
  }
}
