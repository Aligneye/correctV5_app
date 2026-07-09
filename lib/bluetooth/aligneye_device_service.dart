import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:correctv1/services/therapy_pattern_names.dart';

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

// Translates an app-side mode string to the JSON SET_MODE command value.
// New firmware accepts IDLE/TRAINING/THERAPY; legacy app labels collapse to
// the nearest supported mode.
String wireModeCommand(String appMode) {
  final normalized = appMode.trim().toUpperCase();
  switch (normalized) {
    case 'IDLE':
      return 'IDLE';
    case 'THERAPY':
      return 'THERAPY';
    case 'TRAINING':
    case 'POSTURE':
    case 'TRACKING':
      return 'TRAINING';
    default:
      return 'IDLE';
  }
}

String normalizeDeviceMode(dynamic value, {String fallback = 'IDLE'}) {
  final raw = value?.toString().trim().toUpperCase();

  if (raw == null || raw.isEmpty || raw == 'UNKNOWN') {
    return fallback;
  }

  switch (raw) {
    case 'IDLE':
      return 'IDLE';

    case 'TRAINING':
      return 'TRAINING';

    case 'THERAPY':
      return 'THERAPY';

  // Backward compatibility only
    case 'OFF':
      return 'IDLE';

    case 'TRACKING':
      return 'IDLE';

    case 'POSTURE':
      return 'TRAINING';

    default:
      return fallback;
  }
}

class PostureReading {
  final String mode;
  final String subMode;
  final double angle;
  final double rawXG;
  final double rawYG;
  final double rawZG;
  final double angleX;
  final double angleY;
  final double angleZ;
  final double calY;
  final double calZ;
  final bool isCalibrating;
  final String calibrationResult;
  final int calibrationElapsedMs;
  final int calibrationTotalMs;
  final String calibrationPhase;
  final int calibrationQuality;
  final String calibrationFailReason;
  final int calibrationPassedSamples;
  final double calibrationRefX;
  final double calibrationRefY;
  final double calibrationRefZ;
  final String posture;
  final bool isBadPosture;
  final double batteryVoltage;
  final int batteryPercentage;
  final String profile;
  final int difficultyDeg;
  final String therapyPattern;
  final String therapyNextPattern;
  final int therapyElapsedSeconds;
  final int therapyRemainingSeconds;
  final int therapyIntensityLevel;

  /// Full therapy pattern plan for the active session. Each entry is a
  /// firmware TherapyPattern index (0..13). Empty when not in therapy or
  /// the device hasn't announced the sequence yet.
  final List<int> therapyPatternSequence;

  /// Index inside [therapyPatternSequence] of the currently-playing pattern.
  /// -1 when unknown / not in therapy.
  final int therapyCurrentPatternIndex;

  /// Total patterns scheduled for this session. Firmware publishes this via
  /// `t_total`; used as a fallback length when `t_seq` is missing so the
  /// pager can still render a placeholder card per slot.
  final int therapyTotalPatterns;

  /// New V5 fields for exact pattern, session, and total duration tracking.
  final int therapyPatternId;
  final int therapyTotalDurationSeconds;
  final int therapyPatternDurationSeconds;
  final int therapyPatternElapsedSeconds;
  final int therapyPatternRemainingSeconds;

  final int liveSessionId;
  final int liveSessionElapsedSeconds;
  final int liveSessionStartEpoch;
  final int liveSessionBadCount;
  final DateTime timestamp;

  const PostureReading({
    required this.mode,
    required this.subMode,
    required this.angle,
    required this.rawXG,
    required this.rawYG,
    required this.rawZG,
    required this.angleX,
    required this.angleY,
    required this.angleZ,
    required this.calY,
    required this.calZ,
    required this.isCalibrating,
    required this.calibrationResult,
    required this.calibrationElapsedMs,
    required this.calibrationTotalMs,
    required this.calibrationPhase,
    this.calibrationQuality = 0,
    this.calibrationFailReason = '',
    this.calibrationPassedSamples = 0,
    this.calibrationRefX = 0.0,
    this.calibrationRefY = 0.0,
    this.calibrationRefZ = 0.0,
    required this.posture,
    required this.isBadPosture,
    required this.batteryVoltage,
    required this.batteryPercentage,
    required this.profile,
    required this.difficultyDeg,
    required this.therapyPattern,
    required this.therapyNextPattern,
    required this.therapyElapsedSeconds,
    required this.therapyRemainingSeconds,
    required this.therapyIntensityLevel,
    required this.therapyPatternSequence,
    required this.therapyCurrentPatternIndex,
    required this.therapyTotalPatterns,
    this.therapyPatternId = -1,
    this.therapyTotalDurationSeconds = 0,
    this.therapyPatternDurationSeconds = 0,
    this.therapyPatternElapsedSeconds = 0,
    this.therapyPatternRemainingSeconds = 0,
    required this.liveSessionId,
    required this.liveSessionElapsedSeconds,
    required this.liveSessionStartEpoch,
    required this.liveSessionBadCount,
    required this.timestamp,
  });

  factory PostureReading.fromJson(
      Map<String, dynamic> json, {
        PostureReading? current,
      }) {
    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    double? toDoubleOrNull(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    int? toIntOrNull(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    // Determine isCalibrating:
    bool isCal = current?.isCalibrating ?? false;
    if (json.containsKey('isCalibrating') ||
        json.containsKey('is_calibrating')) {
      final v = json['isCalibrating'] ?? json['is_calibrating'];
      isCal = v == true || v?.toString() == 'true';
    }

    final tType = json['t']?.toString().toUpperCase();
    final parsedMode =
        json['mode'] ?? (tType == 'TP' || tType == 'TL' ? 'THERAPY' : null);

    return PostureReading(
      mode: normalizeDeviceMode(parsedMode, fallback: current?.mode ?? 'IDLE'),
      subMode: json['sub_mode']?.toString() ?? current?.subMode ?? 'INSTANT',
      angle: toDoubleOrNull(json['angle']) ?? current?.angle ?? 0.0,
      rawXG: toDoubleOrNull(json['raw_x_g']) ?? current?.rawXG ?? 0.0,
      rawYG: toDoubleOrNull(json['raw_y_g']) ?? current?.rawYG ?? 0.0,
      rawZG: toDoubleOrNull(json['raw_z_g']) ?? current?.rawZG ?? 0.0,
      angleX: toDoubleOrNull(json['angle_x']) ?? current?.angleX ?? 0.0,
      angleY: toDoubleOrNull(json['angle_y']) ?? current?.angleY ?? 0.0,
      angleZ: toDoubleOrNull(json['angle_z']) ?? current?.angleZ ?? 0.0,
      calY: toDoubleOrNull(json['cal_y']) ?? current?.calY ?? 0.0,
      calZ: toDoubleOrNull(json['cal_z']) ?? current?.calZ ?? 0.0,
      isCalibrating: isCal,
      calibrationResult: () {
        if (json.containsKey('calibrationResult') ||
            json.containsKey('calibration_result') ||
            json.containsKey('calibResult') ||
            json.containsKey('result')) {
          final v =
              json['calibrationResult']?.toString() ??
                  json['calibration_result']?.toString() ??
                  json['calibResult']?.toString() ??
                  json['result']?.toString() ??
                  '';
          if (v == 'success') return 'complete';
          return v;
        }
        return current?.calibrationResult ?? '';
      }(),
      calibrationElapsedMs: () {
        final val = json['c_elap'] ?? json['calibration_elapsed_ms'];
        return val != null ? toInt(val) : (current?.calibrationElapsedMs ?? 0);
      }(),
      calibrationTotalMs: () {
        final val = json['c_tot'] ?? json['calibration_total_ms'];
        return val != null ? toInt(val) : (current?.calibrationTotalMs ?? 0);
      }(),
      calibrationPhase: () {
        final val = json['c_phase'];
        return val != null
            ? val.toString().toUpperCase()
            : (current?.calibrationPhase ?? 'IDLE');
      }(),
      calibrationQuality: json.containsKey('quality')
          ? toInt(json['quality'])
          : (current?.calibrationQuality ?? 0),
      calibrationFailReason: json.containsKey('reason')
          ? json['reason']?.toString() ?? ''
          : (current?.calibrationFailReason ?? ''),
      calibrationPassedSamples: json.containsKey('passed_samples')
          ? toInt(json['passed_samples'])
          : (current?.calibrationPassedSamples ?? 0),
      calibrationRefX: json.containsKey('x')
          ? toDouble(json['x'])
          : (current?.calibrationRefX ?? 0.0),
      calibrationRefY: json.containsKey('y')
          ? toDouble(json['y'])
          : (current?.calibrationRefY ?? 0.0),
      calibrationRefZ: json.containsKey('z')
          ? toDouble(json['z'])
          : (current?.calibrationRefZ ?? 0.0),
      posture:
      json['posture']?.toString() ?? current?.posture ?? 'GOOD POSTURE',
      isBadPosture:
      json['is_bad_posture'] == true ||
          json['is_bad_posture']?.toString().toLowerCase() == 'true' ||
          (json['posture']?.toString().toUpperCase().contains('BAD') ??
              current?.isBadPosture ??
              false),
      batteryVoltage:
      toDoubleOrNull(json['battery_voltage']) ??
          current?.batteryVoltage ??
          0.0,
      batteryPercentage: () {
        final val = json['battery_percentage'] ?? json['battery'];
        return val != null ? toInt(val) : (current?.batteryPercentage ?? 0);
      }(),
      profile: json['profile']?.toString() ?? current?.profile ?? '',
      difficultyDeg:
      toIntOrNull(json['difficulty_angle'] ?? json['difficulty_deg']) ??
          current?.difficultyDeg ??
          25,
      therapyPattern: () {
        final val =
            json['t_patt'] ??
                json['therapy_pattern'] ??
                (json['pid'] != null
                    ? firmwarePatternName(toInt(json['pid']))
                    : null);
        return val != null ? val.toString() : (current?.therapyPattern ?? '');
      }(),
      therapyNextPattern: () {
        final val = json['t_next'] ?? json['therapy_next_pattern'];
        return val != null
            ? val.toString()
            : (current?.therapyNextPattern ?? '');
      }(),
      therapyElapsedSeconds: () {
        final val =
            json['t_elap'] ??
                json['therapy_elapsed_sec'] ??
                json['elapsed'] ??
                (json['t']?.toString().toUpperCase() == 'TP' ? 0 : null);
        return val != null ? toInt(val) : (current?.therapyElapsedSeconds ?? 0);
      }(),
      therapyRemainingSeconds: () {
        final val =
            json['t_rem'] ??
                json['therapy_remaining_sec'] ??
                json['remaining'] ??
                json['duration'];
        return val != null
            ? toInt(val)
            : (current?.therapyRemainingSeconds ?? 0);
      }(),
      therapyIntensityLevel: () {
        final val =
            json['t_lvl'] ??
                json['therapy_intensity_level'] ??
                json['intensity'];
        return val != null ? toInt(val) : (current?.therapyIntensityLevel ?? 0);
      }(),
      therapyPatternSequence: () {
        final val =
            json['t_seq'] ?? json['therapy_pattern_sequence'] ?? json['seq'];
        if (val != null) {
          if (val is List) {
            return val.map((e) => toInt(e)).toList();
          }
          final raw = val.toString();
          if (raw.trim().isEmpty) return const <int>[];
          final out = <int>[];
          for (final token in raw.split(',')) {
            final parsed = int.tryParse(token.trim());
            if (parsed != null) out.add(parsed);
          }
          return out;
        }
        return current?.therapyPatternSequence ?? const <int>[];
      }(),
      therapyCurrentPatternIndex: () {
        final raw =
            json['t_cur'] ??
                json['therapy_current_pattern_index'] ??
                (json['idx'] != null ? toInt(json['idx']) - 1 : null);
        if (raw == null) return current?.therapyCurrentPatternIndex ?? -1;
        if (raw is int) return raw;
        if (raw is num) return raw.toInt();
        return int.tryParse(raw.toString()) ?? -1;
      }(),
      therapyTotalPatterns: () {
        final val =
            json['t_total'] ?? json['therapy_total_patterns'] ?? json['total'];
        return val != null ? toInt(val) : (current?.therapyTotalPatterns ?? 0);
      }(),
      therapyPatternId: () {
        final val =
            json['pid'] ??
                (json['idx'] != null && json['seq'] is List
                    ? (json['seq'] as List)[toInt(json['idx']) - 1]
                    : null);
        if (val != null) return toInt(val);
        final pattStr = json['t_patt'] ?? json['therapy_pattern'];
        if (pattStr != null) {
          final idx = therapyPatternIndexFromName(pattStr.toString());
          if (idx != null) return idx;
        }
        return current?.therapyPatternId ?? -1;
      }(),
      therapyTotalDurationSeconds: () {
        final val =
            json['duration'] ??
                (json['remaining'] != null && json['elapsed'] != null
                    ? toInt(json['remaining']) + toInt(json['elapsed'])
                    : null) ??
                (json['t_rem'] != null && json['t_elap'] != null
                    ? toInt(json['t_rem']) + toInt(json['t_elap'])
                    : null);
        return val != null
            ? toInt(val)
            : (current?.therapyTotalDurationSeconds ?? 0);
      }(),
      therapyPatternDurationSeconds: () {
        final val =
            json['pattern_dur'] ??
                (json['p_remaining'] != null && json['p_elapsed'] != null
                    ? toInt(json['p_remaining']) + toInt(json['p_elapsed'])
                    : null);
        return val != null
            ? toInt(val)
            : (current?.therapyPatternDurationSeconds ?? 0);
      }(),
      therapyPatternElapsedSeconds: () {
        final val =
            json['p_elapsed'] ??
                (json['t']?.toString().toUpperCase() == 'TP' ? 0 : null);
        return val != null
            ? toInt(val)
            : (current?.therapyPatternElapsedSeconds ?? 0);
      }(),
      therapyPatternRemainingSeconds: () {
        final val =
            json['p_remaining'] ??
                (json['t']?.toString().toUpperCase() == 'TP'
                    ? json['pattern_dur']
                    : null);
        return val != null
            ? toInt(val)
            : (current?.therapyPatternRemainingSeconds ?? 0);
      }(),
      liveSessionId: () {
        final val = json['s_id'] ?? json['session_id'] ?? json['sid'];
        return val != null ? toInt(val) : (current?.liveSessionId ?? 0);
      }(),
      liveSessionElapsedSeconds: () {
        final val = json['s_elap'] ?? json['session_elapsed_sec'];
        return val != null
            ? toInt(val)
            : (current?.liveSessionElapsedSeconds ?? 0);
      }(),
      liveSessionStartEpoch: () {
        final val = json['s_start'] ?? json['session_start_epoch'];
        return val != null ? toInt(val) : (current?.liveSessionStartEpoch ?? 0);
      }(),
      liveSessionBadCount: () {
        final val = json['s_bad'] ?? json['session_bad_count'];
        return val != null ? toInt(val) : (current?.liveSessionBadCount ?? 0);
      }(),
      timestamp: DateTime.now(),
    );
  }

  String toCompactString() {
    return 'mode=$mode, sub=$subMode, angle=${angle.round()}, '
        'raw=(${rawXG.toStringAsFixed(2)}, ${rawYG.toStringAsFixed(2)}, '
        '${rawZG.toStringAsFixed(2)}), '
        'ang=(${angleX.round()}, ${angleY.round()}, '
        '${angleZ.round()}), '
        'cal=(${calY.toStringAsFixed(2)}, ${calZ.toStringAsFixed(2)}), '
        'calibrating=$isCalibrating, posture=$posture, bad=$isBadPosture, '
        'battery=${batteryVoltage.toStringAsFixed(2)}V ($batteryPercentage%), '
        'difficulty=$difficultyDeg, therapyNow=$therapyPattern, '
        'therapyNext=$therapyNextPattern, '
        'therapyElapsed=$therapyElapsedSeconds, '
        'therapyRemaining=$therapyRemainingSeconds, '
        'sessionId=$liveSessionId, sessionElapsed=$liveSessionElapsedSeconds';
  }
}

// ── Device Info model (from GET_DEVICE_INFO response) ───────────────────────

class DeviceInfo {
  final String deviceName;
  final String model;
  final String hardwareRevision;
  final String firmwareVersion;
  final String firmwareBuildDate;
  final String serial;
  final int batteryPercent;
  final bool dfuReady;

  const DeviceInfo({
    required this.deviceName,
    required this.model,
    required this.hardwareRevision,
    required this.firmwareVersion,
    required this.firmwareBuildDate,
    required this.serial,
    required this.batteryPercent,
    required this.dfuReady,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return DeviceInfo(
      deviceName: json['device_name']?.toString() ?? '',
      model:
      json['device_model']?.toString() ?? json['model']?.toString() ?? '',
      hardwareRevision: json['hw']?.toString() ?? '',
      firmwareVersion: json['fw']?.toString() ?? '',
      firmwareBuildDate: json['fw_build_date']?.toString() ?? '',
      serial: json['serial']?.toString() ?? '',
      batteryPercent: toInt(json['battery']),
      dfuReady: json['dfu_ready'] == true,
    );
  }

  @override
  String toString() {
    return 'DeviceInfo('
        'deviceName=$deviceName, '
        'model=$model, '
        'hw=$hardwareRevision, '
        'fw=$firmwareVersion, '
        'fwBuildDate=$firmwareBuildDate, '
        'serial=$serial, '
        'batteryPercent=$batteryPercent, '
        'dfuReady=$dfuReady'
        ')';
  }
}

class FirmwareProfile {
  final int id;
  final int slot;
  final String name;
  final bool isActive;
  final bool isDefault;
  final int createdEpoch;
  final int quality;

  const FirmwareProfile({
    required this.id,
    required this.slot,
    required this.name,
    required this.isActive,
    required this.isDefault,
    required this.createdEpoch,
    required this.quality,
  });

  factory FirmwareProfile.fromJson(Map<String, dynamic> json) {
    return FirmwareProfile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      slot:
      (json['s'] as num?)?.toInt() ?? (json['slot'] as num?)?.toInt() ?? 0,
      name: json['n']?.toString() ?? json['name']?.toString() ?? 'Profile',
      isActive: (json['a'] as num?)?.toInt() == 1 || json['active'] == true,
      isDefault: (json['d'] as num?)?.toInt() == 1 || json['default'] == true,
      createdEpoch:
      (json['c'] as num?)?.toInt() ??
          (json['created'] as num?)?.toInt() ??
          0,
      quality:
      (json['q'] as num?)?.toInt() ??
          (json['quality'] as num?)?.toInt() ??
          0,
    );
  }

  String get qualityLabel {
    if (quality >= 85) return 'Excellent';
    if (quality >= 70) return 'Good';
    if (quality >= 50) return 'Acceptable';
    return 'Low';
  }

  DateTime? get createdAt => createdEpoch > 0
      ? DateTime.fromMillisecondsSinceEpoch(createdEpoch * 1000)
      : null;

  @override
  String toString() =>
      'FirmwareProfile(id=$id, slot=$slot, name=$name, active=$isActive, default=$isDefault)';
}

class TherapyCompletion {
  final int sessionId;
  final bool completed;
  final int elapsedSeconds;
  final int durationSeconds;
  final int patternDurationSeconds;
  final int totalPatterns;
  final int uniquePatterns;
  final List<int> patternSequence;
  final DateTime timestamp;

  const TherapyCompletion({
    required this.sessionId,
    required this.completed,
    required this.elapsedSeconds,
    required this.durationSeconds,
    required this.patternDurationSeconds,
    required this.totalPatterns,
    required this.uniquePatterns,
    required this.patternSequence,
    required this.timestamp,
  });

  factory TherapyCompletion.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool toBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value.toInt() != 0;
      final normalized = value?.toString().trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    final rawSeq = json['seq'];
    final sequence = rawSeq is List
        ? rawSeq.map(toInt).toList(growable: false)
        : rawSeq
        ?.toString()
        .split(',')
        .map((token) => int.tryParse(token.trim()))
        .whereType<int>()
        .toList(growable: false) ??
        const <int>[];

    return TherapyCompletion(
      sessionId: toInt(json['sid'] ?? json['session_id']),
      completed: toBool(json['completed']),
      elapsedSeconds: toInt(json['elapsed']),
      durationSeconds: toInt(json['duration']),
      patternDurationSeconds: toInt(json['pattern_dur']),
      totalPatterns: toInt(json['total']),
      uniquePatterns: toInt(json['unique']),
      patternSequence: sequence,
      timestamp: DateTime.now(),
    );
  }
}

enum EnterDfuResult { success, lowBattery, sessionActive, timeout, error }

void _bleConsoleLog(String message) {
  debugPrint(message);
}

class AlignEyeDeviceService {
  AlignEyeDeviceService({String deviceNamePrefix = _kDefaultDeviceNamePrefix})
      : _deviceNamePrefix = deviceNamePrefix;

  final String _deviceNamePrefix;
  final _readingController = StreamController<PostureReading>.broadcast();
  final _profileListController =
  StreamController<List<FirmwareProfile>>.broadcast();
  final _therapyCompletionController =
  StreamController<TherapyCompletion>.broadcast();
  final _ackController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<List<FirmwareProfile>> get profileListStream =>
      _profileListController.stream;
  Stream<TherapyCompletion> get therapyCompletions =>
      _therapyCompletionController.stream;
  List<FirmwareProfile> _lastKnownProfiles = [];
  List<FirmwareProfile> get lastKnownProfiles =>
      List.unmodifiable(_lastKnownProfiles);

  String _profileNameFromList(List<FirmwareProfile> profiles) {
    FirmwareProfile? active;
    FirmwareProfile? defaultProfile;

    for (final profile in profiles) {
      if (profile.isActive) active ??= profile;
      if (profile.isDefault) defaultProfile ??= profile;
    }

    return (defaultProfile ?? active)?.name ?? '';
  }

  final connectionStatus = ValueNotifier<DeviceConnectionStatus>(
    DeviceConnectionStatus.disconnected,
  );
  final currentReading = ValueNotifier<PostureReading?>(null);
  final deviceInfo = ValueNotifier<DeviceInfo?>(null);
  final activeProfileName = ValueNotifier<String>('');
  String _lastKnownMode = 'IDLE';
  String _lastKnownSubMode = 'INSTANT';
  String _lastKnownProfile = '';
  int _lastKnownBattery = -1;
  DateTime? _lastUiFrame;
  Timer? _dataWatchdogTimer;
  DateTime? _lastDataReceivedAt;

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
  int latestTherapyPatternId = -1;
  int latestTherapyTotalDurationSeconds = 0;
  int latestTherapyPatternDurationSeconds = 0;

  /// Single source of truth for the therapy countdown so every UI surface
  /// (home mini card + immersive ongoing page) reads the same number.
  /// [_therapyRemainingAnchorSec] holds the remaining seconds *at the
  /// moment firmware reported them*, and [_therapyAnchorAt] is the wall
  /// clock for that report. Consumers derive live remaining via
  /// [therapyRemainingSecondsNow] which just subtracts elapsed wall time.
  int _therapyRemainingAnchorSec = -1;
  int _therapyElapsedAnchorSec = 0;
  DateTime? _therapyAnchorAt;

  int _patternElapsedAnchorSec = 0;
  int _patternRemainingAnchorSec = -1;

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
    if (_patternRemainingAnchorSec >= 0) {
      final anchor = _therapyAnchorAt;
      if (anchor == null) return _patternElapsedAnchorSec;
      final elapsed = DateTime.now().difference(anchor).inSeconds;
      return _patternElapsedAnchorSec + elapsed;
    }
    final value = therapyElapsedSecondsNow - _currentPatternStartElapsedSec;
    return value < 0 ? 0 : value;
  }

  int get therapyPatternRemainingSecondsNow {
    if (_patternRemainingAnchorSec >= 0) {
      final anchor = _therapyAnchorAt;
      if (anchor == null) return _patternRemainingAnchorSec;
      final elapsed = DateTime.now().difference(anchor).inSeconds;
      final value = _patternRemainingAnchorSec - elapsed;
      return value < 0 ? 0 : value;
    }
    return -1;
  }

  BluetoothDevice? _device;
  BluetoothDevice? get device => _device;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  String _buffer = '';
  bool _isConnecting = false;
  Timer? _connectionTimeoutTimer;
  Timer? _reconnectTimer;
  int _connectionRetryCount = 0;
  DateTime? _lastTherapyPlanRequestedAt;
  int _commandSeq = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  static const int _maxRetries = 1;
  static const Duration _connectionTimeout = Duration(seconds: 30);
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
  double get currentRawXG => currentReading.value?.rawXG ?? 0.0;
  double get currentRawYG => currentReading.value?.rawYG ?? 0.0;
  double get currentRawZG => currentReading.value?.rawZG ?? 0.0;
  double get currentAngleX => currentReading.value?.angleX ?? 0.0;
  double get currentAngleY => currentReading.value?.angleY ?? 0.0;
  double get currentAngleZ => currentReading.value?.angleZ ?? 0.0;
  double get currentCalY => currentReading.value?.calY ?? 0.0;
  double get currentCalZ => currentReading.value?.calZ ?? 0.0;
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

  int _nextCommandSeq() {
    _commandSeq = (_commandSeq + 1) & 0x7fffffff;
    if (_commandSeq == 0) _commandSeq = 1;
    return _commandSeq;
  }

  Future<void> sendModeControl({
    required String mode,
    required String postureTiming,
    required int therapyDurationMinutes,
    required int difficultyDegrees,
    int postureDelaySeconds = 5,
  }) async {
    if (connectionStatus.value != DeviceConnectionStatus.connected) {
      return;
    }

    final cleanMode = wireModeCommand(mode);
    final seq = _nextCommandSeq();
    final command = {'seq': seq, 'cmd': 'SET_MODE', 'mode': cleanMode};
    final ack = await _writeJsonCommandAndWaitForAck(
      command,
      timeout: const Duration(seconds: 2),
    );

    if (ack == null) {
      debugPrint('Mode control ACK timed out: $command');
    } else if (ack['ok'] == false) {
      debugPrint('Mode control rejected: $ack');
    }
  }

  /// Start a therapy session on the device with a specific duration and
  /// intensity level (1-3). The device drives the timing and pattern
  /// sequencing — the phone is just the remote. Returns true once the
  /// firmware ACKs the start command.
  ///
  /// Flow:
  ///   1. App -> FW: {"seq":N,"cmd":"THERAPY_START","therapy_duration":M,
  ///      "therapy_intensity":L}
  ///   2. FW -> App: {"t":"ACK","cmd":"THERAPY_START","seq":N,"ok":true}
  ///
  /// No explicit GET_THERAPY_PLAN call here on purpose — the "L" packet
  /// handler in _handleNotifyData already auto-requests the plan (rate
  /// limited via _lastTherapyPlanRequestedAt) once mode == THERAPY and
  /// latestTherapyPatternSequence is empty. Calling getTherapyPlan() here
  /// too would race with that fallback and double-fire the request.
  Future<bool> sendTherapyStart({
    required int durationMinutes,
    required int intensityLevel,
  }) async {
    if (connectionStatus.value != DeviceConnectionStatus.connected) {
      return false;
    }
    final clampedLevel = intensityLevel.clamp(1, 3);
    final supportedMinutes = const {10, 20, 30};
    final minutes = supportedMinutes.contains(durationMinutes)
        ? durationMinutes
        : 10;

    final seq = _nextCommandSeq();
    final command = {
      'seq': seq,
      'cmd': 'THERAPY_START',
      'therapy_duration': minutes,
      'therapy_intensity': clampedLevel,
    };

    final ack = await _writeJsonCommandAndWaitForAck(
      command,
      timeout: const Duration(seconds: 2),
    );

    if (ack == null) {
      debugPrint('Therapy start ACK timed out: $command');
      return false;
    }
    if (ack['ok'] == false) {
      debugPrint('Therapy start rejected: $ack');
      return false;
    }

    return true;
  }

  /// Stop an in-progress therapy session and return the device to training.
  Future<bool> sendTherapyStop() async {
    if (connectionStatus.value != DeviceConnectionStatus.connected) {
      return false;
    }

    final seq = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

    final resp = await sendJsonCommand(
      {'seq': seq, 'cmd': 'THERAPY_STOP'},
      matcher: (m) =>
      m['t']?.toString().toUpperCase() == 'ACK' &&
          m['cmd']?.toString().toUpperCase() == 'THERAPY_STOP' &&
          m['seq'] == seq,
      timeout: const Duration(seconds: 2),
    );

    if (resp != null && resp['ok'] != false) {
      return true;
    }

    return _writeTextCommand('MODE=TRAINING');
  }

  /// Update only the therapy intensity while a session is running. Useful
  /// if we ever allow mid-session adjustment; firmware applies it on the
  /// next motor write without disturbing the pattern shape.
  Future<bool> sendTherapyIntensity(int intensityLevel) async {
    if (connectionStatus.value != DeviceConnectionStatus.connected) {
      return false;
    }
    final clampedLevel = intensityLevel.clamp(1, 3);
    return _writeTextCommand('THERAPY_INTENSITY=$clampedLevel');
  }

  /// Sends the current phone date/time and timezone to the device.
  /// Firmware prints the received time as local date/time in the Serial monitor.
  Future<bool> sendDateTime() async {
    if (connectionStatus.value != DeviceConnectionStatus.connected) {
      return false;
    }
    final now = DateTime.now();
    final epochSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final tzOffsetSeconds = now.timeZoneOffset.inSeconds;
    return _writeTextCommand('TIME=$epochSeconds;TZ=$tzOffsetSeconds');
  }

  Future<bool> sendCalibrationStart() async {
    if (connectionStatus.value != DeviceConnectionStatus.connected) {
      return false;
    }
    return _writeTextCommand('ACTION=CALIBRATE');
  }

  Future<bool> sendCalibrationCancel() async {
    if (connectionStatus.value != DeviceConnectionStatus.connected) {
      return false;
    }
    return _writeTextCommand('ACTION=CALIBRATE_CANCEL');
  }

  Future<bool> getProfiles() async {
    if (connectionStatus.value != DeviceConnectionStatus.connected)
      return false;
    return _writeJsonCommand({'cmd': 'GET_PROFILES'});
  }

  Future<bool> getTherapyPlan() async {
    if (connectionStatus.value != DeviceConnectionStatus.connected)
      return false;
    return _writeJsonCommand({'cmd': 'GET_THERAPY_PLAN'});
  }

  Future<bool> sendCalibrationStartJson({String name = 'Profile'}) async {
    if (connectionStatus.value != DeviceConnectionStatus.connected)
      return false;
    return _writeJsonCommand({
      'cmd': 'CALIBRATE_START',
      'slot': 'auto',
      'name': name,
    });
  }

  Future<bool> setDefaultProfile(int profileId) async {
    if (connectionStatus.value != DeviceConnectionStatus.connected)
      return false;
    return _writeJsonCommand({'cmd': 'PROFILE_SET_DEFAULT', 'id': profileId});
  }

  Future<bool> selectProfile(int profileId) async {
    if (connectionStatus.value != DeviceConnectionStatus.connected)
      return false;
    return _writeJsonCommand({'cmd': 'PROFILE_SELECT', 'id': profileId});
  }

  Future<bool> renameProfile(int profileId, String name) async {
    if (connectionStatus.value != DeviceConnectionStatus.connected)
      return false;
    return _writeJsonCommand({
      'cmd': 'PROFILE_RENAME',
      'id': profileId,
      'name': name,
    });
  }

  Future<bool> deleteProfile(int profileId) async {
    if (connectionStatus.value != DeviceConnectionStatus.connected)
      return false;
    return _writeJsonCommand({'cmd': 'PROFILE_DELETE', 'id': profileId});
  }

  Future<bool> clearAllProfiles() async {
    if (connectionStatus.value != DeviceConnectionStatus.connected)
      return false;
    return _writeJsonCommand({'cmd': 'PROFILE_CLEAR_ALL'});
  }

  Future<bool> _writeJsonCommand(Map<String, dynamic> command) async {
    return _writeTextCommand(jsonEncode(command));
  }

  Future<Map<String, dynamic>?> _writeJsonCommandAndWaitForAck(
      Map<String, dynamic> command, {
        Duration timeout = const Duration(seconds: 2),
      }) async {
    final seq = command['seq'];
    final cmd = command['cmd']?.toString().toUpperCase();
    if (seq == null || cmd == null || cmd.isEmpty) {
      final written = await _writeJsonCommand(command);
      return written ? <String, dynamic>{'ok': true} : null;
    }

    final completer = Completer<Map<String, dynamic>?>();
    late StreamSubscription<Map<String, dynamic>> sub;
    sub = _ackController.stream.listen((ack) {
      final ackCmd = ack['cmd']?.toString().toUpperCase();
      final ackSeq = ack['seq']?.toString();
      if (ackSeq == seq.toString() && ackCmd == cmd && !completer.isCompleted) {
        completer.complete(ack);
      }
    });

    final written = await _writeJsonCommand(command);
    if (!written) {
      await sub.cancel();
      return null;
    }

    final result = await completer.future.timeout(
      timeout,
      onTimeout: () => null,
    );
    await sub.cancel();
    return result;
  }

  /// Sends a JSON command (e.g. {"cmd":"GET_INFO"}) and waits up to
  /// [timeout] for a matching response on the notify characteristic.
  /// Returns the parsed JSON map or null on timeout / error.
  Future<Map<String, dynamic>?> sendJsonCommand(
      Map<String, dynamic> command, {
        Duration timeout = const Duration(seconds: 6),
        bool Function(Map<String, dynamic>)? matcher,
      }) async {
    if (connectionStatus.value != DeviceConnectionStatus.connected) return null;
    final characteristic = _notifyCharacteristic;
    if (characteristic == null) return null;

    final payload = jsonEncode(command);
    final completer = Completer<Map<String, dynamic>?>();
    StreamSubscription<PostureReading>? sub;

    sub = readings.listen((r) {
      // We can't easily intercept raw notify bytes here since they are parsed
      // into PostureReading. Instead we rely on the raw notification stream
      // captured below; this subscription is a no-op placeholder.
    });

    // Capture raw characteristic notifications directly while we wait.
    StreamSubscription<List<int>>? rawSub;
    final rawStream = characteristic.onValueReceived;
    String rawBuffer = '';
    rawSub = rawStream.listen((bytes) {
      rawBuffer += utf8.decode(bytes, allowMalformed: true);
      // Scan for complete JSON objects
      int depth = 0;
      int start = -1;
      for (int i = 0; i < rawBuffer.length; i++) {
        if (rawBuffer[i] == '{') {
          if (depth == 0) start = i;
          depth++;
        } else if (rawBuffer[i] == '}') {
          depth--;
          if (depth == 0 && start >= 0) {
            final chunk = rawBuffer.substring(start, i + 1);
            rawBuffer = rawBuffer.substring(i + 1);
            try {
              final parsed = jsonDecode(chunk) as Map<String, dynamic>;
              if (matcher == null || matcher(parsed)) {
                if (!completer.isCompleted) completer.complete(parsed);
              }
            } catch (_) {}
            break;
          }
        }
      }
    });

    try {
      await characteristic.write(
        utf8.encode(payload),
        withoutResponse: characteristic.properties.writeWithoutResponse,
      );
      debugPrint('JSON command sent: $payload');
      if (payload.contains('GET_DEVICE_INFO')) {
        _bleConsoleLog('BLE TX APP: $payload');
      }
    } catch (e) {
      debugPrint('Failed to send JSON command: $e');
      if (payload.contains('GET_DEVICE_INFO')) {
        _bleConsoleLog('BLE TX APP FAILED: $payload error=$e');
      }
      await rawSub.cancel();
      await sub.cancel();
      return null;
    }

    final result = await completer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint('JSON command timed out: $payload');
        if (payload.contains('GET_DEVICE_INFO')) {
          _bleConsoleLog('GET_DEVICE_INFO timed out waiting for INFO packet');
        }
        return null;
      },
    );

    await rawSub.cancel();
    await sub.cancel();
    return result;
  }

  /// Sends {"cmd":"GET_DEVICE_INFO"} and returns a DeviceInfo on success.
  Future<DeviceInfo?> getDeviceInfo() async {
    final resp = await sendJsonCommand({
      'cmd': 'GET_DEVICE_INFO',
    }, matcher: (m) => m['t'] == 'INFO');
    if (resp == null) return null;
    _bleConsoleLog('GET_DEVICE_INFO response: $resp');
    final info = DeviceInfo.fromJson(resp);
    _bleConsoleLog('Parsed device info: $info');
    return info;
  }

  /// Waits for an unsolicited notification matching [matcher] without sending
  /// any command. Returns the parsed map or null on timeout.
  Future<Map<String, dynamic>?> waitForNotification({
    required bool Function(Map<String, dynamic>) matcher,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (connectionStatus.value != DeviceConnectionStatus.connected) return null;
    final characteristic = _notifyCharacteristic;
    if (characteristic == null) return null;

    final completer = Completer<Map<String, dynamic>?>();
    final rawStream = characteristic.onValueReceived;
    String rawBuffer = '';
    StreamSubscription<List<int>>? rawSub;

    rawSub = rawStream.listen((bytes) {
      rawBuffer += utf8.decode(bytes, allowMalformed: true);
      int depth = 0;
      int start = -1;
      for (int i = 0; i < rawBuffer.length; i++) {
        if (rawBuffer[i] == '{') {
          if (depth == 0) start = i;
          depth++;
        } else if (rawBuffer[i] == '}') {
          depth--;
          if (depth == 0 && start >= 0) {
            final chunk = rawBuffer.substring(start, i + 1);
            rawBuffer = rawBuffer.substring(i + 1);
            try {
              final parsed = jsonDecode(chunk) as Map<String, dynamic>;
              if (matcher(parsed)) {
                if (!completer.isCompleted) completer.complete(parsed);
              }
            } catch (_) {}
            break;
          }
        }
      }
    });

    final result = await completer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint('waitForNotification timed out');
        return null;
      },
    );

    await rawSub.cancel();
    return result;
  }

  /// Sends {"cmd":"ENTER_DFU"} and waits for a two-step ARMED→ENTERED ack.
  Future<EnterDfuResult> sendEnterDfu() async {
    bool hasDfuStatus(Map<String, dynamic> message) {
      return message['dfu'] != null || message['status'] != null;
    }

    String normalizedDfuStatus(Map<String, dynamic> message) {
      final value = message['dfu'] ?? message['status'];
      return value?.toString().trim().toUpperCase() ?? '';
    }

    // Step 1: Send command, wait for ARMED ack
    final resp = await sendJsonCommand(
      {'cmd': 'ENTER_DFU'},
      matcher: hasDfuStatus,
      timeout: const Duration(seconds: 8),
    );

    if (resp == null) return EnterDfuResult.timeout;
    final status = normalizedDfuStatus(resp);
    if (status == 'ERROR') {
      final reason = resp['reason']?.toString() ?? '';
      if (reason == 'LOW_BATTERY') return EnterDfuResult.lowBattery;
      if (reason == 'SESSION_ACTIVE') return EnterDfuResult.sessionActive;
      return EnterDfuResult.error;
    }

    // Check for ARMED
    if (status != 'ARMED' && status != 'OK') {
      return EnterDfuResult.error;
    }

    debugPrint('DFU: ARMED received, waiting for ENTERED...');

    // Step 2: Wait for DFU:"ENTERED" (device rebooting into bootloader)
    final entered = await waitForNotification(
      matcher: (m) => normalizedDfuStatus(m) == 'ENTERED',
      timeout: const Duration(seconds: 15),
    );

    if (entered == null) {
      debugPrint('DFU: ENTERED timeout — continuing anyway');
      return EnterDfuResult.timeout;
    }

    debugPrint('DFU: ENTERED confirmed');
    return EnterDfuResult.success;
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

  Future<void> connect({String? remoteId}) async {
    // Prevent concurrent connection attempts
    if (_isConnecting) {
      debugPrint('Connection already in progress, ignoring duplicate request');
      return;
    }

    if (connectionStatus.value == DeviceConnectionStatus.connected) {
      debugPrint('Already connected, skipping connection attempt');
      return;
    }

    // Reset retry count for new connection attempt
    if (connectionStatus.value == DeviceConnectionStatus.disconnected) {
      _connectionRetryCount = 0;
    }

    _isConnecting = true;

    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        _isConnecting = false;
        connectionStatus.value = DeviceConnectionStatus.disconnected;
        return;
      }

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

      final preferredDeviceId = remoteId ?? await _loadLastConnectedDeviceId();
      // Always prefer the already paired / previously-connected pod so we
      // don't accidentally target an unpaired pod nearby and trigger a fresh
      // Android pair request.
      final device = await _scanForDevice(
        preferredRemoteId: preferredDeviceId,
        preferPairedDevice: remoteId == null,
        prioritizePreferredDevice: preferredDeviceId != null,
        requirePairedDevice: false,
        timeout: _defaultScanTimeout,
      );
      if (device == null) {
        debugPrint('Device not found - scan returned null');
        _isConnecting = false;
        _connectionTimeoutTimer?.cancel();
        connectionStatus.value = DeviceConnectionStatus.disconnected;

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
        const bool shouldAutoConnect = false;
        debugPrint(
          'Connecting to device (autoConnect: $shouldAutoConnect, isPaired: $isPaired)...',
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
              final mtu = await _device!.requestMtu(251, timeout: 3);
              debugPrint('MTU negotiated: $mtu');
              if (mtu < 100) {
                debugPrint('MTU too low ($mtu) — disconnecting');
                _isConnecting = false;
                _connectionTimeoutTimer?.cancel();
                await disconnect();
                return;
              }
            } catch (e) {
              debugPrint('Failed to request MTU (non-fatal): $e');
            }
          }
        } catch (e) {
          debugPrint('Connection failed: $e');

          // MTU negotiation can fail if the device briefly drops the link right
          // after GATT connect.  The physical connection was established (GATT
          // connected), so treat this as a non-fatal hiccup and fall through to
          // service discovery rather than aborting the whole connect attempt.
          final isMtuError =
              e.toString().toLowerCase().contains('requestmtu') ||
                  e.toString().toLowerCase().contains('mtu');
          final deviceAfterError = _device;
          final stateAfterError = deviceAfterError == null
              ? BluetoothConnectionState.disconnected
              : await deviceAfterError.connectionState.first.timeout(
            const Duration(seconds: 2),
            onTimeout: () => BluetoothConnectionState.disconnected,
          );
          debugPrint('Connection state after error: $stateAfterError');

          // If the MTU request itself failed but device is still connected,
          // continue with service discovery (MTU failure is not fatal).
          if (isMtuError &&
              stateAfterError == BluetoothConnectionState.connected) {
            debugPrint('MTU error but device still connected — continuing...');
            // fall through to service discovery below
          } else {
            rethrow;
          }
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

      // final cachedValue = _notifyCharacteristic!.lastValue;
      // if (cachedValue.isNotEmpty) {
      //   _handleNotifyData(cachedValue);
      // }

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
        if (last != null && DateTime.now().difference(last).inSeconds > 25) {
          if (currentIsCalibrating) return;
          debugPrint('WATCHDOG: No data for 15s, forcing disconnect');
          disconnect();
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
      connectionStatus.value = DeviceConnectionStatus.connected;
      _connectionRetryCount = 0; // Reset retry count on success

      // Sync phone time to device immediately after every successful connection.
      sendDateTime().then((sent) {
        debugPrint(sent ? 'DateTime synced to device' : 'DateTime sync failed');
      });

      Future.delayed(const Duration(milliseconds: 500), () {
        if (connectionStatus.value == DeviceConnectionStatus.connected) {
          getProfiles().then((_) => debugPrint('GET_PROFILES sent on connect'));
          // GET_DEVICE_INFO is handled by home_page after 5s (with firmware check)
        }
      });

      // Save connection state: user has connected
      await _saveConnectionState(
        hasEverConnected: true,
        lastConnectedDeviceId: _device?.remoteId.toString(),
      );
      debugPrint('Saved connection state: hasEverConnected=true');

      debugPrint('Connection established successfully');
    } catch (e) {
      debugPrint('Connection error: $e');
      _isConnecting = false;
      _connectionTimeoutTimer?.cancel();
      await disconnect();
      connectionStatus.value = DeviceConnectionStatus.disconnected;
    }
  }

  Future<void> disconnect({bool userInitiated = false}) async {
    debugPrint('Disconnecting (userInitiated: $userInitiated)');

    // Cancel any pending connection attempts
    _isConnecting = false;
    _connectionTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();

    final deviceToDisconnect = _device;

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
    }
    _dataWatchdogTimer?.cancel();

    _device = null;
    _notifyCharacteristic = null;
    currentReading.value = null;
    deviceInfo.value = null;
    activeProfileName.value = '';
    connectionStatus.value = DeviceConnectionStatus.disconnected;

    debugPrint('Disconnect completed');
  }

  Future<void> forgetDevice() async {
    debugPrint('Forgetting AlignEye device');

    _connectionTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();

    final deviceToForget = _device;

    await _saveConnectionState(
      hasEverConnected: false,
      clearLastConnectedDeviceId: true,
    );

    if (deviceToForget != null) {
      try {
        await deviceToForget.disconnect();
      } catch (_) {}

      try {
        await _unpairDevice(deviceToForget);
      } catch (e) {
        debugPrint('Failed to unpair active device: $e');
      }
    }

    try {
      final bonded = await FlutterBluePlus.bondedDevices;
      for (final dev in bonded) {
        if (_matchesTargetDeviceName(dev.platformName)) {
          debugPrint(
            'Unpairing bonded target device: ${dev.platformName} (${dev.remoteId})',
          );
          await _unpairDevice(dev);
        }
      }
    } catch (e) {
      debugPrint('Failed to unpair bonded devices: $e');
    }

    _device = null;
    _notifyCharacteristic = null;
    currentReading.value = null;
    activeProfileName.value = '';
    connectionStatus.value = DeviceConnectionStatus.disconnected;

    debugPrint('Device forgotten successfully');
  }

  Future<void> dispose() async {
    debugPrint('Disposing AlignEyeDeviceService');
    _connectionTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    await disconnect();
    await _readingController.close();
    await _profileListController.close();
    await _therapyCompletionController.close();
    await _ackController.close();
    await _cleanupScan();
    connectionStatus.dispose();
    currentReading.dispose();
    deviceInfo.dispose();
    activeProfileName.dispose();
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
      final preferredId = await _loadLastConnectedDeviceId();
      if (preferredId == null) {
        return false;
      }
      final bondedDevices = await FlutterBluePlus.bondedDevices;
      return bondedDevices.any(
            (device) =>
        device.remoteId.toString().toLowerCase() ==
            preferredId.toLowerCase(),
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
      if (normalizedPreferredId != null) {
        if (deviceId == normalizedPreferredId) {
          debugPrint(
            'Found preferred connected device: ${device.platformName}',
          );
          return device;
        }
      } else {
        if (_matchesTargetDeviceName(device.platformName)) {
          connectedMatch ??= device;
        }
      }
    }
    if (normalizedPreferredId == null && connectedMatch != null) {
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
    final rawData = utf8.decode(data, allowMalformed: true);
    // debugPrint("BLE RAW: $rawData");
    if (rawData.contains('"t":"C"') || rawData.contains('"t":"c"')) {
      debugPrint("BLE RAW CALIB: $rawData");
    }
    _lastDataReceivedAt = DateTime.now();
    // _buffer += utf8.decode(data, allowMalformed: true);
    _buffer += rawData;

    // if (_buffer.length > 2048) {
    if (_buffer.length > 10000) {
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
          depth++;
        } else if (ch == '}') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }

      if (end == -1) {
        if (_buffer.length > 5000) {
          debugPrint("BUFFER DATA:");
          debugPrint(_buffer);
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
          final packetType = decoded['t']?.toString().toUpperCase();

          switch (packetType) {
            case 'INFO':
              final info = DeviceInfo.fromJson(decoded);
              _bleConsoleLog('BLE RX DEVICE INFO RAW: $decoded');
              _bleConsoleLog(
                'BLE RX DEVICE INFO: '
                    'name=${info.deviceName}, '
                    'model=${info.model}, '
                    'hw=${info.hardwareRevision}, '
                    'fw=${info.firmwareVersion}, '
                    'build=${info.firmwareBuildDate}, '
                    'serial=${info.serial}',
              );
              deviceInfo.value = info;
              break;

            case 'L':
            // Fast live posture packet
            // Update angle, mode, difficulty_angle, posture immediately.
            // Do not throttle this packet.
              if (decoded['mode'] == null) decoded['mode'] = _lastKnownMode;
              if (decoded['sub_mode'] == null && _lastKnownSubMode.isNotEmpty) {
                decoded['sub_mode'] = _lastKnownSubMode;
              }
              if (decoded['profile'] == null && _lastKnownProfile.isNotEmpty) {
                decoded['profile'] = _lastKnownProfile;
              }
              if (decoded['battery'] == null && _lastKnownBattery >= 0) {
                decoded['battery'] = _lastKnownBattery;
              }

              final reading = PostureReading.fromJson(
                decoded,
                current: currentReading.value,
              );
              _updateTherapyCache(reading);
              _emitReading(reading, throttle: false);

              if (reading.mode.toUpperCase() == 'THERAPY' &&
                  latestTherapyPatternSequence.isEmpty) {
                final now = DateTime.now();
                if (_lastTherapyPlanRequestedAt == null ||
                    now.difference(_lastTherapyPlanRequestedAt!).inSeconds >=
                        5) {
                  _lastTherapyPlanRequestedAt = now;
                  getTherapyPlan();
                }
              }
              break;

            case 'T':
            // Slow telemetry packet
            // Update cached mode, submode, profile, battery.
            // Use normalizeDeviceMode for mode.
              if (decoded['mode'] != null) {
                _lastKnownMode = normalizeDeviceMode(decoded['mode']);
              }
              if (decoded['sub_mode'] != null) {
                _lastKnownSubMode = decoded['sub_mode'].toString();
              }
              if (decoded['profile'] != null) {
                _lastKnownProfile = decoded['profile'].toString();
              }
              if (decoded['battery'] != null) {
                _lastKnownBattery =
                    int.tryParse(decoded['battery'].toString()) ??
                        _lastKnownBattery;
              }

              final reading = PostureReading.fromJson(
                decoded,
                current: currentReading.value,
              );
              _updateTherapyCache(reading);
              _emitReading(reading, throttle: false);
              break;

            case 'TL':
            // Therapy live progress packet
            // Update therapy timer/progress cache.
            // Do not overwrite live angle/posture unless fields are present.
              if (decoded['mode'] == null) {
                decoded['mode'] = currentReading.value?.mode ?? 'THERAPY';
              }
              final reading = PostureReading.fromJson(
                decoded,
                current: currentReading.value,
              );
              _updateTherapyCache(reading);
              _emitReading(reading, throttle: false);
              break;

            case 'TP':
            // Therapy plan packet
            // Update therapy plan/pattern sequence only.
              if (decoded['mode'] == null) {
                decoded['mode'] = currentReading.value?.mode ?? 'THERAPY';
              }
              final reading = PostureReading.fromJson(
                decoded,
                current: currentReading.value,
              );
              _updateTherapyCache(reading);
              _emitReading(reading, throttle: false);
              break;

            case 'TC':
            // Therapy complete summary packet. Firmware sends this once,
            // then returns the pod to training mode.
              final completion = TherapyCompletion.fromJson(decoded);
              if (completion.patternSequence.isNotEmpty) {
                latestTherapyPatternSequence = List<int>.unmodifiable(
                  completion.patternSequence,
                );
              }
              if (completion.totalPatterns > 0) {
                latestTherapyTotalPatterns = completion.totalPatterns;
              }
              if (completion.durationSeconds > 0) {
                latestTherapyTotalDurationSeconds = completion.durationSeconds;
              }
              if (completion.patternDurationSeconds > 0) {
                latestTherapyPatternDurationSeconds =
                    completion.patternDurationSeconds;
              }
              _therapyRemainingAnchorSec = 0;
              _therapyElapsedAnchorSec = completion.elapsedSeconds;
              _therapyAnchorAt = DateTime.now();
              _patternElapsedAnchorSec = completion.patternDurationSeconds;
              _patternRemainingAnchorSec = 0;
              _therapyCompletionController.add(completion);

              final completionReading = PostureReading.fromJson({
                ...decoded,
                'mode': 'TRAINING',
                't_rem': 0,
                't_elap': completion.elapsedSeconds,
                'duration': completion.durationSeconds,
                'pattern_dur': completion.patternDurationSeconds,
                't_total': completion.totalPatterns,
              }, current: currentReading.value);
              _emitReading(completionReading, throttle: false);
              break;

            case 'C':
            // Calibration packet
            // Update calibration state/progress/result.
              debugPrint(
                "📦 CALIB PACKET => isCalibrating=${decoded['isCalibrating']} phase=${decoded['c_phase']} "
                    "result=${decoded['result'] ?? decoded['calibResult'] ?? decoded['calibrationResult']} "
                    "elap=${decoded['c_elap']}/${decoded['c_tot']}",
              );
              final reading = PostureReading.fromJson(
                decoded,
                current: currentReading.value,
              );
              _updateTherapyCache(reading);
              _emitReading(reading, throttle: false);
              break;

            case 'P':
            // Profile list packet
            // Update profile list only.
            // Do not emit fake posture reading.
              final rawList = decoded['profiles'];
              final profiles = (rawList is List)
                  ? rawList
                  .whereType<Map<String, dynamic>>()
                  .map(FirmwareProfile.fromJson)
                  .toList()
                  : <FirmwareProfile>[];

              final hasActiveCustom = profiles.any((p) => p.isActive);
              final hasDefaultCustom = profiles.any((p) => p.isDefault);

              final systemDefault = FirmwareProfile(
                id: 0,
                slot: 0,
                name: 'System default',
                isActive: !hasActiveCustom,
                isDefault: !hasDefaultCustom,
                createdEpoch: 0,
                quality: 100,
              );

              final combined = [systemDefault, ...profiles];
              _lastKnownProfiles = combined;
              activeProfileName.value = _profileNameFromList(combined);
              _profileListController.add(
                combined,
              ); // always emit, even if empty
              debugPrint('📋 PROFILE LIST => ${combined.length} profiles');
              break;

            case 'ACK':
            // Command acknowledgement only.
            // Do not emit fake posture reading.
              _ackController.add(Map<String, dynamic>.unmodifiable(decoded));
              debugPrint(
                'Command ACK received: '
                    'seq=${decoded['seq']} cmd=${decoded['cmd']} ok=${decoded['ok']}',
              );
              break;
          }
        }
      } catch (e) {
        debugPrint("JSON ERROR: $e");
        debugPrint("BAD JSON:");
        debugPrint(chunk);
      }
    }
  }

  void _handleConnectionUpdate(BluetoothConnectionState state) {
    debugPrint('Connection state changed: $state');

    if (state == BluetoothConnectionState.connected) {
      _isConnecting = false;
      _connectionTimeoutTimer?.cancel();
      _connectionRetryCount = 0;

      // Save state: user has connected again
      _saveConnectionState(lastConnectedDeviceId: _device?.remoteId.toString());

      // Verify connection is actually working
      _verifyConnection().then((isValid) {
        if (isValid) {
          connectionStatus.value = DeviceConnectionStatus.connected;
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
      }
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

  /// Save connection state to persistent storage
  Future<void> _saveConnectionState({
    bool? hasEverConnected,
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
    } catch (e) {
      debugPrint('Error saving connection state: $e');
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

  void _emitReading(PostureReading reading, {bool throttle = false}) {
    currentReading.value = reading;

    if (!throttle) {
      _readingController.add(reading);
      return;
    }

    final now = DateTime.now();
    if (_lastUiFrame == null ||
        now.difference(_lastUiFrame!).inMilliseconds >= 100) {
      _lastUiFrame = now;
      _readingController.add(reading);
    }
  }

  void _updateTherapyCache(PostureReading reading) {
    final isTherapy = reading.mode.trim().toUpperCase() == 'THERAPY';
    if (isTherapy) {
      if (reading.therapyPatternSequence.isNotEmpty) {
        latestTherapyPatternSequence = List<int>.unmodifiable(
          reading.therapyPatternSequence,
        );
      }
      if (reading.therapyCurrentPatternIndex >= 0) {
        latestTherapyCurrentPatternIndex = reading.therapyCurrentPatternIndex;
      }
      if (reading.therapyTotalPatterns > 0) {
        latestTherapyTotalPatterns = reading.therapyTotalPatterns;
      }
      if (reading.therapyPatternId >= 0) {
        latestTherapyPatternId = reading.therapyPatternId;
      }
      if (reading.therapyTotalDurationSeconds > 0) {
        latestTherapyTotalDurationSeconds = reading.therapyTotalDurationSeconds;
      }
      if (reading.therapyPatternDurationSeconds > 0) {
        latestTherapyPatternDurationSeconds =
            reading.therapyPatternDurationSeconds;
      }
      final pattName = reading.therapyPattern.trim();
      if (pattName.isNotEmpty) {
        // Firmware decorates the name with "[S2:13 0s]" — strip it
        // before comparing so we don't treat every second as a new
        // pattern boundary.
        String strip(String v) {
          final b = v.indexOf('[');
          return b <= 0 ? v.trim() : v.substring(0, b).trim();
        }

        final prevClean = strip(latestTherapyPatternName);
        final newClean = strip(pattName);
        if (prevClean != newClean) {
          // Pattern boundary — remember when it started so the mini
          // card and ongoing page can show pattern-elapsed in sync.
          _currentPatternStartElapsedSec = reading.therapyElapsedSeconds;
        }
        latestTherapyPatternName = pattName;
      }
      final nextName = reading.therapyNextPattern.trim();
      if (nextName.isNotEmpty) latestTherapyNextPatternName = nextName;
      // Re-anchor the countdown on every therapy frame. Consumers
      // extrapolate from this anchor via a local 1 Hz ticker, so the
      // displayed countdown stays buttery-smooth between BLE frames
      // and stays consistent across home + ongoing-therapy pages.
      if (reading.therapyRemainingSeconds > 0 ||
          reading.therapyElapsedSeconds > 0) {
        _therapyRemainingAnchorSec = reading.therapyRemainingSeconds;
        _therapyElapsedAnchorSec = reading.therapyElapsedSeconds;
        _therapyAnchorAt = DateTime.now();

        _patternElapsedAnchorSec = reading.therapyPatternElapsedSeconds;
        _patternRemainingAnchorSec = reading.therapyPatternRemainingSeconds;
      }
    } else {
      // Device left therapy mode — clear the cache so the next session
      // starts from a clean slate.
      latestTherapyPatternSequence = const [];
      latestTherapyCurrentPatternIndex = -1;
      latestTherapyTotalPatterns = 0;
      latestTherapyPatternName = '';
      latestTherapyNextPatternName = '';
      latestTherapyPatternId = -1;
      latestTherapyTotalDurationSeconds = 0;
      latestTherapyPatternDurationSeconds = 0;
      _therapyRemainingAnchorSec = -1;
      _therapyElapsedAnchorSec = 0;
      _therapyAnchorAt = null;
      _currentPatternStartElapsedSec = 0;
      _patternElapsedAnchorSec = 0;
      _patternRemainingAnchorSec = -1;
      _lastTherapyPlanRequestedAt = null;
    }
  }
}