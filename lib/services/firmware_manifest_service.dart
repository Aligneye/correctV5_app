import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class FirmwareManifest {
  final String deviceModel;
  final String hardwareRevision;
  final String latestVersion;
  final int buildNumber;
  final String minSupportedAppVersion;
  final int minBatteryPercent;
  final bool mandatory;
  final String firmwareUrl;
  final String sha256;
  final int fileSizeBytes;
  final List<String> releaseNotes;

  const FirmwareManifest({
    required this.deviceModel,
    required this.hardwareRevision,
    required this.latestVersion,
    required this.buildNumber,
    required this.minSupportedAppVersion,
    required this.minBatteryPercent,
    required this.mandatory,
    required this.firmwareUrl,
    required this.sha256,
    required this.fileSizeBytes,
    required this.releaseNotes,
  });

  factory FirmwareManifest.fromJson(Map<String, dynamic> json) {
    return FirmwareManifest(
      deviceModel: json['device_model']?.toString() ?? '',
      hardwareRevision: json['hardware_revision']?.toString() ?? '',
      latestVersion: json['latest_version']?.toString() ?? '',
      buildNumber: (json['build_number'] as num?)?.toInt() ?? 0,
      minSupportedAppVersion:
          json['min_supported_app_version']?.toString() ?? '1.0.0',
      minBatteryPercent: (json['min_battery_percent'] as num?)?.toInt() ?? 40,
      mandatory: json['mandatory'] == true,
      firmwareUrl: json['firmware_url']?.toString() ?? '',
      sha256: json['sha256']?.toString() ?? '',
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
      releaseNotes: (json['release_notes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

class FirmwareManifestService {
  // Replace with production CDN/Supabase URL when backend is ready.
  static const String _manifestUrl = String.fromEnvironment(
    'FIRMWARE_MANIFEST_URL',
    defaultValue: 'https://cdn.aligneye.com/firmware/manifest.json',
  );

  Future<FirmwareManifest?> fetchManifest() async {
    // 1. Try Supabase first
    try {
      final rows = await Supabase.instance.client
          .from('firmware_releases')
          .select()
          .eq('active', true)
          .order('build_number', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        return FirmwareManifest.fromJson(rows.first);
      }
    } catch (e) {
      debugPrint('Supabase manifest fetch error (falling back to CDN): $e');
    }

    // 2. Fall back to CDN
    try {
      final response = await http
          .get(Uri.parse(_manifestUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint('CDN manifest fetch failed: ${response.statusCode}');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return FirmwareManifest.fromJson(json);
    } catch (e) {
      debugPrint('CDN manifest fetch error: $e');
      return null;
    }
  }

  /// Returns true when serverVersion is strictly newer than deviceVersion.
  /// Compares semver-style: "1.0.1" > "1.0.0".
  static bool isNewerVersion(String serverVersion, String deviceVersion) {
    final server = _parseSemver(serverVersion);
    final device = _parseSemver(deviceVersion);
    for (int i = 0; i < 3; i++) {
      if (server[i] > device[i]) return true;
      if (server[i] < device[i]) return false;
    }
    return false;
  }

  static List<int> _parseSemver(String version) {
    final clean = version.replaceAll(RegExp(r'[^0-9.]'), '');
    final parts = clean.split('.');
    return List.generate(
      3,
      (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0,
    );
  }
}
