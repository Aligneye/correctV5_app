import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _kNotificationChannelId = 'aligneye_bg';
const _kNotificationId = 888;

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    _kNotificationChannelId,
    'AlignEye Tracking',
    description: 'Posture and therapy background tracking',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBgStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _kNotificationChannelId,
      initialNotificationTitle: 'AlignEye',
      initialNotificationContent: 'Tracking your posture...',
      foregroundServiceNotificationId: _kNotificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBgStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onBgStart(ServiceInstance service) async {

  final FlutterLocalNotificationsPlugin notifications =
  FlutterLocalNotificationsPlugin();

  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  // UI se data receive karo
  service.on('posture_update').listen((data) async {
    if (data == null) return;
    final isBad = data['is_bad_posture'] as bool? ?? false;
    final mode = data['mode'] as String? ?? '';

    // Notification update karo
    String content = 'Tracking your posture...';
    if (mode.toUpperCase() == 'THERAPY') {
      final remaining = data['therapy_remaining'] as int? ?? 0;
      final mins = remaining ~/ 60;
      final secs = remaining % 60;
      content = 'Therapy: ${mins}m ${secs}s remaining';
    } else if (isBad) {
      content = '⚠️ Bad posture detected!';
    } else {
      content = '✅ Good posture';
    }

    // Foreground notification update
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'AlignEye',
        content: content,
      );
    }

    // Bad posture alert notification
    if (isBad) {
      await notifications.show(
        _kNotificationId + 1,
        'AlignEye Alert',
        '⚠️ Bad posture detected! Please correct your posture.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kNotificationChannelId,
            'AlignEye Tracking',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    }
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}