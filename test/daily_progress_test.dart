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
