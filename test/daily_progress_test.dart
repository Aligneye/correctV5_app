import 'package:correctv1/analytics/analytics_insights.dart';
import 'package:correctv1/analytics/analytics_screen.dart';
import 'package:correctv1/services/live_session_recorder.dart';
import 'package:correctv1/services/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

TodayStats _stats({
  int todayPct = 80,
  int todaySec = 3600,
  int todaySlouch = 10,
  int yPct = 64,
  int ySec = 7200,
  int ySlouch = 40,
}) =>
    TodayStats(
      todayPct: todayPct,
      todayPostureDurationSec: todaySec,
      todayTherapyDurationSec: 0,
      todaySessionCount: 1,
      todayTrackedSec: todaySec,
      yesterdayPct: yPct,
      yesterdayHasPostureData: ySec > 0,
      yesterdayPostureDurationSec: ySec,
      yesterdayTherapyDurationSec: 0,
      yesterdaySessionCount: 1,
      yesterdayTrackedSec: ySec,
      yesterdayHasTrackedData: ySec > 0,
      todaySlouchCount: todaySlouch,
      yesterdaySlouchCount: ySlouch,
    );

void main() {
  slouchRuleTests();
  analyticsInsightTests();

  test('slouch change is per hour, not raw count', () {
    // today 10/h, yesterday 40 in 2h = 20/h → 50% fewer
    expect(_stats().slouchChangePct, closeTo(-50, 0.001));
  });

  test('score change is relative %', () {
    // 64 → 80 = +25%
    expect(_stats().scoreChangePct, closeTo(25, 0.001));
  });

  test('no yesterday data → null', () {
    final s = _stats(ySec: 0, ySlouch: 0);
    expect(s.slouchChangePct, isNull);
    expect(s.scoreChangePct, isNull);
  });

  test('zero slouches yesterday → null (no divide by zero)', () {
    expect(_stats(ySlouch: 0).slouchChangePct, isNull);
  });
}

void slouchRuleTests() {
  const delay = Duration(seconds: 5);
  bool counts(String mode, int sec, {double angle = 30}) =>
      LiveSessionRecorder.slouchCounts(
          angle: angle,
          subMode: mode,
          badFor: Duration(seconds: sec),
          alertDelay: delay);

  test('INSTANT and NO_ALERTS count immediately', () {
    expect(counts('INSTANT', 0), isTrue);
    expect(counts('NO_ALERTS', 0), isTrue);
  });

  test('DELAYED counts only after the alert delay', () {
    expect(counts('DELAYED', 4), isFalse);
    expect(counts('DELAYED', 5), isTrue);
  });

  test('leaning back (negative angle) never counts', () {
    expect(counts('INSTANT', 0, angle: -30), isFalse);
    expect(counts('NO_ALERTS', 0, angle: -30), isFalse);
    expect(counts('DELAYED', 10, angle: -30), isFalse);
  });
}

void analyticsInsightTests() {
  DailyProgress day(int i, {int sec = 3600, int wrong = 720, int slouch = 6}) =>
      DailyProgress(
        date: DateTime(2026, 9, i),
        score: sec == 0 ? 0 : (100 - wrong / sec * 100).round(),
        slouchCount: slouch,
        postureSec: sec,
        wrongDurSec: wrong,
      );

  test('period summary is time-weighted and counts target days', () {
    final s = PeriodSummary.of(
      [day(1), day(2, sec: 0, wrong: 0, slouch: 0), day(3, wrong: 2160)],
      70,
    );
    expect(s.score, 60); // 2880 bad of 7200
    expect(s.activeDays, 2);
    expect(s.targetDays, 1); // 80% yes, 40% no
    expect(s.slouchPerHour, closeTo(6, 0.001));
    expect(s.slouchPerDay, closeTo(6, 0.001)); // 12 slouches / 2 worn days
  });

  test('slouches bucket by local hour; peak is busiest 2-hour window', () {
    final session = SessionData(
      id: 0,
      type: SessionType.posture,
      name: '',
      time: '',
      date: '',
      duration: '',
      durationSec: 7200,
      startTs: DateTime(2026, 9, 1, 14, 30),
      postureEvents: const [
        PostureEvent(slouchSec: 0, correctionSec: 10), // 14:30
        PostureEvent(slouchSec: 1800, correctionSec: 1806), // 15:00
        PostureEvent(slouchSec: 2400, correctionSec: 0xFFFF), // 15:10
      ],
    );
    final ins = SlouchInsights.of([session]);
    expect(ins.byHour[14], 1);
    expect(ins.byHour[15], 2);
    expect(ins.total, 3);
    expect(ins.peakStartHour, 14);
    expect(ins.avgCorrectionSec, closeTo(8, 0.001)); // (10 + 6) / 2
  });

  test('no events → no peak, no correction avg', () {
    final ins = SlouchInsights.of(const []);
    expect(ins.peakStartHour, isNull);
    expect(ins.avgCorrectionSec, isNull);
  });
}
