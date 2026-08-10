import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IntegrityService {
  IntegrityService._();

  static const _channel = MethodChannel('com.alignpod.app/integrity');
  static const _cloudProjectNumber = 204892022204;

  static SupabaseClient get _client => Supabase.instance.client;

  /// Returns true if the device passes Play Integrity checks.
  /// On non-Android or debug builds, always returns true (skip check).
  static Future<bool> verifyDeviceIntegrity() async {
    if (kIsWeb || kDebugMode) return true;

    try {
      // 1. Get nonce from backend
      final nonceResp = await _client.functions.invoke(
        'generate-integrity-nonce',
        method: HttpMethod.post,
      );
      final nonce = nonceResp.data?['nonce'] as String?;
      if (nonce == null || nonce.isEmpty) return false;

      // 2. Request integrity token via native Android bridge
      final token = await _channel.invokeMethod<String>(
        'requestIntegrityToken',
        {
          'nonce': nonce,
          'cloudProjectNumber': _cloudProjectNumber,
        },
      );
      if (token == null || token.isEmpty) return false;

      // 3. Verify token on backend
      final verifyResp = await _client.functions.invoke(
        'verify-integrity-token',
        method: HttpMethod.post,
        body: {'token': token},
      );
      return verifyResp.data?['passed'] == true;
    } catch (e) {
      debugPrint('IntegrityService: check failed — $e');
      // Fail open: don't block legitimate users if service is unavailable
      return true;
    }
  }
}