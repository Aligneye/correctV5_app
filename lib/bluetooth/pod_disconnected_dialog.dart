import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/bluetooth/bluetooth_service_manager.dart';
import 'package:correctv1/bluetooth/device_connect_page.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shows the "Align Pod is Disconnected" dialog.
/// If the user taps "Tap to Connect", checks BLE readiness using the
/// caller's [context] (which stays mounted after the dialog closes),
/// then navigates to [DeviceConnectPage].
Future<void> showPodDisconnectedDialog(
  BuildContext context, {
  String subtitle = 'Connect your Align Pod to start calibration.',
}) async {
  final shouldConnect = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _PodDisconnectedDialog(subtitle: subtitle),
  );

  if (shouldConnect != true) return;
  if (!context.mounted) return;

  // BLE readiness check runs in caller's context — still alive after dialog close.
  final ready = await _ensureBleReady(context);
  if (!ready || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const DeviceConnectPage()),
  );
}

Future<bool> _ensureBleReady(BuildContext context) async {
  final deviceService = BluetoothServiceManager().deviceService;
  final readiness = await deviceService.checkReadiness();
  if (!context.mounted) return false;

  switch (readiness) {
    case BleReadiness.ready:
      return true;

    case BleReadiness.bluetoothUnsupported:
      _showSnack(context, 'Bluetooth is not supported on this device.');
      return false;

    case BleReadiness.bluetoothOff:
      try {
        await FlutterBluePlus.turnOn();
        final on = await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 8));
        if (on == BluetoothAdapterState.on) return true;
      } catch (_) {}
      if (!context.mounted) return false;
      _showSnack(
        context,
        'Bluetooth is required to connect. Please enable it and try again.',
      );
      return false;

    case BleReadiness.permissionDenied:
      _showSnack(
        context,
        'Bluetooth permissions are required. Please grant them and try again.',
      );
      return false;

    case BleReadiness.permissionPermanentlyDenied:
      if (!context.mounted) return false;
      _showSnack(context, 'Bluetooth permissions were denied. Opening settings…');
      await openAppSettings();
      return false;
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
}

class _PodDisconnectedDialog extends StatelessWidget {
  const _PodDisconnectedDialog({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.brandPrimary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bluetooth_disabled_rounded,
                size: 30,
                color: AppTheme.brandPrimary,
              ),
            ),
            const SizedBox(height: 18),

            // Title
            Text(
              'Align Pod is Disconnected',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),

            // Tap to Connect — gradient button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      // Return true — caller handles BLE check + navigation
                      Navigator.of(context).pop(true);
                    },
                    child: const Center(
                      child: Text(
                        'Tap to Connect',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Cancel — ghost button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: scheme.outline),
                  ),
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop(false);
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
