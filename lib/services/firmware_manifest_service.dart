import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class FirmwareManifest {
  final String deviceModel;
  final String hardwareRevision;
  final String firmwareVersion;
  final String appVersion;
  final bool mandatory;
  final String firmwareUrl;
  final String sha256;
  final List<String> releaseNotes;
  final String? githubTag;
  final String? githubReleaseUrl;

  const FirmwareManifest({
    required this.deviceModel,
    required this.hardwareRevision,
    required this.firmwareVersion,
    required this.appVersion,
    required this.mandatory,
    required this.firmwareUrl,
    required this.sha256,
    required this.releaseNotes,
    this.githubTag,
    this.githubReleaseUrl,
  });

  factory FirmwareManifest.fromJson(Map<String, dynamic> json) {
    return FirmwareManifest(
      deviceModel: json['device_model']?.toString() ?? '',
      hardwareRevision: json['hardware_revision']?.toString() ?? '',
      firmwareVersion: json['firmware_version']?.toString() ?? '',
      appVersion: json['app_version']?.toString() ?? '1.0.0',
      mandatory: json['mandatory'] == true,
      firmwareUrl: json['firmware_url']?.toString() ?? '',
      sha256: json['sha256']?.toString() ?? '',
      releaseNotes: (json['release_notes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      githubTag: json['github_tag']?.toString(),
      githubReleaseUrl: json['github_release_url']?.toString(),
    );
  }
}

class FirmwareManifestService {
  static const String _manifestUrl = String.fromEnvironment(
    'FIRMWARE_MANIFEST_URL',
    defaultValue: 'https://cdn.aligneye.com/firmware/manifest.json',
  );

  Future<FirmwareManifest?> fetchLatestForDeviceFromSupabase({
    required String deviceModel,
    required String hardwareRevision,
  }) async {
    try {
      final rows = await Supabase.instance.client
          .from('firmware_releases')
          .select()
          .eq('Active', true)
          .order('created_at', ascending: false)
          .limit(20);

      for (final row in rows) {
        final manifest = FirmwareManifest.fromJson(row);
        final modelMatches =
            manifest.deviceModel.isEmpty || manifest.deviceModel == deviceModel;
        final hardwareMatches =
            manifest.hardwareRevision.isEmpty ||
            manifest.hardwareRevision == hardwareRevision;
        if (modelMatches && hardwareMatches) {
          return manifest;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Supabase device manifest fetch error: $e');
      return null;
    }
  }

  Future<FirmwareManifest?> fetchManifest() async {
    // 1. Try Supabase first
    try {
      final rows = await Supabase.instance.client
          .from('firmware_releases')
          .select()
          .eq('Active', true)
          .order('created_at', ascending: false)
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