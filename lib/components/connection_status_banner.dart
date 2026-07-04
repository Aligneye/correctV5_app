import 'package:flutter/material.dart';
import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/theme/app_theme.dart';

/// Slim persistent banner showing BLE pod connection state + battery.
/// Renders nothing when connected and battery is unknown (avoids flash on
/// first connect before the first telemetry packet arrives).
class ConnectionStatusBanner extends StatelessWidget {
  final AlignEyeDeviceService deviceService;

  const ConnectionStatusBanner({super.key, required this.deviceService});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DeviceConnectionStatus>(
      valueListenable: deviceService.connectionStatus,
      builder: (context, status, _) {
        if (status == DeviceConnectionStatus.connected) {
          return ValueListenableBuilder<PostureReading?>(
            valueListenable: deviceService.currentReading,
            builder: (context, reading, _) {
              return _ConnectedBanner(battery: reading?.batteryPercentage);
            },
          );
        }
        return _StatusBanner(status: status);
      },
    );
  }
}

// ── Connected state ────────────────────────────────────────────────────────

class _ConnectedBanner extends StatelessWidget {
  final int? battery;
  const _ConnectedBanner({this.battery});

  @override
  Widget build(BuildContext context) {
    // Hide banner entirely when connected — presence is the default state.
    // Only show if battery is critically low (≤15 %).
    if (battery == null || battery! > 15) return const SizedBox.shrink();

    return _BannerShell(
      color: const Color(0xFFFEF3C7),
      borderColor: const Color(0xFFFDE68A),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.battery_alert_rounded, size: 14, color: Color(0xFFD97706)),
          const SizedBox(width: 6),
          Text(
            'Low battery — $battery%',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF92400E),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Disconnected / Connecting states ──────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final DeviceConnectionStatus status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final isConnecting = status == DeviceConnectionStatus.connecting;
    final bg = isConnecting
        ? const Color(0xFFEFF6FF)
        : const Color(0xFFFEF2F2);
    final border = isConnecting
        ? const Color(0xFFBFDBFE)
        : const Color(0xFFFECACA);
    final textColor = isConnecting
        ? AppTheme.connectedText
        : const Color(0xFFDC2626);
    final label = isConnecting ? 'Connecting to pod…' : 'Pod disconnected';
    final icon = isConnecting
        ? Icons.bluetooth_searching_rounded
        : Icons.bluetooth_disabled_rounded;

    return _BannerShell(
      color: bg,
      borderColor: border,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isConnecting
              ? SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    valueColor: AlwaysStoppedAnimation<Color>(textColor),
                  ),
                )
              : Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared shell ───────────────────────────────────────────────────────────

class _BannerShell extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final Widget child;

  const _BannerShell({
    required this.color,
    required this.borderColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        border: Border(
          bottom: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: Center(child: child),
    );
  }
}