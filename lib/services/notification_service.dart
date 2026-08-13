import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Notification IDs
  static const int _idStreakReminder = 1001;
  static const int _idDailySummary = 1002;
  static const int _idInactivity = 1003;
  static const int _idSessionComplete = 1004;
  static const int _idWeeklySummary = 1005;

  // Prefs keys
  static const String _kLastSummaryDay = 'notif_last_summary_day';
  static const String _kLastInactivityDay = 'notif_last_inactivity_day';
  static const String _kLastWeeklySummaryWeek = 'notif_last_weekly_week';
  static const String _kLastSessionDay = 'notif_last_session_day';

  // Channels
  static const _chActivity = AndroidNotificationDetails(
    'activity',
    'Activity',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );
  static const _chReminder = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    icon: '@mipmap/ic_launcher',
  );

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    try {
      await _plugin.initialize(
        const InitializationSettings(android: android),
      );
    } catch (e) {
      debugPrint('NotificationService: initialize failed: $e');
    }
  }

  // ── Daily Summary ──────────────────────────────────────────────────────────
  // Call this after loading TodayStats, around 8 PM.
  // goodPct: 0–100, sessionCount: total sessions today, trackedMinutes: total
  Future<void> maybeSendDailySummary({
    required int goodPct,
    required int sessionCount,
    required int trackedMinutes,
    int hour = 20,
  }) async {
    final now = DateTime.now();
    if (now.hour < hour) return;
    if (trackedMinutes < 1) return; // no data today — skip

    final todayKey = _dayKey(now);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kLastSummaryDay) == todayKey) return;

    final title = goodPct >= 70
        ? 'Great posture day! 🌟'
        : goodPct >= 40
            ? 'Not bad today 💪'
            : 'Let\'s do better tomorrow! 💡';

    final body = goodPct >= 70
        ? '$goodPct% good posture across $sessionCount session${sessionCount != 1 ? 's' : ''}. Keep the streak alive!'
        : goodPct >= 40
            ? '$goodPct% good posture today. $sessionCount session${sessionCount != 1 ? 's' : ''} done — consistency is the key!'
            : '$goodPct% good posture today. Every session counts — come back stronger tomorrow!';

    await _show(_idDailySummary, title, body, _chActivity);
    await prefs.setString(_kLastSummaryDay, todayKey);
  }

  // ── 24hr Inactivity Reminder ───────────────────────────────────────────────
  // Call this periodically (e.g. on app open / background tick).
  // lastSessionTime: when user last used pod (null = never)
  Future<void> maybeShowInactivityReminder({
    required DateTime? lastSessionTime,
    int quietStart = 21, // 9 PM
    int quietEnd = 9,    // 9 AM
  }) async {
    final now = DateTime.now();
    // Quiet hours
    if (now.hour >= quietStart || now.hour < quietEnd) return;

    if (lastSessionTime == null) return;
    final hoursSince = now.difference(lastSessionTime).inHours;
    if (hoursSince < 24) return;

    final todayKey = _dayKey(now);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kLastInactivityDay) == todayKey) return;

    final messages = [
      "Your pod is waiting for you! Don't break the habit now.",
      "It's been over 24 hours. A short session goes a long way!",
      "Consistency is everything. Come back and use your pod today!",
      "Your posture goals are waiting. Let's get back on track!",
    ];
    final body = messages[Random().nextInt(messages.length)];

    await _show(
      _idInactivity,
      'Time to use your pod! 🎯',
      body,
      _chReminder,
    );
    await prefs.setString(_kLastInactivityDay, todayKey);
  }

  // ── Session Complete ───────────────────────────────────────────────────────
  // Call this immediately when a session finishes.
  // durationMin: session length, currentStreak: user's streak days
  Future<void> showSessionComplete({
    required int durationMin,
    required int currentStreak,
    required String sessionType, // 'training' | 'therapy' | 'tracking'
  }) async {
    final now = DateTime.now();
    final todayKey = _dayKey(now);
    final prefs = await SharedPreferences.getInstance();

    // Dedupe: only one session-complete notif per day
    if (prefs.getString(_kLastSessionDay) == todayKey) return;

    final typeLabel = sessionType == 'therapy'
        ? 'Therapy'
        : sessionType == 'training'
            ? 'Training'
            : 'Tracking';

    final streakLine = currentStreak >= 7
        ? '$currentStreak day streak! You\'re on fire! 🔥'
        : currentStreak > 1
            ? '$currentStreak day streak! Keep it up!'
            : 'Great start! Build your streak!';

    final motivations = [
      'Consistency is the key!',
      'Every session brings you closer to perfect posture.',
      'Your spine thanks you!',
      'Small steps, big results!',
    ];
    final motivation = motivations[Random().nextInt(motivations.length)];

    await _show(
      _idSessionComplete,
      '$typeLabel session complete! ✅',
      '$durationMin min done. $streakLine $motivation',
      _chActivity,
    );
    await prefs.setString(_kLastSessionDay, todayKey);
  }

  // ── Weekly Summary ─────────────────────────────────────────────────────────
  // Call this on Sunday after loading weekly stats.
  // totalSessions: this week, avgGoodPct: 0–100
  Future<void> maybeSendWeeklySummary({
    required int totalSessions,
    required int avgGoodPct,
  }) async {
    final now = DateTime.now();
    if (now.weekday != DateTime.sunday) return;
    if (totalSessions == 0) return;

    final weekKey = _weekKey(now);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kLastWeeklySummaryWeek) == weekKey) return;

    final title = avgGoodPct >= 70
        ? 'Excellent week! 🏆'
        : avgGoodPct >= 40
            ? 'Solid week! 💪'
            : 'Keep pushing this week! 🌱';

    final body = avgGoodPct >= 70
        ? '$totalSessions sessions this week, $avgGoodPct% good posture. You\'re building a great habit!'
        : avgGoodPct >= 40
            ? '$totalSessions sessions this week, $avgGoodPct% good posture. You\'re making progress — keep going!'
            : '$totalSessions sessions this week. Every session counts — aim for more next week!';

    await _show(_idWeeklySummary, title, body, _chActivity);
    await prefs.setString(_kLastWeeklySummaryWeek, weekKey);
  }

  // ── Streak Reminder (existing) ─────────────────────────────────────────────
  String? _lastStreakNotifiedDay;

  Future<void> updateStreakReminderForToday(bool todayActive) async {
    if (todayActive) {
      await _plugin.cancel(_idStreakReminder);
    } else {
      await _maybeShowStreakReminder();
    }
  }

  Future<void> _maybeShowStreakReminder({int hour = 20}) async {
    final now = DateTime.now();
    if (now.hour < hour) return;
    final todayKey = _dayKey(now);
    if (_lastStreakNotifiedDay == todayKey) return;

    await _show(
      _idStreakReminder,
      'Streak at risk! 🔥',
      "You haven't done today's session yet. Do a quick session to keep your streak alive!",
      _chReminder,
    );
    _lastStreakNotifiedDay = todayKey;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _show(
    int id,
    String title,
    String body,
    AndroidNotificationDetails androidDetails,
  ) async {
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('NotificationService: show($id) failed: $e');
    }
  }

  String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _weekKey(DateTime dt) {
    final monday = dt.subtract(Duration(days: dt.weekday - 1));
    return _dayKey(monday);
  }
}