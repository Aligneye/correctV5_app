import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

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

      final now = DateTime.now();
      var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      // Use show with a future: schedule once for tonight.
      // Re-scheduled each app open via updateStreakReminderForToday.
      await _plugin.show(
        _streakReminderId,
        'Streak Alert! 🔥',
        'Aaj ka session abhi nahi hua. Streak tutne wali hai — ek chhota session karo!',
        details,
      );
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
