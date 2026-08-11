import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

class AppUpdateService {
  AppUpdateService._();
  static final instance = AppUpdateService._();

  Future<void> checkForUpdate() async {
    if (kIsWeb || kDebugMode) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (_) {
      // Silently ignore — Play Store not available in dev/sideload builds
    }
  }
}