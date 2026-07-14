import 'package:shared_preferences/shared_preferences.dart';
import 'package:correctv1/legal/disclaimer_content.dart';

class DisclaimerPrefs {
  DisclaimerPrefs._();

  static const _key = 'disclaimer_accepted_version';

  static Future<bool> hasAcceptedCurrentVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) == disclaimerVersion;
  }

  static Future<void> markAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, disclaimerVersion);
  }
}
