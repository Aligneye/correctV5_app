import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:correctv1/bluetooth/aligneye_device_service.dart';

class CalibrationProfileSyncService {
  CalibrationProfileSyncService._();

  static Future<void> saveProfile({
    required String profileName,
    required PostureReading reading,
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client
          .from('calibration_profiles')
          .upsert(
            {
              'user_id': user.id,
              'name': profileName,
              'profile_id': reading.calibrationProfileId,
              'quality': reading.calibrationQuality,
              'ref_x': reading.calibrationRefX,
              'ref_y': reading.calibrationRefY,
              'ref_z': reading.calibrationRefZ,
              'total_samples': reading.calibrationTotalSamples,
              'passed_samples': reading.calibrationPassedSamples,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'user_id,name',
          );
    } catch (e) {
      // Non-fatal — device holds the source of truth for calibration profiles.
      debugPrint('CalibrationProfileSyncService: saveProfile failed: $e');
    }
  }
}