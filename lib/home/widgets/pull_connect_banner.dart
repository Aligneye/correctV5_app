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
}

/// A slim animated banner that grows in at the top of the home page when
/// the user pulls to refresh, replacing the plain platform spinner with a
/// colored status readout: orange while connecting, green once connected,
/// and red briefly if the connection attempt failed.
class PullConnectBanner extends StatelessWidget {
  final PullConnectPhase phase;

  /// Optional override for the label shown in the [PullConnectPhase.synced]
  /// state (e.g. "3 sessions synced"). Falls back to "Sessions synced".
  final String? syncedLabel;

  const PullConnectBanner({
    super.key,
    required this.phase,
    this.syncedLabel,
  });

  _BannerStyle get _style {
    switch (phase) {
      case PullConnectPhase.connecting:
        return const _BannerStyle(
          background: Color(0xFFFFF7ED),
          border: Color(0xFFFED7AA),
          foreground: Color(0xFFEA580C),
          label: 'Connecting…',
          icon: Icons.bluetooth_searching_rounded,
          showSpinner: true,
        );
      case PullConnectPhase.connected:
        return const _BannerStyle(
          background: Color(0xFFF0FDF4),
          border: Color(0xFFBBF7D0),
          foreground: Color(0xFF16A34A),
          label: 'Connected',
          icon: Icons.bluetooth_connected_rounded,
          showSpinner: false,
        );
      case PullConnectPhase.failed:
        return const _BannerStyle(
          background: Color(0xFFFEF2F2),
          border: Color(0xFFFECACA),
          foreground: Color(0xFFDC2626),
          label: 'Not connected',
          icon: Icons.bluetooth_disabled_rounded,
          showSpinner: false,
        );
      case PullConnectPhase.syncing:
        return const _BannerStyle(
          background: Color(0xFFFFF7ED),
          border: Color(0xFFFED7AA),
          foreground: Color(0xFFEA580C),
          label: 'Syncing sessions…',
          icon: Icons.sync_rounded,
          showSpinner: true,
        );
      case PullConnectPhase.synced:
        return _BannerStyle(
          background: const Color(0xFFF0FDF4),
          border: const Color(0xFFBBF7D0),
          foreground: const Color(0xFF16A34A),
          label: syncedLabel ?? 'Sessions synced',
          icon: Icons.check_circle_outline_rounded,
          showSpinner: false,
        );
      case PullConnectPhase.idle:
        return const _BannerStyle(
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
    final style = _style;

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