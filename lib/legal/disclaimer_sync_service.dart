import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:correctv1/legal/disclaimer_content.dart';
import 'package:correctv1/legal/disclaimer_prefs.dart';

class DisclaimerSyncService {
  DisclaimerSyncService._();

  static Future<void> syncIfNeeded() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final accepted = await DisclaimerPrefs.hasAcceptedCurrentVersion();
      if (!accepted) return;

      await Supabase.instance.client
          .from('user_disclaimer_acceptances')
          .upsert(
            {
              'user_id': user.id,
              'disclaimer_version': disclaimerVersion,
              'accepted_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'user_id,disclaimer_version',
          );
    } catch (_) {
      // Non-fatal — local storage is source of truth for gating UI.
    }
  }
}
