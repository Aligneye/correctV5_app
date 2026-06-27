import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One angle reading captured from the live BLE stream.
class AnglePoint {
  final DateTime time;
  final double deviation; // always positive, degrees from calibrated position

  const AnglePoint({required this.time, required this.deviation});
}

/// Singleton service that:
///  - Saves the calibrated reference angle (set after each calibration).
///  - Listens to the live BLE angle stream.
///  - Keeps the last 24 hours of angle deviation samples (one per 5 sec).
///  - Exposes per-hour averages for the Analytics graph.
class AngleHistoryService {
  AngleHistoryService._internal();
  static final AngleHistoryService _instance = AngleHistoryService._internal();
  factory AngleHistoryService() => _instance;

  static const _keyRefAngle = 'angle_history_ref_angle';
  static const _sampleIntervalSec = 1; // capture one sample every 1 seconds
  static const _maxHistory = 24 * 60 * 60; // 24 hrs at 1 per sec = 86400

  // Reference (calibrated) angle — deviation = abs(current - ref)
  double _refAngle = 0.0;

  // In-memory ring buffer of today's samples
  final List<AnglePoint> _history = [];

  DateTime? _lastSampleTime;
  StreamSubscription<double>? _angleSub;

  double get referenceAngle => _refAngle;

  /// Call once from DeviceManager.init() after BLE is wired up.
  /// [angleStream] should emit the raw `angle` value from every PostureReading.
  Future<void> init(Stream<double> angleStream) async {
    // Load saved reference angle
    try {
      final prefs = await SharedPreferences.getInstance();
      _refAngle = prefs.getDouble(_keyRefAngle) ?? 0.0;
    } catch (_) {}

    // Subscribe to live angle stream, sample every 5 seconds
    await _angleSub?.cancel();
    _angleSub = angleStream.listen(_onAngle);
  }

  /// Call this right after a successful calibration completes.
  /// Pass the current raw angle reading at the moment calibration finished.
  Future<void> setReferenceAngle(double angle) async {
    _refAngle = angle;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyRefAngle, angle);
    } catch (_) {}
    debugPrint('AngleHistoryService: reference angle set to $angle°');
  }


  Future<void> syncToSupabase(String userId) async {
    if (_history.isEmpty) return;
    try {
      final client = Supabase.instance.client;
      final rows = _history.map((p) => {
        'user_id': userId,
        'time': p.time.toUtc().toIso8601String(),
        'deviation': p.deviation,
        'ref_angle': _refAngle,
      }).toList();

      await client.from('angle_history').upsert(rows);
      debugPrint('AngleHistoryService: ${rows.length} rows synced');
    } catch (e) {
      debugPrint('AngleHistoryService: sync failed $e');
    }
  }

  void _onAngle(double rawAngle) {
    final now = DateTime.now();

    // Rate-limit: one sample per _sampleIntervalSec
    if (_lastSampleTime != null &&
        now.difference(_lastSampleTime!).inSeconds < _sampleIntervalSec) {
      return;
    }
    _lastSampleTime = now;

    final deviation = (rawAngle - _refAngle).abs();
    _history.add(AnglePoint(time: now, deviation: deviation));

    // Remove samples older than 24 hours
    final cutoff = now.subtract(const Duration(hours: 24));
    _history.removeWhere((p) => p.time.isBefore(cutoff));

    // Also cap by max count
    if (_history.length > _maxHistory) {
      _history.removeRange(0, _history.length - _maxHistory);
    }
  }

  /// Returns 7 average deviation values for today:
  /// [8am, 10am, 12pm, 2pm, 4pm, 6pm, 8pm]
  /// Each slot covers a 2-hour window. Returns 0 if no data in that window.
  List<double> todayHourlyDeviations() {
    const hours = [8, 10, 12, 14, 16, 18, 20];
    final today = DateTime.now();

    return hours.map((h) {
      final windowStart = DateTime(today.year, today.month, today.day, h);
      final windowEnd = windowStart.add(const Duration(hours: 2));

      final samples = _history
          .where((p) =>
      !p.time.isBefore(windowStart) && p.time.isBefore(windowEnd))
          .map((p) => p.deviation)
          .toList();

      if (samples.isEmpty) return 0.0;
      return samples.reduce((a, b) => a + b) / samples.length;
    }).toList();
  }

  /// Average deviation for today (all samples).
  double get todayAverageDeviation {
    if (_history.isEmpty) return 0.0;
    final today = DateTime.now();
    final todaySamples = _history
        .where((p) =>
    p.time.year == today.year &&
        p.time.month == today.month &&
        p.time.day == today.day)
        .map((p) => p.deviation)
        .toList();
    if (todaySamples.isEmpty) return 0.0;
    return todaySamples.reduce((a, b) => a + b) / todaySamples.length;
  }

  /// Maximum deviation recorded today.
  double get todayMaxDeviation {
    if (_history.isEmpty) return 0.0;
    final today = DateTime.now();
    final todaySamples = _history
        .where((p) =>
    p.time.year == today.year &&
        p.time.month == today.month &&
        p.time.day == today.day)
        .map((p) => p.deviation)
        .toList();
    if (todaySamples.isEmpty) return 0.0;
    return todaySamples.reduce((a, b) => a > b ? a : b);
  }

  /// True if we have any real data for today.
  bool get hasTodayData {
    final today = DateTime.now();
    return _history.any((p) =>
    p.time.year == today.year &&
        p.time.month == today.month &&
        p.time.day == today.day);
  }

  Future<void> dispose() async {
    await _angleSub?.cancel();
    _angleSub = null;
  }
}