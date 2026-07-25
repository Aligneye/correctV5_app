import 'package:flutter/material.dart';

/// States shown by [PullConnectBanner] while the user pulls-to-refresh
/// on the home page.
enum PullConnectPhase {
  /// Nothing happening — banner is collapsed/invisible.
  idle,

  /// Attempting to connect with the pod.
  connecting,

  /// Connect succeeded.
  connected,

  /// Connect attempt failed — pod is not connected.
  failed,

  /// Syncing sessions from a connected device to the backend.
  syncing,

  /// Session sync completed successfully.
  synced,

  /// Bluetooth is turned off on the device.
  bluetoothOff,

  /// Required Bluetooth / location permissions are denied.
  permissionDenied,

  /// Device signal is weak (RSSI below threshold).
  weakSignal,
}

/// A slim animated banner that grows in at the top of the home page when
/// the user pulls to refresh, replacing the plain platform spinner with a
/// colored status readout.
class PullConnectBanner extends StatelessWidget {
  final PullConnectPhase phase;

  /// Optional override for the label shown in the [PullConnectPhase.synced]
  /// state (e.g. "3 sessions synced"). Falls back to "Sessions synced".
  final String? syncedLabel;

  /// Optional failure reason shown in [PullConnectPhase.failed].
  final String? failedReason;

  const PullConnectBanner({
    super.key,
    required this.phase,
    this.syncedLabel,
    this.failedReason,
  });

  _BannerStyle _buildStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Dark-mode aware palette helpers
    Color bg(Color light, Color dark) => isDark ? dark : light;
    Color bd(Color light, Color dark) => isDark ? dark : light;

    switch (phase) {
      case PullConnectPhase.connecting:
        return _BannerStyle(
          background: bg(const Color(0xFFFFF7ED), const Color(0xFF2D1800)),
          border: bd(const Color(0xFFFED7AA), const Color(0xFF7C3A00)),
          foreground: bg(const Color(0xFFEA580C), const Color(0xFFFB923C)),
          label: 'Connecting…',
          icon: Icons.bluetooth_searching_rounded,
          showSpinner: true,
        );
      case PullConnectPhase.connected:
        return _BannerStyle(
          background: bg(const Color(0xFFF0FDF4), const Color(0xFF052E16)),
          border: bd(const Color(0xFFBBF7D0), const Color(0xFF14532D)),
          foreground: bg(const Color(0xFF16A34A), const Color(0xFF4ADE80)),
          label: 'Connected',
          icon: Icons.bluetooth_connected_rounded,
          showSpinner: false,
        );
      case PullConnectPhase.failed:
        return _BannerStyle(
          background: bg(const Color(0xFFFEF2F2), const Color(0xFF2D0000)),
          border: bd(const Color(0xFFFECACA), const Color(0xFF7F1D1D)),
          foreground: bg(const Color(0xFFDC2626), const Color(0xFFF87171)),
          label: failedReason ?? 'Not connected',
          icon: Icons.bluetooth_disabled_rounded,
          showSpinner: false,
        );
      case PullConnectPhase.syncing:
        return _BannerStyle(
          background: bg(const Color(0xFFFFF7ED), const Color(0xFF2D1800)),
          border: bd(const Color(0xFFFED7AA), const Color(0xFF7C3A00)),
          foreground: bg(const Color(0xFFEA580C), const Color(0xFFFB923C)),
          label: 'Syncing sessions…',
          icon: Icons.sync_rounded,
          showSpinner: true,
        );
      case PullConnectPhase.synced:
        return _BannerStyle(
          background: bg(const Color(0xFFF0FDF4), const Color(0xFF052E16)),
          border: bd(const Color(0xFFBBF7D0), const Color(0xFF14532D)),
          foreground: bg(const Color(0xFF16A34A), const Color(0xFF4ADE80)),
          label: syncedLabel ?? 'Sessions synced',
          icon: Icons.check_circle_outline_rounded,
          showSpinner: false,
        );
      case PullConnectPhase.bluetoothOff:
        return _BannerStyle(
          background: bg(const Color(0xFFEFF6FF), const Color(0xFF0A1929)),
          border: bd(const Color(0xFFBFDBFE), const Color(0xFF1E3A5F)),
          foreground: bg(const Color(0xFF2563EB), const Color(0xFF60A5FA)),
          label: 'Bluetooth is off',
          icon: Icons.bluetooth_disabled_rounded,
          showSpinner: false,
        );
      case PullConnectPhase.permissionDenied:
        return _BannerStyle(
          background: bg(const Color(0xFFFFFBEB), const Color(0xFF2D1F00)),
          border: bd(const Color(0xFFFDE68A), const Color(0xFF78460F)),
          foreground: bg(const Color(0xFFD97706), const Color(0xFFFBBF24)),
          label: 'Permission required',
          icon: Icons.lock_outline_rounded,
          showSpinner: false,
        );
      case PullConnectPhase.weakSignal:
        return _BannerStyle(
          background: bg(const Color(0xFFFFFBEB), const Color(0xFF2D1F00)),
          border: bd(const Color(0xFFFDE68A), const Color(0xFF78460F)),
          foreground: bg(const Color(0xFFD97706), const Color(0xFFFBBF24)),
          label: 'Weak signal — move closer',
          icon: Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
          showSpinner: false,
        );
      case PullConnectPhase.idle:
        return _BannerStyle(
          background: Colors.transparent,
          border: Colors.transparent,
          foreground: Colors.transparent,
          label: '',
          icon: Icons.bluetooth_rounded,
          showSpinner: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = phase != PullConnectPhase.idle;
    final style = _buildStyle(context);

    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isVisible ? 1 : 0,
          child: !isVisible
              ? const SizedBox(width: double.infinity, height: 0)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: style.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: style.border, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      style.showSpinner
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  style.foreground,
                                ),
                              ),
                            )
                          : Icon(style.icon, size: 16, color: style.foreground),
                      const SizedBox(width: 8),
                      Text(
                        style.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: style.foreground,
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

class _BannerStyle {
  final Color background;
  final Color border;
  final Color foreground;
  final String label;
  final IconData icon;
  final bool showSpinner;

  const _BannerStyle({
    required this.background,
    required this.border,
    required this.foreground,
    required this.label,
    required this.icon,
    required this.showSpinner,
  });
}
