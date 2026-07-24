import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _lastStreakNotifiedDay;

  static const int _streakReminderId = 1001;
  static const String _channelId = 'streak_reminder';
  static const String _channelName = 'Streak Reminders';

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    try {
      await _plugin.initialize(settings);
    } catch (e) {
      debugPrint('NotificationService: initialize failed: $e');
    }
  }

  Future<void> scheduleDailyStreakReminder({
    int hour = 20,
    int minute = 0,
  }) async {
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // Fire at most once per calendar day
    if (_lastStreakNotifiedDay == todayKey) return;

    // Only show after the scheduled hour
    if (today.hour < hour || (today.hour == hour && today.minute < minute)) {
      return;
    }

    try {
      await _plugin.cancel(_streakReminderId);

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      const details = NotificationDetails(android: androidDetails);

      await _plugin.show(
        _streakReminderId,
        'Streak Alert! 🔥',
        "You haven't done today's session yet. Your streak is at risk — do a quick session now!",
        details,
      );

      _lastStreakNotifiedDay = todayKey;
    } catch (e) {
      debugPrint('NotificationService: scheduleDailyStreakReminder failed: $e');
    }
  }

  Future<void> cancelStreakReminder() async {
    try {
      await _plugin.cancel(_streakReminderId);
    } catch (e) {
      debugPrint('NotificationService: cancelStreakReminder failed: $e');
    }
  }

  Future<void> updateStreakReminderForToday(bool todayActive) async {
    if (todayActive) {
      await cancelStreakReminder();
    } else {
      await scheduleDailyStreakReminder();
    }
  }
}
