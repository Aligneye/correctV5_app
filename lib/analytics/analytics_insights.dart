import 'package:correctv1/analytics/analytics_screen.dart';
import 'package:correctv1/services/session_repository.dart';

/// Totals for one period (e.g. last 7 days) built from per-day progress.
class PeriodSummary {
  const PeriodSummary({
    required this.score,
    required this.slouchPerHour,
    required this.slouchPerDay,
    required this.postureSec,
    required this.activeDays,
    required this.targetDays,
    required this.days,
  });

  /// Time-weighted posture score; null when nothing was worn.
  final int? score;
  final double? slouchPerHour;

  /// Average slouches per day the pod was worn.
  final double? slouchPerDay;
  final int postureSec;
  final int activeDays;
  final int targetDays;
  final int days;

  bool get hasData => postureSec > 0;

  factory PeriodSummary.of(List<DailyProgress> days, int target) {
    var posture = 0, wrong = 0, slouches = 0, active = 0, hit = 0;
    for (final d in days) {
      if (!d.hasData) continue;
      active++;
      posture += d.postureSec;
      wrong += d.wrongDurSec;
      slouches += d.slouchCount;
      if (d.score >= target) hit++;
    }
    return PeriodSummary(
      score: posture > 0
          ? (100 - wrong / posture * 100).round().clamp(0, 100)
          : null,
      slouchPerHour: posture > 0 ? slouches / (posture / 3600) : null,
      slouchPerDay: active > 0 ? slouches / active : null,
      postureSec: posture,
      activeDays: active,
      targetDays: hit,
      days: days.length,
    );
  }
}

/// When during the day slouches happen, plus how fast they get corrected.
class SlouchInsights {
  const SlouchInsights({
    required this.byHour,
    required this.avgCorrectionSec,
  });

  /// 24 buckets, index = local hour of day.
  final List<int> byHour;
  final double? avgCorrectionSec;

  int get total => byHour.fold(0, (a, b) => a + b);

  /// Start hour of the busiest 2-hour window, or null with no slouches.
  int? get peakStartHour {
    if (total == 0) return null;
    var best = 0, bestSum = -1;
    for (var h = 0; h < 24; h++) {
      final sum = byHour[h] + byHour[(h + 1) % 24];
      if (sum > bestSum) {
        bestSum = sum;
        best = h;
      }
    }
    return best;
  }

  /// Only sessions with exact events count; others are skipped, not guessed.
  factory SlouchInsights.of(List<SessionData> sessions) {
    final byHour = List<int>.filled(24, 0);
    var corrected = 0, correctionTotal = 0;
    for (final s in sessions) {
      final start = s.startTs;
      final events = s.postureEvents;
      if (s.type != SessionType.posture || start == null || events == null) {
        continue;
      }
      for (final e in events) {
        byHour[start.add(Duration(seconds: e.slouchSec)).hour]++;
        if (e.wasCorrected) {
          corrected++;
          correctionTotal += e.durationSec;
        }
      }
    }
    return SlouchInsights(
      byHour: byHour,
      avgCorrectionSec: corrected > 0 ? correctionTotal / corrected : null,
    );
  }
}

/// "3 PM", "12 AM".
String formatHour(int h) {
  final hour = h % 24;
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12 ${hour < 12 ? 'AM' : 'PM'}';
}
