import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const _kCharacteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
const _kDefaultDeviceNamePrefix = 'align pod';

enum DeviceConnectionStatus { disconnected, connecting, connected }

/// Result of a pre-flight Bluetooth readiness check.
enum BleReadiness {
  ready,
  bluetoothUnsupported,
  bluetoothOff,
  permissionDenied,
  permissionPermanentlyDenied,
}

class _ScanCandidate {
  const _ScanCandidate({
    required this.device,
    required this.rssi,
    required this.isBonded,
  });

  final BluetoothDevice device;
  final int rssi;
  final bool isBonded;
}

class LiveTelemetry {
  final int seq;
  final int ms;
  final int rev;
  final String mode;
  final String subMode;
  final double angle;
  final bool isBadPosture;
  final String posture;
  final DateTime timestamp;

  LiveTelemetry({
    required this.seq,
    required this.ms,
    required this.rev,
    required this.mode,
    required this.subMode,
    required this.angle,
    required this.isBadPosture,
    required this.posture,
    required this.timestamp,
  });

  factory LiveTelemetry.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }
    return LiveTelemetry(
      seq: toInt(json['seq']),
      ms: toInt(json['ms']),
      rev: toInt(json['rev']),
      mode: json['mode']?.toString() ?? 'UNKNOWN',
      subMode: json['sub']?.toString() ?? 'UNKNOWN',
      angle: toDouble(json['angle']),
      isBadPosture: toInt(json['bad']) != 0,
      posture: json['posture']?.toString() ?? 'UNKNOWN',
      timestamp: DateTime.now(),
    );
  }
}

class DeviceStatus {
  final int rev;
  final String source;
  final String reason;
  final String mode;
  final String subMode;
  final String trainingAlert;
  final int therapyDurationMin;
  final int therapyIntensity;
  final int difficultyDeg;
  final int batteryPct;
  final int batteryMv;
  final bool charging;
  final bool calibrating;
  final String calPhase;
  final int calElapsedMs;
  final int calTotalMs;
  final String calResult;
  final bool sessionActive;
  final String sessionType;
  final int sessionId;
  final int sessionElapsedSec;
  final int sessionBadCount;
  final bool therapyActive;
  final String therapyPattern;
  final String therapyNext;
  final int therapyElapsedSec;
  final int therapyRemainingSec;
  final int therapyCurrentIndex;
  final int therapyTotalPatterns;
  final int steps;
  final bool sensorOk;
  final String fw;
  final DateTime timestamp;

  DeviceStatus({
    required this.rev,
    required this.source,
    required this.reason,
    required this.mode,
    required this.subMode,
    required this.trainingAlert,
    required this.therapyDurationMin,
    required this.therapyIntensity,
    required this.difficultyDeg,
    required this.batteryPct,
    required this.batteryMv,
    required this.charging,
    required this.calibrating,
    required this.calPhase,
    required this.calElapsedMs,
    required this.calTotalMs,
    required this.calResult,
    required this.sessionActive,
    required this.sessionType,
    required this.sessionId,
    required this.sessionElapsedSec,
    required this.sessionBadCount,
    required this.therapyActive,
    required this.therapyPattern,
    required this.therapyNext,
    required this.therapyElapsedSec,
    required this.therapyRemainingSec,
    required this.therapyCurrentIndex,
    required this.therapyTotalPatterns,
    required this.steps,
    required this.sensorOk,
    required this.fw,
    required this.timestamp,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }
    bool toBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value.toInt() != 0;
      return value?.toString() == 'true' || toInt(value) != 0;
    }
    return DeviceStatus(
      rev: toInt(json['rev']),
      source: json['source']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      mode: json['mode']?.toString() ?? 'UNKNOWN',
      subMode: json['sub']?.toString() ?? 'UNKNOWN',
      trainingAlert: json['training_alert']?.toString() ?? 'INSTANT',
      therapyDurationMin: toInt(json['therapy_duration_min']),
      therapyIntensity: toInt(json['therapy_intensity']),
      difficultyDeg: toInt(json['difficulty_deg'] ?? json['difficulty']),
      batteryPct: toInt(json['battery_pct']),
      batteryMv: toInt(json['battery_mv']),
      charging: toBool(json['charging']),
      calibrating: toBool(json['calibrating']),
      calPhase: json['cal_phase']?.toString() ?? 'IDLE',
      calElapsedMs: toInt(json['cal_elapsed_ms']),
      calTotalMs: toInt(json['cal_total_ms']),
      calResult: json['cal_result']?.toString() ?? '',
      sessionActive: toBool(json['session_active']),
      sessionType: json['session_type']?.toString() ?? '',
      sessionId: toInt(json['session_id']),
      sessionElapsedSec: toInt(json['session_elapsed_sec']),
      sessionBadCount: toInt(json['session_bad_count']),
      therapyActive: toBool(json['therapy_active']),
      therapyPattern: json['therapy_pattern']?.toString() ?? '',
      therapyNext: json['therapy_next']?.toString() ?? '',
      therapyElapsedSec: toInt(json['therapy_elapsed_sec']),
      therapyRemainingSec: toInt(json['therapy_remaining_sec']),
      therapyCurrentIndex: toInt(json['therapy_current_index']),
      therapyTotalPatterns: toInt(json['therapy_total_patterns']),
      steps: toInt(json['steps']),
      sensorOk: toBool(json['sensor_ok']),
      fw: json['fw']?.toString() ?? '',
      timestamp: DateTime.now(),
    );
  }
}

class CommandAck {
  final int seq;
  final bool ok;
  final int rev;
  final String cmd;
  final String reason;

  CommandAck({
    required this.seq,
    required this.ok,
    required this.rev,
    required this.cmd,
    required this.reason,
  });

  factory CommandAck.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }
    bool toBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value.toInt() != 0;
      return value?.toString() == 'true' || toInt(value) != 0;
    }
    return CommandAck(
      seq: toInt(json['seq']),
      ok: toBool(json['ok']),
      rev: toInt(json['rev']),
      cmd: json['cmd']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
    );
  }
}

class DeviceEvent {
  final int rev;
  final String event;
  final bool ok;

  DeviceEvent({
    required this.rev,
    required this.event,
    required this.ok,
  });

  factory DeviceEvent.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }
    bool toBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value.toInt() != 0;
      return value?.toString() == 'true' || toInt(value) != 0;
    }
    return DeviceEvent(
      rev: toInt(json['rev']),
      event: json['event']?.toString() ?? '',
      ok: toBool(json['ok']),
    );
  }
}

class DebugTelemetry {
  final double rawX;
  final double rawY;
  final double rawZ;
  final double calY;
  final double calZ;
  final double angX;
  final double angY;
  final double angZ;
  final DateTime timestamp;

  DebugTelemetry({
    required this.rawX,
    required this.rawY,
    required this.rawZ,
    required this.calY,
    required this.calZ,
    required this.angX,
    required this.angY,
    required this.angZ,
    required this.timestamp,
  });

  factory DebugTelemetry.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }
    return DebugTelemetry(
      rawX: toDouble(json['raw_x']),
      rawY: toDouble(json['raw_y']),
      rawZ: toDouble(json['raw_z']),
      calY: toDouble(json['cal_y']),
      calZ: toDouble(json['cal_z']),
      angX: toDouble(json['ang_x']),
      angY: toDouble(json['ang_y']),
      angZ: toDouble(json['ang_z']),
      timestamp: DateTime.now(),
    );
  }
}

class PostureReading {
  final String mode;
  final String subMode;
  final double angle;
  final bool isCalibrating;
  final String calibrationResult;
  final int calibrationElapsedMs;
  final int calibrationTotalMs;
  final String calibrationPhase;
  final String posture;
  final bool isBadPosture;
  final double batteryVoltage;
  final int batteryPercentage;
  final int difficultyDeg;
  final String therapyPattern;
  final String therapyNextPattern;
  final int therapyElapsedSeconds;
  final int therapyRemainingSeconds;
  final int therapyIntensityLevel;
  final int therapyCurrentPatternIndex;
  final int therapyTotalPatterns;
  final int liveSessionId;
  final int liveSessionElapsedSeconds;
  final int liveSessionStartEpoch;
  final int liveSessionBadCount;
  final DateTime timestamp;

  const PostureReading({
    required this.mode,
    required this.subMode,
    required this.angle,
    required this.isCalibrating,
    required this.calibrationResult,
    required this.calibrationElapsedMs,
    required this.calibrationTotalMs,
    required this.calibrationPhase,
    required this.posture,
    required this.isBadPosture,
    required this.batteryVoltage,
    required this.batteryPercentage,
    required this.difficultyDeg,
    required this.therapyPattern,
    required this.therapyNextPattern,
    required this.therapyElapsedSeconds,
    required this.therapyRemainingSeconds,
    required this.therapyIntensityLevel,
    required this.therapyCurrentPatternIndex,
    required this.therapyTotalPatterns,
    required this.liveSessionId,
    required this.liveSessionElapsedSeconds,
    required this.liveSessionStartEpoch,
    required this.liveSessionBadCount,
    required this.timestamp,
  });

  PostureReading copyWith({
    String? mode,
    String? subMode,
    double? angle,
    bool? isCalibrating,
    String? calibrationResult,
    int? calibrationElapsedMs,
    int? calibrationTotalMs,
    String? calibrationPhase,
    String? posture,
    bool? isBadPosture,
    double? batteryVoltage,
    int? batteryPercentage,
    int? difficultyDeg,
    String? therapyPattern,
    String? therapyNextPattern,
    int? therapyElapsedSeconds,
    int? therapyRemainingSeconds,
    int? therapyIntensityLevel,
    int? therapyCurrentPatternIndex,
    int? therapyTotalPatterns,
    int? liveSessionId,
    int? liveSessionElapsedSeconds,
    int? liveSessionStartEpoch,
    int? liveSessionBadCount,
    DateTime? timestamp,
  }) {
    return PostureReading(
      mode: mode ?? this.mode,
      subMode: subMode ?? this.subMode,
      angle: angle ?? this.angle,
      isCalibrating: isCalibrating ?? this.isCalibrating,
      calibrationResult: calibrationResult ?? this.calibrationResult,
      calibrationElapsedMs: calibrationElapsedMs ?? this.calibrationElapsedMs,
      calibrationTotalMs: calibrationTotalMs ?? this.calibrationTotalMs,
      calibrationPhase: calibrationPhase ?? this.calibrationPhase,
      posture: posture ?? this.posture,
      isBadPosture: isBadPosture ?? this.isBadPosture,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      batteryPercentage: batteryPercentage ?? this.batteryPercentage,
      difficultyDeg: difficultyDeg ?? this.difficultyDeg,
      therapyPattern: therapyPattern ?? this.therapyPattern,
      therapyNextPattern: therapyNextPattern ?? this.therapyNextPattern,
      therapyElapsedSeconds: therapyElapsedSeconds ?? this.therapyElapsedSeconds,
      therapyRemainingSeconds: therapyRemainingSeconds ?? this.therapyRemainingSeconds,
      therapyIntensityLevel: therapyIntensityLevel ?? this.therapyIntensityLevel,
      therapyCurrentPatternIndex: therapyCurrentPatternIndex ?? this.therapyCurrentPatternIndex,
      therapyTotalPatterns: therapyTotalPatterns ?? this.therapyTotalPatterns,
      liveSessionId: liveSessionId ?? this.liveSessionId,
      liveSessionElapsedSeconds: liveSessionElapsedSeconds ?? this.liveSessionElapsedSeconds,
      liveSessionStartEpoch: liveSessionStartEpoch ?? this.liveSessionStartEpoch,
      liveSessionBadCount: liveSessionBadCount ?? this.liveSessionBadCount,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  factory PostureReading.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool toBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value.toInt() != 0;
      return value?.toString() == 'true' || toInt(value) != 0;
    }

    return PostureReading(
      mode: json['mode']?.toString() ?? 'UNKNOWN',
      subMode: json['sub_mode']?.toString() ?? 'UNKNOWN',
      angle: toDouble(json['angle']),
      isCalibrating: toBool(json['is_calibrating']),
      calibrationResult: json['calibration_result']?.toString() ?? '',
      calibrationElapsedMs: toInt(
        json['c_elap'] ?? json['calibration_elapsed_ms'],
      ),
      calibrationTotalMs: toInt(json['c_tot'] ?? json['calibration_total_ms']),
      calibrationPhase: (json['c_phase']?.toString() ?? 'IDLE').toUpperCase(),
      posture: json['posture']?.toString() ?? 'UNKNOWN',
      isBadPosture: toBool(json['is_bad_posture']),
      batteryVoltage: toDouble(json['battery_voltage']),
      batteryPercentage: toInt(json['battery_percentage']),
      difficultyDeg: toInt(json['difficulty_deg']),
      therapyPattern:
          (json['t_patt'] ?? json['therapy_pattern'])?.toString() ?? '',
      therapyNextPattern:
          (json['t_next'] ?? json['therapy_next_pattern'])?.toString() ?? '',
      therapyElapsedSeconds: toInt(
        json['t_elap'] ?? json['therapy_elapsed_sec'],
      ),
      therapyRemainingSeconds: toInt(
        json['t_rem'] ?? json['therapy_remaining_sec'],
      ),
      therapyIntensityLevel: toInt(
        json['t_lvl'] ?? json['therapy_intensity_level'],
      ),
      therapyCurrentPatternIndex: () {
        final raw = json['t_cur'] ?? json['therapy_current_pattern_index'];
        if (raw == null) return -1;
        if (raw is int) return raw;
        if (raw is num) return raw.toInt();
        return int.tryParse(raw.toString()) ?? -1;
      }(),
      therapyTotalPatterns: toInt(
        json['t_total'] ?? json['therapy_total_patterns'],
      ),
      liveSessionId: toInt(json['s_id'] ?? json['session_id']),
      liveSessionElapsedSeconds: toInt(
        json['s_elap'] ?? json['session_elapsed_sec'],
      ),
      liveSessionStartEpoch: toInt(
        json['s_start'] ?? json['session_start_epoch'],
      ),
      liveSessionBadCount: toInt(json['s_bad'] ?? json['session_bad_count']),
      timestamp: DateTime.now(),
    );
  }

  String toCompactString() {
    return 'mode=$mode, sub=$subMode, angle=${angle.round()}, '
        'calibrating=$isCalibrating, posture=$posture, bad=$isBadPosture, '
        'battery=${batteryVoltage.toStringAsFixed(2)}V ($batteryPercentage%), '
        'difficulty=$difficultyDeg, therapyNow=$therapyPattern, '
        'therapyNext=$therapyNextPattern, '
        'therapyElapsed=$therapyElapsedSeconds, '
        'therapyRemaining=$therapyRemainingSeconds, '
        'sessionId=$liveSessionId, sessionElapsed=$liveSessionElapsedSeconds';
  }
}

class AlignEyeDeviceService {
  AlignEyeDeviceService({String deviceNamePrefix = _kDefaultDeviceNamePrefix})
    : _deviceNamePrefix = deviceNamePrefix;

  final String _deviceNamePrefix;
  final _readingController = StreamController<PostureReading>.broadcast();
  final connectionStatus = ValueNotifier<DeviceConnectionStatus>(
    DeviceConnectionStatus.disconnected,
  );
  final isAutoConnectionAttempt = ValueNotifier<bool>(false);
  final currentReading = ValueNotifier<PostureReading?>(null);
  DateTime? _lastUiFrame;
  Timer? _dataWatchdogTimer;
  DateTime? _lastDataReceivedAt;

  // Pending commands ValueNotifiers
  final pendingMode = ValueNotifier<String?>(null);
  final pendingSubMode = ValueNotifier<String?>(null);
  final pendingDifficulty = ValueNotifier<int?>(null);

  // Command sequence and map
  int _nextCommandSeq = 1;
  final Map<int, String> _pendingCommandNames = {};

  // Revision and sequence debugging
  int? latestDeviceRevision;
  int? _lastLiveSeq;

  // Broadcast controllers for ACK, Event, and Debug packets
  final _ackController = StreamController<CommandAck>.broadcast();
  final _eventController = StreamController<DeviceEvent>.broadcast();
  final _debugController = StreamController<DebugTelemetry>.broadcast();

  Stream<CommandAck> get acks => _ackController.stream;
  Stream<DeviceEvent> get deviceEvents => _eventController.stream;
  Stream<DebugTelemetry> get debugTelemetry => _debugController.stream;

  /// Sticky cache of the latest therapy pattern plan + live index. Firmware
  /// publishes `t_seq` / `t_cur` only periodically (not every JSON frame),
  /// so a page re-entering therapy mid-session would otherwise see an empty
  /// plan for several seconds and flash the "Getting your therapy session
  /// ready…" placeholder. Caching here lets the ongoing page seed itself
  /// instantly from the last known plan.
  List<int> latestTherapyPatternSequence = const [];
  int latestTherapyCurrentPatternIndex = -1;
  int latestTherapyTotalPatterns = 0;
  String latestTherapyPatternName = '';
  String latestTherapyNextPatternName = '';

  /// Single source of truth for the therapy countdown so every UI surface
  /// (home mini card + immersive ongoing page) reads the same number.
  /// [_therapyRemainingAnchorSec] holds the remaining seconds *at the
  /// moment firmware reported them*, and [_therapyAnchorAt] is the wall
  /// clock for that report. Consumers derive live remaining via
  /// [therapyRemainingSecondsNow] which just subtracts elapsed wall time.
  int _therapyRemainingAnchorSec = -1;
  int _therapyElapsedAnchorSec = 0;
  DateTime? _therapyAnchorAt;

  /// Latest firmware-reported remaining seconds, extrapolated to "right now"
  /// by the wall clock. Returns -1 when no therapy frame has been seen yet.
  int get therapyRemainingSecondsNow {
    final anchor = _therapyAnchorAt;
    if (anchor == null || _therapyRemainingAnchorSec < 0) return -1;
    final elapsed = DateTime.now().difference(anchor).inSeconds;
    final value = _therapyRemainingAnchorSec - elapsed;
    return value < 0 ? 0 : value;
  }

  /// Mirror of [therapyRemainingSecondsNow] for elapsed-side progress.
  int get therapyElapsedSecondsNow {
    final anchor = _therapyAnchorAt;
    if (anchor == null) return 0;
    final elapsed = DateTime.now().difference(anchor).inSeconds;
    final value = _therapyElapsedAnchorSec + elapsed;
    return value < 0 ? 0 : value;
  }

  /// Session-elapsed value at which the currently-playing pattern started.
  /// Updated whenever firmware reports a different pattern name. Combined
  /// with [therapyElapsedSecondsNow] this gives a "pattern elapsed" clock
  /// that both the mini home card and the immersive page can share.
  int _currentPatternStartElapsedSec = 0;
  int get therapyPatternElapsedSecondsNow {
    final value = therapyElapsedSecondsNow - _currentPatternStartElapsedSec;
    return value < 0 ? 0 : value;
  }

  BluetoothDevice? _device;
  BluetoothDevice? get device => _device;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  String _buffer = '';
  bool _userInitiatedDisconnect = false;
  bool _isConnecting = false;
  Timer? _connectionTimeoutTimer;
  Timer? _reconnectTimer;
  Timer? _syncRetryTimer;
  int _connectionRetryCount = 0;
  static const int _maxRetries = 1;
  static const Duration _connectionTimeout = Duration(seconds: 12);
  static const Duration _serviceDiscoveryTimeout = Duration(seconds: 8);
  static const Duration _defaultScanTimeout = Duration(seconds: 3);

  bool get _isAndroid12OrAbove {
    if (!Platform.isAndroid) {
      return false;
    }

    // SDK 31 (Android 12) introduced runtime BLUETOOTH_SCAN/CONNECT permissions.
    return (int.tryParse(Platform.operatingSystemVersion) ?? 0) >= 31;
  }

  // Persistent storage keys
  static const String _keyHasEverConnected = 'bluetooth_has_ever_connected';
  static const String _keyLastConnectedDeviceId =
      'bluetooth_last_connected_device_id';
  static const MethodChannel _bondChannel = MethodChannel(
      'com.correctv1.bluetooth/unpair',
  );

  Stream<PostureReading> get readings => _readingController.stream;

  // Convenience getters for current reading values
  String get currentMode => currentReading.value?.mode ?? 'UNKNOWN';
  String get currentSubMode => currentReading.value?.subMode ?? 'UNKNOWN';
  double get currentAngle => currentReading.value?.angle ?? 0.0;
  bool get currentIsCalibrating => currentReading.value?.isCalibrating ?? false;
  String get currentPosture => currentReading.value?.posture ?? 'UNKNOWN';
  bool get currentIsBadPosture => currentReading.value?.isBadPosture ?? false;
  double get currentBatteryVoltage =>
      currentReading.value?.batteryVoltage ?? 0.0;
  int get currentBatteryPercentage =>
      currentReading.value?.batteryPercentage ?? 0;
  int get currentDifficultyDeg => currentReading.value?.difficultyDeg ?? 25;
  String get currentTherapyPattern =>
      currentReading.value?.therapyPattern ?? '';
  String get currentTherapyNextPattern =>
      currentReading.value?.therapyNextPattern ?? '';
  int get currentTherapyElapsedSeconds =>
      currentReading.value?.therapyElapsedSeconds ?? 0;
  int get currentTherapyRemainingSeconds =>
      currentReading.value?.therapyRemainingSeconds ?? 0;
  int get currentTherapyIntensityLevel =>
      currentReading.value?.therapyIntensityLevel ?? 0;
  int get currentLiveSessionElapsedSeconds =>
      currentReading.value?.liveSessionElapsedSeconds ?? 0;

  Future<bool> _sendJsonCommand(String commandName, [Map<String, dynamic>? params]) async {
    final characteristic = _notifyCharacteristic;
    if (characteristic == null) {
      return false;
    }
    final seq = _nextCommandSeq++;
    final payload = {
      't': 'cmd',
      'seq': seq,
      'cmd': commandName,
      if (params != null) ...params,
    };
    
    _pendingCommandNames[seq] = commandName;
    
    final jsonStr = jsonEncode(payload);
    final sent = await _writeTextCommand(jsonStr);
    if (!sent) {
      _pendingCommandNames.remove(seq);
    }
    return sent;
  }

  Future<bool> sendMode(String mode) async {
    final modeUpper = mode.toUpperCase();
    pendingMode.value = modeUpper;
    final sent = await _sendJsonCommand('set_mode', {'mode': modeUpper});
    if (!sent) {
      pendingMode.value = null;
    }
    return sent;
  }

  Future<bool> sendTrainingAlert(String alert) async {
    final alertUpper = alert.toUpperCase();
    pendingSubMode.value = alertUpper;
    final sent = await _sendJsonCommand('set_training_alert', {'sub': alertUpper});
    if (!sent) {
      pendingSubMode.value = null;
    }
    return sent;
  }

  Future<bool> sendTherapyDuration(int durationMin) async {
    final subMode = '${durationMin}_MIN';
    pendingSubMode.value = subMode;
    final sent = await _sendJsonCommand('set_therapy_duration', {'min': durationMin});
    if (!sent) {
      pendingSubMode.value = null;
    }
    return sent;
  }

  Future<bool> sendTherapyIntensity(int intensityLevel) async {
    final clampedLevel = intensityLevel.clamp(1, 3);
    return _sendJsonCommand('set_therapy_intensity', {'level': clampedLevel});
  }

  Future<bool> sendCalibrationStart() async {
    return _sendJsonCommand('start_calibration');
  }

  Future<bool> sendCalibrationCancel() async {
    return _sendJsonCommand('cancel_calibration');
  }

  Future<bool> sendDifficulty(int difficultyDeg) async {
    pendingDifficulty.value = difficultyDeg;
    final sent = await _sendJsonCommand('set_difficulty', {'deg': difficultyDeg});
    if (!sent) {
      pendingDifficulty.value = null;
    }
    return sent;
  }

  Future<bool> requestStatus() async {
    return _sendJsonCommand('request_status');
  }

  Future<bool> enterDfu() async {
    return _sendJsonCommand('enter_dfu');
  }

  Future<void> sendModeControl({
    required String mode,
    required String postureTiming,
    required int therapyDurationMinutes,
    required int difficultyDegrees,
  }) async {
    await sendMode(mode);
    await sendTrainingAlert(postureTiming);
    await sendDifficulty(difficultyDegrees);
  }

  /// Start a therapy session on the device with a specific duration and
  /// intensity level (1-3). Returns true if the command was written successfully.
  Future<bool> sendTherapyStart({
    required int durationMinutes,
    required int intensityLevel,
  }) async {
    final durationSent = await sendTherapyDuration(durationMinutes);
    if (!durationSent) return false;
    
    final intensitySent = await sendTherapyIntensity(intensityLevel);
    if (!intensitySent) return false;
    
    return await sendMode('THERAPY');
  }

  /// Stop an in-progress therapy session and return the device to tracking.
  Future<bool> sendTherapyStop() async {
    return await sendMode('TRACKING');
  }

  /// Sends the current phone date/time and timezone to the device.
  Future<bool> sendDateTime() async {
    final now = DateTime.now();
    final epochSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final tzOffsetSeconds = now.timeZoneOffset.inSeconds;
    return _writeTextCommand('TIME=$epochSeconds;TZ=$tzOffsetSeconds');
  }

  Future<bool> _writeTextCommand(String payload) async {
    final characteristic = _notifyCharacteristic;
    if (characteristic == null) {
      return false;
    }

    if (!characteristic.properties.write &&
        !characteristic.properties.writeWithoutResponse) {
      debugPrint('Write skipped: characteristic is not writable');
      return false;
    }

    try {
      await characteristic.write(
        utf8.encode(payload),
        withoutResponse: characteristic.properties.writeWithoutResponse,
      );
      debugPrint('Command sent: $payload');
      return true;
    } catch (e) {
      debugPrint('Failed to send command "$payload": $e');
      return false;
    }
  }

  /// Lightweight pre-flight check.  Returns [BleReadiness.ready] when the
  /// adapter is on and all runtime permissions have been granted.
  /// Does NOT start a scan or connection – call [connect] afterwards.
  Future<BleReadiness> checkReadiness() async {
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) return BleReadiness.bluetoothUnsupported;

    // Check permissions first (Android only; iOS returns true).
    if (defaultTargetPlatform == TargetPlatform.android) {
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;

      if (scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied) {
        return BleReadiness.permissionPermanentlyDenied;
      }

      if (!scanStatus.isGranted) {
        final result = await Permission.bluetoothScan.request();
        if (result.isPermanentlyDenied) {
          return BleReadiness.permissionPermanentlyDenied;
        }
        if (!result.isGranted) return BleReadiness.permissionDenied;
      }

      if (!connectStatus.isGranted) {
        final result = await Permission.bluetoothConnect.request();
        if (result.isPermanentlyDenied) {
          return BleReadiness.permissionPermanentlyDenied;
        }
        if (!result.isGranted) return BleReadiness.permissionDenied;
      }

      if (!_isAndroid12OrAbove) {
        final locStatus = await Permission.location.status;
        if (locStatus.isPermanentlyDenied) {
          return BleReadiness.permissionPermanentlyDenied;
        }
        if (!locStatus.isGranted) {
          final result = await Permission.location.request();
          if (result.isPermanentlyDenied) {
            return BleReadiness.permissionPermanentlyDenied;
          }
          if (!result.isGranted) return BleReadiness.permissionDenied;
        }
      }
    }

    // Check adapter state.
    try {
      final adapterState = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 2),
      );
      if (adapterState != BluetoothAdapterState.on) {
        return BleReadiness.bluetoothOff;
      }
    } catch (_) {
      return BleReadiness.bluetoothOff;
    }

    return BleReadiness.ready;
  }

  Future<void> connect({bool isAutoConnect = false}) async {
    // Prevent concurrent connection attempts
    if (_isConnecting) {
      debugPrint('Connection already in progress, ignoring duplicate request');
      return;
    }

    if (connectionStatus.value == DeviceConnectionStatus.connected) {
      debugPrint('Already connected, skipping connection attempt');
      return;
    }

    // Don't auto-connect if user manually disconnected (only during current session)
    // Note: This flag is reset to false when app starts, so it only blocks during the same session
    if (isAutoConnect && _userInitiatedDisconnect) {
      debugPrint(
        'CONNECT: Skipping auto-connect - user manually disconnected during this session',
      );
      return;
    }

    // Reset retry count for new connection attempt
    if (connectionStatus.value == DeviceConnectionStatus.disconnected) {
      _connectionRetryCount = 0;
    }

    _isConnecting = true;
    isAutoConnectionAttempt.value = isAutoConnect;

    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        _isConnecting = false;
        connectionStatus.value = DeviceConnectionStatus.disconnected;
        return;
      }

      if (isAutoConnect) {
        // Auto-connect: only proceed if BLE is already on and permissions
        // are granted. Never show any system dialog.
        if (!await _isBleReadySilent()) {
          debugPrint('Auto-connect: BLE not ready, skipping silently');
          _isConnecting = false;
          return;
        }
      } else {
        // Manual connect: request permissions and turn on Bluetooth.
        final hasPermissions = await _ensurePermissions();
        if (!hasPermissions) {
          debugPrint('Required permissions not granted, cannot proceed');
          _isConnecting = false;
          _connectionTimeoutTimer?.cancel();
          connectionStatus.value = DeviceConnectionStatus.disconnected;
          throw Exception(
            'Required permissions not granted. Please grant Location and Bluetooth permissions in app settings.',
          );
        }

        await _ensureBluetoothOn();
      }

      // BLE is ready — now signal connecting state and arm timeout.
      connectionStatus.value = DeviceConnectionStatus.connecting;
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = Timer(_connectionTimeout, () {
        if (_isConnecting) {
          debugPrint('Connection timeout reached');
          _isConnecting = false;
          connectionStatus.value = DeviceConnectionStatus.disconnected;
          disconnect();
        }
      });

      // Verify Bluetooth is actually on with retry
      BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;
      for (int i = 0; i < 3; i++) {
        adapterState = await FlutterBluePlus.adapterState.first.timeout(
          const Duration(seconds: 2),
        );
        if (adapterState == BluetoothAdapterState.on) {
          break;
        }
        if (i < 2) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (adapterState != BluetoothAdapterState.on) {
        debugPrint('ERROR: Bluetooth is not ON after retries, cannot proceed');
        _isConnecting = false;
        _connectionTimeoutTimer?.cancel();
        connectionStatus.value = DeviceConnectionStatus.disconnected;
        throw Exception(
          'Bluetooth is not enabled. Please enable Bluetooth and try again.',
        );
      }

      // Clean up any existing scan before starting new one
      await _cleanupScan();

      final preferredDeviceId = await _loadLastConnectedDeviceId();
      // Always prefer the already paired / previously-connected pod so we
      // don't accidentally target an unpaired pod nearby and trigger a fresh
      // Android pair request. Only auto-connect strictly *requires* a paired
      // candidate — manual connect still falls back to the nearest pod when
      // none are paired yet.
      final device = await _scanForDevice(
        preferredRemoteId: preferredDeviceId,
        preferPairedDevice: true,
        prioritizePreferredDevice: preferredDeviceId != null,
        requirePairedDevice: isAutoConnect,
        timeout: _defaultScanTimeout,
      );
      if (device == null) {
        debugPrint('Device not found - scan returned null');
        _isConnecting = false;
        _connectionTimeoutTimer?.cancel();
        connectionStatus.value = DeviceConnectionStatus.disconnected;

        // Retry connection if we haven't exceeded max retries
        if (_connectionRetryCount < _maxRetries && !isAutoConnect) {
          _connectionRetryCount++;
          debugPrint(
            'Retrying connection (attempt $_connectionRetryCount/$_maxRetries)...',
          );
          await Future.delayed(Duration(seconds: _connectionRetryCount * 2));
          _isConnecting = false;
          await connect(isAutoConnect: isAutoConnect);
          return;
        }

        throw Exception(
          'Device "align pod" not found. Please ensure the device is powered on and within range.',
        );
      }

      _device = device;
      debugPrint(
        'Found device: ${_device!.platformName} (${_device!.remoteId})',
      );

      // Check if device is paired/bonded
      var isPaired = await _isDevicePaired(_device!);
      debugPrint('Device is paired: $isPaired');
      isAutoConnectionAttempt.value = isPaired;

      // For first-time devices, ask Android to create a bond before connection.
      if (!isPaired) {
        final pairingCompleted = await _requestPairing(_device!);
        if (pairingCompleted) {
          isPaired = true;
          debugPrint('Pairing completed successfully before connect');
        } else {
          debugPrint(
            'Pairing request was not completed, continuing with connection attempt',
          );
        }
      }

      // Check if already connected
      BluetoothConnectionState currentState = await _device!
          .connectionState
          .first
          .timeout(const Duration(seconds: 2));
      debugPrint('Current connection state: $currentState');

      bool needsConnection = true;
      if (currentState == BluetoothConnectionState.connected) {
        debugPrint('Device already connected, verifying connection...');
        // Verify the connection is actually working
        if (await _verifyConnection()) {
          debugPrint('Connection verified, setting up services...');
          needsConnection = false; // Already connected and verified
        } else {
          debugPrint(
            'Connection state says connected but verification failed, reconnecting...',
          );
          try {
            await _device!.disconnect();
            await Future.delayed(const Duration(milliseconds: 500));
            // Re-check state after disconnect
            currentState = await _device!.connectionState.first.timeout(
              const Duration(seconds: 2),
            );
            debugPrint('Connection state after disconnect: $currentState');
            needsConnection = true; // Need to reconnect
          } catch (e) {
            debugPrint('Error disconnecting: $e');
            needsConnection = true; // Assume we need to reconnect
          }
        }
      }

      if (needsConnection &&
          currentState != BluetoothConnectionState.connected) {
        // flutter_blue_plus asserts when autoConnect=true with the default MTU flow.
        // We still do startup reconnects by explicitly calling connect() from app lifecycle,
        // but keep the native connect call as a direct connect.
        const bool shouldAutoConnect = false;
        debugPrint(
          'Connecting to device (autoConnect: $shouldAutoConnect, startupAttempt: $isAutoConnect, isPaired: $isPaired, userDisconnected: $_userInitiatedDisconnect)...',
        );

        try {
          await _device!.connect(
            timeout: const Duration(seconds: 8),
            autoConnect: shouldAutoConnect,
          );
          debugPrint('Connect call completed, waiting for connection state...');

          // Wait for connection to be established with timeout
          await _device!.connectionState
              .where((state) => state == BluetoothConnectionState.connected)
              .first
              .timeout(const Duration(seconds: 8));
          debugPrint('Device connected successfully');

          // Small delay to ensure connection is stable
          await Future.delayed(const Duration(milliseconds: 300));

          // Request larger MTU on Android BEFORE enabling notifications
          // so large JSON payloads are never truncated mid-packet.
          if (Platform.isAndroid || Platform.isIOS) {
            debugPrint('Requesting MTU of 251...');
            try {
              await _device!.requestMtu(251, timeout: 3);
              debugPrint('MTU request completed');
            } catch (e) {
              debugPrint('Failed to request MTU (non-fatal): $e');
            }
          }

          // Request high connection priority on Android
          if (Platform.isAndroid) {
            debugPrint('Requesting high connection priority...');
            try {
              await _device!.requestConnectionPriority(
                  connectionPriorityRequest: ConnectionPriority.high);
              debugPrint('Connection priority set to high');
            } catch (e) {
              debugPrint('Failed to request connection priority (non-fatal): $e');
            }
          }

          // Reset user initiated disconnect flag on successful connection
          _userInitiatedDisconnect = false;
        } catch (e) {
          debugPrint('Connection failed: $e');
          final deviceAfterError = _device;
          final stateAfterError = deviceAfterError == null
              ? BluetoothConnectionState.disconnected
              : await deviceAfterError.connectionState.first.timeout(
                  const Duration(seconds: 2),
                  onTimeout: () => BluetoothConnectionState.disconnected,
                );
          debugPrint('Connection state after error: $stateAfterError');

          // Retry if we haven't exceeded max retries
          if (_connectionRetryCount < _maxRetries && !isAutoConnect) {
            _connectionRetryCount++;
            debugPrint(
              'Retrying connection after failure (attempt $_connectionRetryCount/$_maxRetries)...',
            );
            await Future.delayed(Duration(seconds: _connectionRetryCount * 2));
            _isConnecting = false;
            _connectionTimeoutTimer?.cancel();
            await connect(isAutoConnect: isAutoConnect);
            return;
          }

          rethrow;
        }
      }

      // Set up connection state listener
      await _connectionSubscription?.cancel();
      _connectionSubscription = _device!.connectionState.listen(
        _handleConnectionUpdate,
        onError: (error) {
          debugPrint('Connection state listener error: $error');
        },
      );

      // Discover services with retry logic
      List<BluetoothService> services = await _discoverServicesWithRetry();

      _notifyCharacteristic = _findNotifyCharacteristic(services);

      if (_notifyCharacteristic == null) {
        debugPrint('ERROR: Could not find notify characteristic');
        debugPrint('Looking for service: $_kServiceUuid');
        debugPrint('Looking for characteristic: $_kCharacteristicUuid');

        // Retry service discovery if characteristic not found
        if (_connectionRetryCount < _maxRetries) {
          _connectionRetryCount++;
          debugPrint(
            'Retrying service discovery (attempt $_connectionRetryCount/$_maxRetries)...',
          );
          await Future.delayed(Duration(seconds: _connectionRetryCount));
          services = await _discoverServicesWithRetry();
          _notifyCharacteristic = _findNotifyCharacteristic(services);
        }

        if (_notifyCharacteristic == null) {
          await disconnect();
          _isConnecting = false;
          _connectionTimeoutTimer?.cancel();
          return;
        }
      }

      debugPrint(
        'Found characteristic: ${_notifyCharacteristic!.uuid} in service: ${_notifyCharacteristic!.serviceUuid}',
      );

      // Subscribe before enabling notifications. Some Android BLE stacks can
      // deliver the first cached/live value immediately after the CCCD write.
      // If we attach the listener afterwards, the app may show "connected"
      // while the live stream never gets its first frame.
      await _notifySubscription?.cancel();
      _notifySubscription = _notifyCharacteristic!.onValueReceived.listen(
        _handleNotifyData,
        onError: (error) {
          debugPrint('Notification error: $error');
          // Try to reconnect on notification error
          if (connectionStatus.value == DeviceConnectionStatus.connected) {
            disconnect();
          }
        },
      );

      // Enable notifications with retry
      await _enableNotificationsWithRetry();

      final cachedValue = _notifyCharacteristic!.lastValue;
      if (cachedValue.isNotEmpty) {
        _handleNotifyData(cachedValue);
      }

      // Watchdog: if no BLE data arrives for too long while we still think
      // we're connected, force a reconnect to recover the stream.
      _lastDataReceivedAt = DateTime.now();
      _dataWatchdogTimer?.cancel();
      _dataWatchdogTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (connectionStatus.value != DeviceConnectionStatus.connected) {
          timer.cancel();
          return;
        }
        final last = _lastDataReceivedAt;
        if (last != null && DateTime.now().difference(last).inSeconds > 15) {
          debugPrint('WATCHDOG: No data for 15s, forcing reconnect');
          disconnect().then((_) {
            if (!_userInitiatedDisconnect &&
                connectionStatus.value == DeviceConnectionStatus.disconnected) {
              connect(isAutoConnect: true);
            }
          });
        }
      });

      // Verify connection is working by checking if we can receive data
      if (!await _verifyConnection()) {
        debugPrint('Connection verification failed after setup');
        await disconnect();
        _isConnecting = false;
        _connectionTimeoutTimer?.cancel();
        return;
      }

      _connectionTimeoutTimer?.cancel();
      _isConnecting = false;
      _connectionRetryCount = 0; // Reset retry count on success

      // Request status and sync date time, but wait for first status packet to mark connected.
      void sendSyncCommands() {
        requestStatus().then((_) {
          debugPrint('Sync: request_status command sent');
        });
        sendDateTime().then((sent) {
          debugPrint(sent ? 'Sync: DateTime synced to device' : 'Sync: DateTime sync failed');
        });
      }

      sendSyncCommands();

      _syncRetryTimer?.cancel();
      _syncRetryTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
        if (connectionStatus.value == DeviceConnectionStatus.connecting) {
          debugPrint('Sync retry: sending status request and DateTime again...');
          sendSyncCommands();
        } else {
          timer.cancel();
          _syncRetryTimer = null;
        }
      });

      // Start a timeout timer for status sync
      _connectionTimeoutTimer = Timer(const Duration(seconds: 10), () {
        if (connectionStatus.value == DeviceConnectionStatus.connecting) {
          debugPrint('Sync timeout: did not receive status packet in 10s');
          connectionStatus.value = DeviceConnectionStatus.disconnected;
          disconnect();
        }
      });

      // Save connection state: user has connected and not manually disconnected
      if (!isAutoConnect) {
        // This is a manual connection, save state
        await _saveConnectionState(
          hasEverConnected: true,
          userManuallyDisconnected: false,
          lastConnectedDeviceId: _device?.remoteId.toString(),
        );
        debugPrint(
          'Saved connection state: hasEverConnected=true, userManuallyDisconnected=false',
        );
      } else {
        // Auto-connect succeeded, clear manual disconnect flag
        await _saveConnectionState(
          userManuallyDisconnected: false,
          lastConnectedDeviceId: _device?.remoteId.toString(),
        );
        debugPrint('Auto-connect succeeded, cleared manual disconnect flag');
      }

      debugPrint('Connection established successfully');
    } catch (e) {
      debugPrint('Connection error: $e');
      _isConnecting = false;
      _connectionTimeoutTimer?.cancel();
      await disconnect();
      connectionStatus.value = DeviceConnectionStatus.disconnected;

      // Only retry for transient failures (scan timeout, connection drop).
      // Never retry when user denied permissions or Bluetooth.
      final msg = e.toString().toLowerCase();
      final isDenied =
          msg.contains('permission') ||
          msg.contains('bluetooth is not enabled') ||
          msg.contains('not granted');
      if (!isDenied &&
          _connectionRetryCount < _maxRetries &&
          !isAutoConnect &&
          !_userInitiatedDisconnect) {
        _connectionRetryCount++;
        debugPrint(
          'Retrying connection after error (attempt $_connectionRetryCount/$_maxRetries)...',
        );
        await Future.delayed(Duration(seconds: _connectionRetryCount * 2));
        await connect(isAutoConnect: isAutoConnect);
      }
    }
  }

  Future<void> disconnect({bool userInitiated = false}) async {
    debugPrint('Disconnecting (userInitiated: $userInitiated)');

    // Cancel any pending connection attempts
    _isConnecting = false;
    _connectionTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    _syncRetryTimer?.cancel();
    _syncRetryTimer = null;

    final deviceToDisconnect = _device;

    if (userInitiated) {
      _userInitiatedDisconnect = true;
      // Manual disconnect should fully forget the device and stop auto-connect.
      await _saveConnectionState(
        userManuallyDisconnected: true,
        clearLastConnectedDeviceId: true,
      );
      debugPrint('User initiated disconnect - cleared remembered device state');
    }

    // Clean up subscriptions first
    _buffer = '';
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    // Clean up scan
    await _cleanupScan();

    if (deviceToDisconnect != null) {
      try {
        // Disconnect device with timeout first; unpairing is more reliable once link is closed.
        await deviceToDisconnect.disconnect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('Disconnect timeout, forcing cleanup');
          },
        );
      } catch (e) {
        debugPrint('Error during disconnect: $e');
        // Continue with cleanup even if disconnect fails
      }

      if (userInitiated) {
        try {
          await _unpairDevice(deviceToDisconnect);
          debugPrint('Device unpaired successfully after manual disconnect');
        } catch (e) {
          debugPrint('Failed to unpair device after manual disconnect: $e');
        }
      }
    }
    _dataWatchdogTimer?.cancel();

    _device = null;
    _notifyCharacteristic = null;
    currentReading.value = null; // Clear current reading on disconnect
    connectionStatus.value = DeviceConnectionStatus.disconnected;
    isAutoConnectionAttempt.value = false;

    debugPrint('Disconnect completed');
  }

  Future<void> dispose() async {
    debugPrint('Disposing AlignEyeDeviceService');
    _connectionTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    await disconnect();
    await _readingController.close();
    await _cleanupScan();
    connectionStatus.dispose();
    isAutoConnectionAttempt.dispose();
    currentReading.dispose();
  }

  /// Silent readiness check — returns true only if permissions are already
  /// granted and Bluetooth is on. Never shows any system dialog.
  Future<bool> _isBleReadySilent() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final scan = await Permission.bluetoothScan.status;
        final connect = await Permission.bluetoothConnect.status;
        if (!scan.isGranted || !connect.isGranted) return false;
      }
      final adapter = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 2),
      );
      return adapter == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first.timeout(
      const Duration(seconds: 2),
    );

    if (state == BluetoothAdapterState.on) {
      return;
    }

    if (state == BluetoothAdapterState.off &&
        defaultTargetPlatform == TargetPlatform.android) {
      debugPrint('Bluetooth is off, requesting turn on...');
      try {
        await FlutterBluePlus.turnOn();
        // Wait for Bluetooth to turn on
        for (int i = 0; i < 5; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          final newState = await FlutterBluePlus.adapterState.first.timeout(
            const Duration(seconds: 1),
          );
          if (newState == BluetoothAdapterState.on) {
            debugPrint('Bluetooth turned on successfully');
            return;
          }
        }
      } catch (e) {
        debugPrint('Error turning on Bluetooth: $e');
      }
    }

    throw Exception('Bluetooth is not enabled');
  }

  Future<bool> _isDevicePaired(BluetoothDevice device) async {
    try {
      final bondedDevices = await FlutterBluePlus.bondedDevices;
      final isPaired = bondedDevices.any(
        (bonded) => bonded.remoteId == device.remoteId,
      );
      return isPaired;
    } catch (e) {
      debugPrint('Error checking if device is paired: $e');
      return false;
    }
  }

  Future<bool> hasBondedTargetDevice() async {
    try {
      final bondedDevices = await FlutterBluePlus.bondedDevices;
      return bondedDevices.any(
        (device) => _matchesTargetDeviceName(device.platformName),
      );
    } catch (e) {
      debugPrint('Error checking bonded target devices: $e');
      return false;
    }
  }

  Future<bool> hasUnpairedTargetDeviceNearby({
    Duration timeout = _defaultScanTimeout,
  }) async {
    final device = await _scanForDevice(
      preferPairedDevice: false,
      prioritizePreferredDevice: false,
      requirePairedDevice: false,
      timeout: timeout,
    );
    if (device == null) {
      return false;
    }
    return !(await _isDevicePaired(device));
  }

  Future<bool> _requestPairing(BluetoothDevice device) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      // iOS handles BLE pairing implicitly based on characteristic permissions.
      return true;
    }

    try {
      if (await _isDevicePaired(device)) {
        return true;
      }

      final address = device.remoteId.toString();
      debugPrint('Requesting bond for device: $address');
      final started = await _bondChannel.invokeMethod<bool>('createBond', {
        'address': address,
      });

      if (started != true) {
        debugPrint('createBond did not start successfully');
        return false;
      }

      // Wait for Android bond state to settle.
      for (int attempt = 0; attempt < 10; attempt++) {
        await Future.delayed(const Duration(seconds: 1));
        if (await _isDevicePaired(device)) {
          return true;
        }
      }

      debugPrint('Pairing request timed out without bonded state');
      return false;
    } on PlatformException catch (e) {
      debugPrint('Platform exception during pairing: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Unexpected error during pairing request: $e');
      return false;
    }
  }

  Future<void> _unpairDevice(BluetoothDevice device) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final address = device.remoteId.toString();
    if (address.isEmpty) {
      return;
    }

    await _bondChannel.invokeMethod<bool>('removeBond', {'address': address});
  }

  Future<bool> _ensurePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return true; // iOS handles permissions differently
    }

    debugPrint('Checking required permissions...');

    final bluetoothScanStatus = await Permission.bluetoothScan.status;
    final bluetoothConnectStatus = await Permission.bluetoothConnect.status;

    debugPrint('Bluetooth scan permission: $bluetoothScanStatus');
    debugPrint('Bluetooth connect permission: $bluetoothConnectStatus');

    if (!bluetoothScanStatus.isGranted) {
      debugPrint('Requesting Bluetooth scan permission...');
      final scanResult = await Permission.bluetoothScan.request();
      if (!scanResult.isGranted) {
        debugPrint('Bluetooth scan permission denied');
        return false;
      }
    }

    if (!bluetoothConnectStatus.isGranted) {
      debugPrint('Requesting Bluetooth connect permission...');
      final connectResult = await Permission.bluetoothConnect.request();
      if (!connectResult.isGranted) {
        debugPrint('Bluetooth connect permission denied');
        return false;
      }
    }

    // Location permission is only required pre-Android 12 for BLE scanning.
    if (!_isAndroid12OrAbove) {
      final locationStatus = await Permission.location.status;
      debugPrint('Location permission status: $locationStatus');

      if (!locationStatus.isGranted) {
        debugPrint('Location permission not granted, requesting...');
        final locationResult = await Permission.location.request();
        debugPrint('Location permission request result: $locationResult');

        if (!locationResult.isGranted) {
          debugPrint('Location permission denied by user');
          return false;
        }
      }
    }

    debugPrint('All required permissions granted');
    return true;
  }

  bool _matchesTargetDeviceName(String candidateName) {
    final normalizedName = candidateName.trim().toLowerCase();
    final normalizedPrefix = _deviceNamePrefix.trim().toLowerCase();
    if (normalizedName.isEmpty) {
      return false;
    }
    return normalizedName == normalizedPrefix ||
        normalizedName.startsWith(normalizedPrefix);
  }

  Future<BluetoothDevice?> _scanForDevice({
    String? preferredRemoteId,
    bool preferPairedDevice = true,
    bool prioritizePreferredDevice = true,
    bool requirePairedDevice = false,
    Duration timeout = _defaultScanTimeout,
  }) async {
    final normalizedPreferredId = preferredRemoteId?.toLowerCase();

    // First, prefer devices that are already connected.
    final connectedDevices = FlutterBluePlus.connectedDevices;
    BluetoothDevice? connectedMatch;
    for (final device in connectedDevices) {
      final deviceId = device.remoteId.toString().toLowerCase();
      if (normalizedPreferredId != null && deviceId == normalizedPreferredId) {
        debugPrint('Found preferred connected device: ${device.platformName}');
        return device;
      }
      if (_matchesTargetDeviceName(device.platformName)) {
        connectedMatch ??= device;
      }
    }
    if (connectedMatch != null) {
      debugPrint(
        'Found matching connected device: ${connectedMatch.platformName}',
      );
      return connectedMatch;
    }

    // Build bonded device index for paired-first selection.
    final bondedDeviceIds = <String>{};
    try {
      final bondedDevices = await FlutterBluePlus.bondedDevices;
      for (final device in bondedDevices) {
        if (_matchesTargetDeviceName(device.platformName)) {
          bondedDeviceIds.add(device.remoteId.toString().toLowerCase());
        }
      }
      debugPrint('Matching bonded devices found: ${bondedDeviceIds.length}');
    } catch (e) {
      debugPrint('Error loading bonded devices: $e');
    }

    // Clean up any existing scan
    await _cleanupScan();

    debugPrint('Starting BLE scan for device: $_deviceNamePrefix');

    // Check adapter state before scanning
    final adapterState = await FlutterBluePlus.adapterState.first;
    debugPrint('Adapter state before scan: $adapterState');
    if (adapterState != BluetoothAdapterState.on) {
      debugPrint('ERROR: Bluetooth adapter is not ON, cannot scan');
      return null;
    }

    final candidates = <String, _ScanCandidate>{};
    final serviceUuidLower = _kServiceUuid.toLowerCase();

    _scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        for (final result in results) {
          final hasServiceMatch = result.advertisementData.serviceUuids.any(
            (uuid) => uuid.toString().toLowerCase() == serviceUuidLower,
          );
          // Require AlignEye service UUID to be present so we only consider
          // genuine AlignEye devices during scanning.
          if (!hasServiceMatch) {
            continue;
          }

          final remoteId = result.device.remoteId.toString().toLowerCase();
          final isBonded = bondedDeviceIds.contains(remoteId);
          final existing = candidates[remoteId];

          if (existing == null || result.rssi > existing.rssi) {
            candidates[remoteId] = _ScanCandidate(
              device: result.device,
              rssi: result.rssi,
              isBonded: isBonded,
            );
          }
        }
      },
      onError: (error) {
        debugPrint('Scan results stream error: $error');
      },
    );

    try {
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      debugPrint('ERROR: Failed to start scan: $e');
      debugPrint('Please verify Bluetooth + Location permissions on Android');
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      return null;
    }

    final scanStart = DateTime.now();
    while (DateTime.now().difference(scanStart) <
        timeout + const Duration(milliseconds: 250)) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (preferredRemoteId != null) {
        final remoteIdLower = preferredRemoteId.toLowerCase();
        final match = candidates[remoteIdLower];
        if (match != null && (match.isBonded || !requirePairedDevice)) {
          break;
        }
      } else if (candidates.values.any((c) => c.isBonded)) {
        break;
      }
    }
    await _cleanupScan();

    if (candidates.isEmpty) {
      debugPrint('Scan finished with no matching candidates');
      return null;
    }

    if (prioritizePreferredDevice &&
        normalizedPreferredId != null &&
        candidates.containsKey(normalizedPreferredId)) {
      final preferred = candidates[normalizedPreferredId]!;
      debugPrint(
        'Selected preferred known device: ${preferred.device.platformName} (RSSI ${preferred.rssi})',
      );
      return preferred.device;
    }

    if (preferPairedDevice) {
      final pairedCandidates = candidates.values
          .where((candidate) => candidate.isBonded)
          .toList();
      if (pairedCandidates.isNotEmpty) {
        pairedCandidates.sort((a, b) => b.rssi.compareTo(a.rssi));
        final bestPaired = pairedCandidates.first;
        debugPrint(
          'Selected paired candidate: ${bestPaired.device.platformName} (RSSI ${bestPaired.rssi})',
        );
        return bestPaired.device;
      }
    }

    if (requirePairedDevice) {
      debugPrint(
        'Auto-connect requires a paired device, but no paired candidates are currently available',
      );
      return null;
    }

    final allCandidates = candidates.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    final nearest = allCandidates.first;
    debugPrint(
      'Selected nearest candidate: ${nearest.device.platformName} (RSSI ${nearest.rssi})',
    );
    return nearest.device;
  }

  BluetoothCharacteristic? _findNotifyCharacteristic(
    List<BluetoothService> services,
  ) {
    final serviceUuidLower = _kServiceUuid.toLowerCase();
    final charUuidLower = _kCharacteristicUuid.toLowerCase();

    debugPrint('Searching for service: $serviceUuidLower');
    debugPrint('Searching for characteristic: $charUuidLower');

    for (final service in services) {
      final serviceUuid = service.uuid.toString().toLowerCase();
      debugPrint('Checking service: $serviceUuid');

      if (serviceUuid == serviceUuidLower) {
        debugPrint('Found matching service!');
        for (final characteristic in service.characteristics) {
          final charUuid = characteristic.uuid.toString().toLowerCase();
          debugPrint('  Checking characteristic: $charUuid');

          if (charUuid == charUuidLower) {
            debugPrint('  Found matching characteristic!');
            // Verify it supports notifications
            if (characteristic.properties.notify ||
                characteristic.properties.indicate) {
              debugPrint('  Characteristic supports notifications - SUCCESS!');
              return characteristic;
            } else {
              debugPrint('  Characteristic does NOT support notifications');
            }
          }
        }
      }
    }

    debugPrint('Could not find matching service/characteristic');
    return null;
  }

  void _handleNotifyData(List<int> data) {
    if (data.isEmpty) return;
    _lastDataReceivedAt = DateTime.now();
    _buffer += utf8.decode(data, allowMalformed: true);

    if (_buffer.length > 2048) {
      debugPrint('BLE buffer overflow cleared: ${_buffer.length}B');
      _buffer = '';
      return;
    }

    while (true) {
      final start = _buffer.indexOf('{');
      if (start == -1) {
        _buffer = '';
        break;
      }
      if (start > 0) {
        _buffer = _buffer.substring(start);
      }

      int depth = 0;
      int end = -1;
      bool inString = false;
      bool escape = false;
      bool restartFromNestedStart = false;
      for (int i = 0; i < _buffer.length; i++) {
        final ch = _buffer[i];
        if (escape) {
          escape = false;
          continue;
        }
        if (ch == '\\') {
          escape = true;
          continue;
        }
        if (ch == '"') {
          inString = !inString;
          continue;
        }
        if (inString) continue;
        if (ch == '{') {
          if (depth > 0) {
            _buffer = _buffer.substring(i);
            restartFromNestedStart = true;
            break;
          }
          depth++;
        }
        if (ch == '}') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }

      if (restartFromNestedStart) {
        continue;
      }

      if (end == -1) {
        if (_buffer.length > 600) {
          debugPrint('BLE stale buffer cleared: ${_buffer.length}B');
          _buffer = '';
        }
        break;
      }

      final chunk = _buffer.substring(0, end + 1).trim();
      _buffer = _buffer.substring(end + 1);
      try {
        final decoded = jsonDecode(chunk);
        if (decoded is Map<String, dynamic>) {
          final t = decoded['t']?.toString();
          
          final int? rev = decoded['rev'] != null 
              ? (decoded['rev'] is int 
                  ? decoded['rev'] as int 
                  : int.tryParse(decoded['rev'].toString())) 
              : null;
          
          if (rev != null) {
            final currentRev = latestDeviceRevision;
            if (currentRev != null && rev < currentRev) {
              debugPrint('Ignoring packet with older revision: $rev < $currentRev');
              continue;
            }
            if (currentRev == null || rev > currentRev) {
              latestDeviceRevision = rev;
            }
          }

          if (t == 'live') {
            final live = LiveTelemetry.fromJson(decoded);
            
            final lastSeq = _lastLiveSeq;
            if (lastSeq != null && live.seq != lastSeq + 1) {
              final missed = live.seq - lastSeq - 1;
              if (missed > 0) {
                debugPrint('DEBUG: Missed $missed live packets (last: $lastSeq, current: ${live.seq})');
              }
            }
            _lastLiveSeq = live.seq;

            final prev = currentReading.value ?? _createDefaultReading();
            final updated = prev.copyWith(
              angle: live.angle,
              isBadPosture: live.isBadPosture,
              posture: live.posture == 'GOOD' ? 'Good posture' : 'Bad posture',
              mode: live.mode,
              subMode: live.subMode,
              timestamp: DateTime.now(),
            );
            currentReading.value = updated;
            
            final now = DateTime.now();
            if (_lastUiFrame == null ||
                now.difference(_lastUiFrame!).inMilliseconds >= 100) {
              _lastUiFrame = now;
              _readingController.add(updated);
            }
          } 
          else if (t == 'status') {
            final status = DeviceStatus.fromJson(decoded);
            
            if (connectionStatus.value == DeviceConnectionStatus.connecting) {
              connectionStatus.value = DeviceConnectionStatus.connected;
            }

            final isTherapy = status.mode.trim().toUpperCase() == 'THERAPY';
            if (isTherapy) {
              latestTherapyTotalPatterns = status.therapyTotalPatterns;
              if (status.therapyCurrentIndex >= 0) {
                latestTherapyCurrentPatternIndex = status.therapyCurrentIndex;
              }
              final pattName = status.therapyPattern.trim();
              if (pattName.isNotEmpty) {
                final prevClean = _stripSessionMeta(latestTherapyPatternName);
                final newClean = _stripSessionMeta(pattName);
                if (prevClean != newClean) {
                  _currentPatternStartElapsedSec = status.therapyElapsedSec;
                }
                latestTherapyPatternName = pattName;
              }
              final nextName = status.therapyNext.trim();
              if (nextName.isNotEmpty) {
                latestTherapyNextPatternName = nextName;
              }
              
              if (status.therapyRemainingSec > 0 || status.therapyElapsedSec > 0) {
                _therapyRemainingAnchorSec = status.therapyRemainingSec;
                _therapyElapsedAnchorSec = status.therapyElapsedSec;
                _therapyAnchorAt = DateTime.now();
              }
            } else {
              latestTherapyTotalPatterns = 0;
              latestTherapyCurrentPatternIndex = -1;
              latestTherapyPatternName = '';
              latestTherapyNextPatternName = '';
              _therapyRemainingAnchorSec = -1;
              _therapyElapsedAnchorSec = 0;
              _therapyAnchorAt = null;
              _currentPatternStartElapsedSec = 0;
            }

            if (pendingMode.value == status.mode) {
              pendingMode.value = null;
            }
            if (pendingSubMode.value == status.subMode) {
              pendingSubMode.value = null;
            }
            if (pendingDifficulty.value == status.difficultyDeg) {
              pendingDifficulty.value = null;
            }

            final prev = currentReading.value ?? _createDefaultReading();
            final updated = prev.copyWith(
              mode: status.mode,
              subMode: status.subMode,
              difficultyDeg: status.difficultyDeg,
              batteryPercentage: status.batteryPct,
              batteryVoltage: status.batteryMv / 1000.0,
              isCalibrating: status.calibrating,
              calibrationPhase: status.calPhase,
              calibrationElapsedMs: status.calElapsedMs,
              calibrationTotalMs: status.calTotalMs,
              calibrationResult: status.calResult,
              liveSessionId: status.sessionId,
              liveSessionElapsedSeconds: status.sessionElapsedSec,
              liveSessionBadCount: status.sessionBadCount,
              therapyPattern: status.therapyPattern,
              therapyNextPattern: status.therapyNext,
              therapyElapsedSeconds: status.therapyElapsedSec,
              therapyRemainingSeconds: status.therapyRemainingSec,
              therapyIntensityLevel: status.therapyIntensity,
              therapyTotalPatterns: status.therapyTotalPatterns,
              timestamp: DateTime.now(),
            );
            
            currentReading.value = updated;
            _readingController.add(updated);
          } 
          else if (t == 'ack') {
            final ack = CommandAck.fromJson(decoded);
            final pendingCmd = _pendingCommandNames.remove(ack.seq);
            
            if (pendingCmd != null) {
              debugPrint('ACK received for $pendingCmd: seq=${ack.seq}, ok=${ack.ok}');
            }
            
            if (ack.cmd == 'set_mode') {
              pendingMode.value = null;
            } else if (ack.cmd == 'set_training_alert' || ack.cmd == 'set_therapy_duration') {
              pendingSubMode.value = null;
            } else if (ack.cmd == 'set_difficulty') {
              pendingDifficulty.value = null;
            }

            _ackController.add(ack);
          } 
          else if (t == 'event') {
            final event = DeviceEvent.fromJson(decoded);
            _eventController.add(event);
          } 
          else if (t == 'debug') {
            final debug = DebugTelemetry.fromJson(decoded);
            _debugController.add(debug);
          } 
          else {
            final oldReading = PostureReading.fromJson(decoded);
            
            final isTherapy = oldReading.mode.trim().toUpperCase() == 'THERAPY';
            if (isTherapy) {
              latestTherapyTotalPatterns = oldReading.therapyTotalPatterns;
              if (oldReading.therapyCurrentPatternIndex >= 0) {
                latestTherapyCurrentPatternIndex = oldReading.therapyCurrentPatternIndex;
              }
              final pattName = oldReading.therapyPattern.trim();
              if (pattName.isNotEmpty) {
                final prevClean = _stripSessionMeta(latestTherapyPatternName);
                final newClean = _stripSessionMeta(pattName);
                if (prevClean != newClean) {
                  _currentPatternStartElapsedSec = oldReading.therapyElapsedSeconds;
                }
                latestTherapyPatternName = pattName;
              }
              final nextName = oldReading.therapyNextPattern.trim();
              if (nextName.isNotEmpty) {
                latestTherapyNextPatternName = nextName;
              }
              
              if (oldReading.therapyRemainingSeconds > 0 || oldReading.therapyElapsedSeconds > 0) {
                _therapyRemainingAnchorSec = oldReading.therapyRemainingSeconds;
                _therapyElapsedAnchorSec = oldReading.therapyElapsedSeconds;
                _therapyAnchorAt = DateTime.now();
              }
            } else {
              latestTherapyTotalPatterns = 0;
              latestTherapyCurrentPatternIndex = -1;
              latestTherapyPatternName = '';
              latestTherapyNextPatternName = '';
              _therapyRemainingAnchorSec = -1;
              _therapyElapsedAnchorSec = 0;
              _therapyAnchorAt = null;
              _currentPatternStartElapsedSec = 0;
            }

            currentReading.value = oldReading;
            
            final now = DateTime.now();
            if (_lastUiFrame == null ||
                now.difference(_lastUiFrame!).inMilliseconds >= 100) {
              _lastUiFrame = now;
              _readingController.add(oldReading);
            }
          }
        }
      } catch (_) {
        // Ignore malformed payloads; we'll wait for the next valid JSON packet.
      }
    }
  }

  void _handleConnectionUpdate(BluetoothConnectionState state) {
    debugPrint('Connection state changed: $state');

    if (state == BluetoothConnectionState.connected) {
      // Reset user initiated disconnect flag when reconnected (user manually connected again)
      _userInitiatedDisconnect = false;
      _isConnecting = false;
      _connectionTimeoutTimer?.cancel();
      _connectionRetryCount = 0;

      // Save state: user has connected again, clear manual disconnect flag
      _saveConnectionState(
        userManuallyDisconnected: false,
        lastConnectedDeviceId: _device?.remoteId.toString(),
      );

      // Verify connection is actually working
      _verifyConnection().then((isValid) {
        if (isValid) {
          // Re-sync but stay connecting until status confirms it
          requestStatus().then((_) {
            debugPrint('Reconnected, request_status sent');
          });
          sendDateTime().then((sent) {
            debugPrint(sent ? 'Reconnected, DateTime synced' : 'Reconnected, DateTime sync failed');
          });
        } else {
          debugPrint('Connection state says connected but verification failed');
          disconnect();
        }
      });
    } else if (state == BluetoothConnectionState.disconnected) {
      _isConnecting = false;
      _connectionTimeoutTimer?.cancel();

      // Only update status if we're not already disconnected
      if (connectionStatus.value != DeviceConnectionStatus.disconnected) {
        connectionStatus.value = DeviceConnectionStatus.disconnected;

        // Don't auto-reconnect here - auto-reconnect only happens on app start
        // via tryAutoConnect() which checks persistent state
      }

      // Keep _userInitiatedDisconnect flag set if user manually disconnected
      // This prevents auto-reconnect until user manually connects again
    }
  }

  /// Clean up any active scan
  Future<void> _cleanupScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    }
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  /// Discover services with retry logic
  Future<List<BluetoothService>> _discoverServicesWithRetry() async {
    List<BluetoothService>? services;
    Exception? lastError;

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        debugPrint('Discovering services (attempt ${attempt + 1}/3)...');

        if (_device == null) {
          throw Exception('Device is null');
        }

        services = await _device!.discoverServices().timeout(
          _serviceDiscoveryTimeout,
        );

        debugPrint('Found ${services.length} services');

        // Log all services and characteristics for debugging
        for (final service in services) {
          debugPrint('  Service: ${service.uuid}');
          for (final char in service.characteristics) {
            debugPrint(
              '    Characteristic: ${char.uuid} (notify: ${char.properties.notify}, read: ${char.properties.read})',
            );
          }
        }

        // If we got services, break out of retry loop
        if (services.isNotEmpty) {
          break;
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('Service discovery failed (attempt ${attempt + 1}/3): $e');

        if (attempt < 2) {
          // Wait before retry with exponential backoff
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }

    if (services == null || services.isEmpty) {
      throw lastError ??
          Exception('Failed to discover services after 3 attempts');
    }

    return services;
  }

  /// Enable notifications with retry logic
  Future<void> _enableNotificationsWithRetry() async {
    if (_notifyCharacteristic == null) {
      throw Exception('Notify characteristic is null');
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        debugPrint('Enabling notifications (attempt ${attempt + 1}/3)...');
        await _notifyCharacteristic!.setNotifyValue(true);

        // Wait a bit to ensure notification is set up
        await Future.delayed(const Duration(milliseconds: 200));

        // Verify notification is enabled
        if (_notifyCharacteristic!.isNotifying) {
          debugPrint('Notifications enabled successfully');
          return;
        } else {
          throw Exception('Notification enabled but isNotifying is false');
        }
      } catch (e) {
        debugPrint(
          'Failed to enable notifications (attempt ${attempt + 1}/3): $e',
        );

        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        } else {
          rethrow;
        }
      }
    }
  }

  /// Verify connection is actually working
  Future<bool> _verifyConnection() async {
    if (_device == null) {
      debugPrint('Connection verification failed: device is null');
      return false;
    }

    try {
      // Check connection state
      final state = await _device!.connectionState.first.timeout(
        const Duration(seconds: 2),
      );

      if (state != BluetoothConnectionState.connected) {
        debugPrint('Connection verification failed: state is $state');
        return false;
      }

      // If characteristic is not set up yet, that's okay - we'll set it up
      // Only verify notifications if characteristic is already set up
      if (_notifyCharacteristic != null) {
        // Check if notifications are enabled
        if (!_notifyCharacteristic!.isNotifying) {
          debugPrint(
            'Connection verification: characteristic exists but notifications not enabled yet',
          );
          // This is okay - we'll enable them during setup
          return true; // Connection is good, just need to set up notifications
        }
        debugPrint(
          'Connection verification passed - device connected and notifications enabled',
        );
        return true;
      } else {
        debugPrint(
          'Connection verification passed - device connected, will set up services',
        );
        return true; // Device is connected, we just need to set up services
      }
    } catch (e) {
      debugPrint('Connection verification error: $e');
      return false;
    }
  }

  /// Attempts to auto-connect to a paired device if available
  /// This should be called on app start or when appropriate
  /// Always attempts to connect when app opens, regardless of previous connection history
  Future<void> tryAutoConnect() async {
    // Reset user initiated disconnect flag on app start
    // This ensures auto-connect always happens when app opens
    _userInitiatedDisconnect = false;
    debugPrint(
      '=== AUTO-CONNECT: App started - resetting user disconnect flag, attempting auto-connect ===',
    );

    // Load persistent state (but don't use it to block auto-connect on app start)
    await _loadConnectionState();

    // Note: We don't check _userInitiatedDisconnect here because we just reset it
    // The flag will be set if user disconnects during this session

    if (connectionStatus.value != DeviceConnectionStatus.disconnected) {
      debugPrint(
        'AUTO-CONNECT: Already connected or connecting, skipping auto-connect',
      );
      return;
    }

    // Wait a bit for the app to fully initialize and Bluetooth to be ready
    await Future.delayed(const Duration(milliseconds: 500));

    // Check if Bluetooth is supported
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        debugPrint('AUTO-CONNECT: Bluetooth is not supported on this device');
        return;
      }

      // Check if Bluetooth adapter is ready
      final adapterState = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint(
            'AUTO-CONNECT: Timeout waiting for Bluetooth adapter state',
          );
          return BluetoothAdapterState.unknown;
        },
      );

      if (adapterState != BluetoothAdapterState.on) {
        debugPrint(
          'AUTO-CONNECT: Bluetooth adapter is not ON (state: $adapterState), cannot auto-connect',
        );
        return;
      }

      debugPrint(
        'AUTO-CONNECT: Bluetooth is ready, starting connection flow...',
      );
      // Force reset again right before connecting to ensure session flag never blocks startup.
      _userInitiatedDisconnect = false;
      // Startup flow only targets already paired devices. If none are available,
      // UI can prompt the user to manually connect to the nearest device.
      await connect(isAutoConnect: true);
      debugPrint('AUTO-CONNECT: Connection attempt completed');
    } catch (e, stackTrace) {
      debugPrint('AUTO-CONNECT: Failed with error: $e');
      debugPrint('AUTO-CONNECT: Stack trace: $stackTrace');
      // Don't throw - auto-connect failures should be silent
    }
  }

  /// Save connection state to persistent storage
  /// Note: We don't persist userManuallyDisconnected anymore
  /// because we want auto-connect to always happen on app start
  Future<void> _saveConnectionState({
    bool? hasEverConnected,
    bool? userManuallyDisconnected,
    String? lastConnectedDeviceId,
    bool clearLastConnectedDeviceId = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (hasEverConnected != null) {
        await prefs.setBool(_keyHasEverConnected, hasEverConnected);
      }
      if (clearLastConnectedDeviceId) {
        await prefs.remove(_keyLastConnectedDeviceId);
      } else if (lastConnectedDeviceId != null) {
        final normalized = lastConnectedDeviceId.trim();
        if (normalized.isEmpty) {
          await prefs.remove(_keyLastConnectedDeviceId);
        } else {
          await prefs.setString(_keyLastConnectedDeviceId, normalized);
        }
      }
      // Don't persist userManuallyDisconnected - it's session-only now
      // Just update the in-memory flag for the current session
      if (userManuallyDisconnected != null) {
        _userInitiatedDisconnect = userManuallyDisconnected;
      }
    } catch (e) {
      debugPrint('Error saving connection state: $e');
    }
  }

  /// Load connection state from persistent storage
  /// Note: We don't load _userInitiatedDisconnect from storage anymore
  /// because we want auto-connect to always happen on app start
  Future<void> _loadConnectionState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // We still load hasEverConnected to know if user has connected before
      final hasEverConnected = prefs.getBool(_keyHasEverConnected) ?? false;
      final lastConnectedDeviceId = prefs.getString(_keyLastConnectedDeviceId);
      debugPrint(
        'Loaded connection state: hasEverConnected=$hasEverConnected, lastConnectedDeviceId=$lastConnectedDeviceId',
      );
      // Don't load userManuallyDisconnected - it's session-only now
    } catch (e) {
      debugPrint('Error loading connection state: $e');
    }
  }

  Future<String?> _loadLastConnectedDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_keyLastConnectedDeviceId)?.trim();
      if (value == null || value.isEmpty) {
        return null;
      }
      return value;
    } catch (e) {
      debugPrint('Error loading last connected device id: $e');
      return null;
    }
  }

  PostureReading _createDefaultReading() {
    return PostureReading(
      mode: 'UNKNOWN',
      subMode: 'UNKNOWN',
      angle: 0.0,
      isCalibrating: false,
      calibrationResult: '',
      calibrationElapsedMs: 0,
      calibrationTotalMs: 0,
      calibrationPhase: 'IDLE',
      posture: 'UNKNOWN',
      isBadPosture: false,
      batteryVoltage: 0.0,
      batteryPercentage: 0,
      difficultyDeg: 25,
      therapyPattern: '',
      therapyNextPattern: '',
      therapyElapsedSeconds: 0,
      therapyRemainingSeconds: 0,
      therapyIntensityLevel: 0,
      therapyCurrentPatternIndex: -1,
      therapyTotalPatterns: 0,
      liveSessionId: 0,
      liveSessionElapsedSeconds: 0,
      liveSessionStartEpoch: 0,
      liveSessionBadCount: 0,
      timestamp: DateTime.now(),
    );
  }

  String _stripSessionMeta(String v) {
    final b = v.indexOf('[');
    return b <= 0 ? v.trim() : v.substring(0, b).trim();
  }
}
