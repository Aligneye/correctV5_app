import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/services/firmware_download_service.dart';
import 'package:correctv1/services/firmware_manifest_service.dart';

enum FirmwareUpdateState {
  idle,
  checking,    // GET_INFO + manifest fetch
  downloading, // ZIP download in background
  ready,       // downloaded + verified, waiting for user tap
  noUpdate,
  error,
}

class FirmwareUpdateService {
  FirmwareUpdateService._();
  static final FirmwareUpdateService instance = FirmwareUpdateService._();

  final _state = ValueNotifier<FirmwareUpdateState>(FirmwareUpdateState.idle);
  ValueNotifier<FirmwareUpdateState> get state => _state;

  final _downloadProgress = ValueNotifier<double>(0);
  ValueNotifier<double> get downloadProgress => _downloadProgress;

  FirmwareManifest? _manifest;
  FirmwareManifest? get manifest => _manifest;

  DeviceInfo? _deviceInfo;
  DeviceInfo? get deviceInfo => _deviceInfo;

  String? _localZipPath;
  String? get localZipPath => _localZipPath;

  final _manifestService = FirmwareManifestService();
  final _downloadService = FirmwareDownloadService();

  bool _running = false;

  /// Call this every time device connects. Silently checks + downloads.
  Future<void> onDeviceConnected(AlignEyeDeviceService deviceService) async {
    if (_running) return;
    // Already have a ready update — don't re-check
    if (_state.value == FirmwareUpdateState.ready) return;

    _running = true;
    _state.value = FirmwareUpdateState.checking;

    try {
      // Step 1: GET_INFO from device
      final info = await deviceService.getDeviceInfo();
      _deviceInfo = info;

      debugPrint('FirmwareUpdateService: device fw = ${info?.firmwareVersion}');

      // Step 2: Fetch manifest from server
      final manifest = await _manifestService.fetchManifest();
      if (manifest == null) {
        debugPrint('FirmwareUpdateService: manifest null → noUpdate');
        _state.value = FirmwareUpdateState.noUpdate;
        return;
      }
      _manifest = manifest;

      debugPrint('FirmwareUpdateService: server version = ${manifest.latestVersion}');

      // Step 3: Version compare
      final deviceFw = info?.firmwareVersion ?? '';
      final hasUpdate = deviceFw.isEmpty ||
          FirmwareManifestService.isNewerVersion(
              manifest.latestVersion, deviceFw);

      debugPrint('FirmwareUpdateService: hasUpdate = $hasUpdate');

      if (!hasUpdate) {
        _state.value = FirmwareUpdateState.noUpdate;
        return;
      }

      // Step 4: Silent background download
      _state.value = FirmwareUpdateState.downloading;
      _downloadProgress.value = 0;

      final zipPath = await _downloadService.download(
        manifest.firmwareUrl,
        onProgress: (p) => _downloadProgress.value = p,
      );

      debugPrint('FirmwareUpdateService: downloaded to $zipPath');

      // Step 5: SHA256 verify
      await _downloadService.verifySha256(zipPath, manifest.sha256);
      _localZipPath = zipPath;

      debugPrint('FirmwareUpdateService: state → ready, showing popup');

      // Step 6: Notify UI — update is ready to install
      _state.value = FirmwareUpdateState.ready;
    } catch (e) {
      debugPrint('FirmwareUpdateService bg check error: $e');
      _state.value = FirmwareUpdateState.error;
    } finally {
      _running = false;
    }
  }

  /// Reset so next connection triggers a fresh check.
  void reset() {
    _running = false;
    _state.value = FirmwareUpdateState.idle;
    _downloadProgress.value = 0;
    _manifest = null;
    _deviceInfo = null;
    _localZipPath = null;
  }
}