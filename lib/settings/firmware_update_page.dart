import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/bluetooth/bluetooth_service_manager.dart';
import 'package:correctv1/services/dfu_update_service.dart';
import 'package:correctv1/services/firmware_download_service.dart';
import 'package:correctv1/services/firmware_manifest_service.dart';
import 'package:correctv1/theme/app_theme.dart';

// ── Update state machine ────────────────────────────────────────────────────

enum _UpdateStep {
  idle,           // waiting for user to open screen
  readingDevice,  // sending GET_INFO over BLE
  checkingServer, // fetching manifest
  upToDate,       // nothing to install
  updateAvailable,// newer version ready
  preflightFailed,// battery / device mismatch / no internet
  downloading,    // downloading ZIP
  verifying,      // SHA256 check
  enteringDfu,    // waiting for ENTER_DFU ack + 5 s reboot
  transferring,   // Nordic DFU in progress
  reconnecting,   // waiting for device to come back
  success,        // done
  failed,         // unrecoverable (with retry option)
}

// ── Page ────────────────────────────────────────────────────────────────────

class FirmwareUpdatePage extends StatefulWidget {
  const FirmwareUpdatePage({super.key});

  @override
  State<FirmwareUpdatePage> createState() => _FirmwareUpdatePageState();
}

class _FirmwareUpdatePageState extends State<FirmwareUpdatePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryController;

  _UpdateStep _step = _UpdateStep.idle;
  String _errorMessage = '';
  double _downloadProgress = 0;
  int _dfuPercent = 0;

  DeviceInfo? _deviceInfo;
  FirmwareManifest? _manifest;

  final _manifestService = FirmwareManifestService();
  final _downloadService = FirmwareDownloadService();
  final _dfuService = DfuUpdateService();

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _runCheckFlow();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  // ── Main flow ─────────────────────────────────────────────────────────────

  Future<void> _runCheckFlow() async {
    _set(_UpdateStep.readingDevice);

    // 1. Read device info via BLE
    final deviceService = BluetoothServiceManager().deviceService;
    final info = await deviceService.getDeviceInfo();

    if (!mounted) return;

    if (info == null) {
      // Device not connected or GET_INFO timed out — fall back to reading
      // battery from the live telemetry stream so the battery card still works.
      _deviceInfo = null;
    } else {
      _deviceInfo = info;
    }

    // 2. Fetch manifest
    _set(_UpdateStep.checkingServer);
    final manifest = await _manifestService.fetchManifest();

    if (!mounted) return;

    if (manifest == null) {
      _fail('Could not reach the update server. Check your internet connection and try again.');
      return;
    }
    _manifest = manifest;

    // 3. Compare versions
    final deviceFw = _deviceInfo?.firmwareVersion ?? '';
    final hasUpdate = deviceFw.isEmpty ||
        FirmwareManifestService.isNewerVersion(manifest.latestVersion, deviceFw);

    if (!hasUpdate) {
      _set(_UpdateStep.upToDate);
      return;
    }

    _set(_UpdateStep.updateAvailable);
  }

  Future<void> _startUpdate() async {
    final manifest = _manifest;
    if (manifest == null) return;

    HapticFeedback.mediumImpact();

    // Pre-flight: battery check
    final battery = _deviceInfo?.batteryPercent ??
        (BluetoothServiceManager()
                .deviceService
                .currentReading
                .value
                ?.batteryPercentage ??
            0);

    if (battery > 0 && battery < manifest.minBatteryPercent) {
      _prefail(
        'Battery is at $battery%. Charge to at least ${manifest.minBatteryPercent}% before updating.',
      );
      return;
    }

    // Pre-flight: device model match
    if (_deviceInfo != null &&
        manifest.deviceModel.isNotEmpty &&
        _deviceInfo!.model.isNotEmpty &&
        _deviceInfo!.model != manifest.deviceModel) {
      _prefail(
        'This update is for ${manifest.deviceModel} but your device is ${_deviceInfo!.model}.',
      );
      return;
    }

    // Download
    _set(_UpdateStep.downloading);
    setState(() {
      _downloadProgress = 0;
    });

    String zipPath;
    try {
      zipPath = await _downloadService.download(
        manifest.firmwareUrl,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
    } catch (e) {
      _fail('Download failed: $e');
      return;
    }

    // SHA256 verify
    _set(_UpdateStep.verifying);
    try {
      await _downloadService.verifySha256(zipPath, manifest.sha256);
    } catch (e) {
      _fail('Firmware verification failed. Please try again.');
      return;
    }
    // ENTER_DFU
    _set(_UpdateStep.enteringDfu);
    final deviceService = BluetoothServiceManager().deviceService;

    if (deviceService.connectionStatus.value ==
        DeviceConnectionStatus.connected) {
      final result = await deviceService.sendEnterDfu();
      if (!mounted) return;

      switch (result) {
        case EnterDfuResult.lowBattery:
          _prefail('Device reported low battery. Charge and try again.');
          return;
        case EnterDfuResult.sessionActive:
          _prefail('Stop your active session before updating firmware.');
          return;
        case EnterDfuResult.timeout:
          // Device may have already rebooted into DFU — continue anyway.
          break;
        case EnterDfuResult.error:
          _fail('Device refused the update command. Try reconnecting.');
          return;
        case EnterDfuResult.success:
          break;
      }
    }

    // Wait for device to reboot into bootloader
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!mounted) return;

    // DFU transfer
    _set(_UpdateStep.transferring);
    setState(() => _dfuPercent = 0);

    final deviceAddress = deviceService.device?.remoteId.str ?? '';
    if (deviceAddress.isEmpty) {
      _fail('Device address not available. Reconnect and try again.');
      return;
    }

    _dfuService.startDfu(
      deviceAddress: deviceAddress,
      firmwareZipPath: zipPath,
      onProgress: (p) {
        if (mounted) setState(() => _dfuPercent = p);
      },
      onCompleted: () async {
        if (!mounted) return;
        _set(_UpdateStep.reconnecting);
        // Give device time to boot normal firmware
        await Future<void>.delayed(const Duration(seconds: 4));
        if (!mounted) return;
        _set(_UpdateStep.success);
        HapticFeedback.heavyImpact();
      },
      onError: (msg) {
        if (mounted) _fail('DFU transfer failed: $msg');
      },
    );
  }

  // ── State helpers ─────────────────────────────────────────────────────────

  void _set(_UpdateStep step) {
    if (mounted) setState(() => _step = step);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _step = _UpdateStep.failed;
      _errorMessage = message;
    });
  }

  void _prefail(String message) {
    if (!mounted) return;
    setState(() {
      _step = _UpdateStep.preflightFailed;
      _errorMessage = message;
    });
  }

  void _retry() {
    setState(() {
      _step = _UpdateStep.idle;
      _errorMessage = '';
      _downloadProgress = 0;
      _dfuPercent = 0;
    });
    _runCheckFlow();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.pageBackgroundGradientFor(context),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppTheme.textPrimary,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Firmware Update',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FadeSlide(
                        controller: _entryController,
                        delay: 0,
                        child: _DeviceInfoCard(info: _deviceInfo),
                      ),
                      const SizedBox(height: 18),
                      _FadeSlide(
                        controller: _entryController,
                        delay: 0.1,
                        child: _StatusCard(
                          step: _step,
                          manifest: _manifest,
                          deviceInfo: _deviceInfo,
                          downloadProgress: _downloadProgress,
                          dfuPercent: _dfuPercent,
                          errorMessage: _errorMessage,
                          onRetry: _retry,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _FadeSlide(
                        controller: _entryController,
                        delay: 0.2,
                        child: _BatteryCard(
                          deviceInfo: _deviceInfo,
                          minBattery: _manifest?.minBatteryPercent ?? 40,
                        ),
                      ),
                      if (_step == _UpdateStep.updateAvailable) ...[
                        const SizedBox(height: 28),
                        _FadeSlide(
                          controller: _entryController,
                          delay: 0.3,
                          child: _InstallButton(onTap: _startUpdate),
                        ),
                      ],
                      if (_step == _UpdateStep.failed ||
                          _step == _UpdateStep.preflightFailed) ...[
                        const SizedBox(height: 28),
                        _FadeSlide(
                          controller: _entryController,
                          delay: 0.3,
                          child: _RetryButton(onTap: _retry),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Device Info Card ─────────────────────────────────────────────────────────

class _DeviceInfoCard extends StatelessWidget {
  final DeviceInfo? info;
  const _DeviceInfoCard({required this.info});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: const Icon(Icons.memory_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info?.model.isNotEmpty == true ? info!.model : 'AlignEye Pod',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  info != null
                      ? 'HW: ${info!.hardwareRevision}  ·  FW: ${info!.firmwareVersion}'
                      : 'Reading device…',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (info != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.connectedBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                info!.firmwareVersion,
                style: const TextStyle(
                  color: AppTheme.connectedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Status Card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final _UpdateStep step;
  final FirmwareManifest? manifest;
  final DeviceInfo? deviceInfo;
  final double downloadProgress;
  final int dfuPercent;
  final String errorMessage;
  final VoidCallback onRetry;

  const _StatusCard({
    required this.step,
    required this.manifest,
    required this.deviceInfo,
    required this.downloadProgress,
    required this.dfuPercent,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Update Status',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _body(context),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (step) {
      case _UpdateStep.idle:
      case _UpdateStep.readingDevice:
        return _Spinner(label: 'Reading device info…');
      case _UpdateStep.checkingServer:
        return _Spinner(label: 'Checking for updates…');
      case _UpdateStep.upToDate:
        return _UpToDate(
          version: deviceInfo?.firmwareVersion ?? manifest?.latestVersion ?? '',
          onRetry: onRetry,
        );
      case _UpdateStep.updateAvailable:
        return _UpdateAvailable(manifest: manifest!);
      case _UpdateStep.preflightFailed:
        return _ErrorRow(
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFF59E0B),
          bg: const Color(0xFFFFFBEB),
          message: errorMessage,
        );
      case _UpdateStep.downloading:
        return _ProgressRow(
          label: 'Downloading firmware…',
          progress: downloadProgress,
          subtitle:
              '${(downloadProgress * 100).round()}%  ·  Keep app open',
        );
      case _UpdateStep.verifying:
        return _Spinner(label: 'Verifying firmware integrity…');
      case _UpdateStep.enteringDfu:
        return _Spinner(label: 'Preparing device for update…\nDo not close the app.');
      case _UpdateStep.transferring:
        return _ProgressRow(
          label: 'Installing update… $dfuPercent%',
          progress: dfuPercent / 100,
          subtitle: 'Keep Align Pod near your phone.',
        );
      case _UpdateStep.reconnecting:
        return _Spinner(label: 'Reconnecting to device…');
      case _UpdateStep.success:
        return _SuccessRow(
          version: manifest?.latestVersion ?? '',
        );
      case _UpdateStep.failed:
        return _ErrorRow(
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFEF4444),
          bg: const Color(0xFFFEF2F2),
          message: errorMessage,
        );
    }
  }
}

class _Spinner extends StatelessWidget {
  final String label;
  const _Spinner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.brandPrimary),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final double progress;
  final String subtitle;
  const _ProgressRow({
    required this.label,
    required this.progress,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppTheme.brandPrimary),
                backgroundColor:
                    AppTheme.brandPrimary.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppTheme.brandPrimary.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.brandPrimary),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _UpToDate extends StatelessWidget {
  final String version;
  final VoidCallback onRetry;
  const _UpToDate({required this.version, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.successBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.successText,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "You're up to date",
                    style: TextStyle(
                      color: AppTheme.successText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (version.isNotEmpty)
                    Text(
                      'Running $version',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: onRetry,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded,
                  size: 15, color: AppTheme.brandPrimary),
              const SizedBox(width: 6),
              Text(
                'Check again',
                style: TextStyle(
                  color: AppTheme.brandPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpdateAvailable extends StatelessWidget {
  final FirmwareManifest manifest;
  const _UpdateAvailable({required this.manifest});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.system_update_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Update Available',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          manifest.latestVersion,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'New firmware improvements are ready to install.',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (manifest.releaseNotes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "What's new",
                  style: TextStyle(
                    color: AppTheme.connectedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                ...manifest.releaseNotes.map((note) => _BulletItem(text: note)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SuccessRow extends StatelessWidget {
  final String version;
  const _SuccessRow({required this.version});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.successBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.successText,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update complete!',
                style: TextStyle(
                  color: AppTheme.successText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (version.isNotEmpty)
                Text(
                  'Your device is now running $version.',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String message;

  const _ErrorRow({
    required this.icon,
    required this.color,
    required this.bg,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Battery Card ─────────────────────────────────────────────────────────────

class _BatteryCard extends StatelessWidget {
  final DeviceInfo? deviceInfo;
  final int minBattery;
  const _BatteryCard({required this.deviceInfo, required this.minBattery});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PostureReading?>(
      valueListenable:
          BluetoothServiceManager().deviceService.currentReading,
      builder: (context, reading, _) {
        // Prefer live GET_INFO battery; fallback to telemetry stream.
        final battery =
            deviceInfo?.batteryPercent ?? reading?.batteryPercentage ?? 0;
        final isConnected = battery > 0;
        final isEnough = battery >= minBattery;

        final Color statusColor;
        final Color statusBg;
        if (!isConnected) {
          statusColor = AppTheme.textMuted;
          statusBg = const Color(0xFFF3F4F6);
        } else if (isEnough) {
          statusColor = AppTheme.successText;
          statusBg = AppTheme.successBg;
        } else {
          statusColor = const Color(0xFFF59E0B);
          statusBg = const Color(0xFFFFFBEB);
        }

        return _Card(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  isConnected
                      ? (isEnough
                          ? Icons.battery_charging_full_rounded
                          : Icons.battery_3_bar_rounded)
                      : Icons.battery_unknown_rounded,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Battery Requirement',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isConnected
                          ? (isEnough
                              ? 'Battery sufficient for update ($battery%)'
                              : 'Charge to $minBattery%+ before updating (now $battery%)')
                          : 'Connect device to check battery level',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isConnected) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$battery%',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Buttons ────────────────────────────────────────────────────────────────

class _InstallButton extends StatelessWidget {
  final VoidCallback onTap;
  const _InstallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _ActionButton(
      label: 'Install Update',
      gradient: AppTheme.brandGradient,
      icon: Icons.download_rounded,
      onTap: onTap,
    );
  }
}

class _RetryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RetryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _ActionButton(
      label: 'Try Again',
      gradient: AppTheme.brandGradient,
      icon: Icons.refresh_rounded,
      onTap: onTap,
    );
  }
}

// ── Shared Widgets ──────────────────────────────────────────────────────────

class _BulletItem extends StatelessWidget {
  final String text;
  const _BulletItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 5, right: 8),
            decoration: const BoxDecoration(
              color: AppTheme.connectedText,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.glassBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final LinearGradient gradient;
  final IconData? icon;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.gradient,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            boxShadow: onTap != null
                ? [
                    BoxShadow(
                      color:
                          gradient.colors.first.withValues(alpha: 0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FadeSlide extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final Widget child;

  const _FadeSlide({
    required this.controller,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final remaining = 1.0 - delay;
        final value = remaining <= 0
            ? 1.0
            : Curves.easeOut.transform(
                ((controller.value - delay) / remaining).clamp(0.0, 1.0),
              );
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }
}
