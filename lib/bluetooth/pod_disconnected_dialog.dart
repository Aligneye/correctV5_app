import 'package:correctv1/bluetooth/device_connect_page.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a themed dialog when the Pod is disconnected and the user tries to
/// perform a device-dependent action.
///
/// [subtitle] overrides the default description text so each call site can
/// explain what requires a connection (calibration, training, therapy, etc.).
///
/// "Tap to Connect" navigates to [DeviceConnectPage] — identical behaviour to
/// the header pill on the home page. "Cancel" simply closes the dialog.
Future<void> showPodDisconnectedDialog(
  BuildContext context, {
  String subtitle =
      'Connect your AlignEye Pod to start calibration.',
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _PodDisconnectedDialog(subtitle: subtitle),
  );
}

class _PodDisconnectedDialog extends StatelessWidget {
  const _PodDisconnectedDialog({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
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
            const Text(
              'Your Pod is Disconnected',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
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
                color: AppTheme.textSecondary,
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
                      Navigator.of(context).pop(); // close dialog
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DeviceConnectPage(),
                        ),
                      );
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
                  foregroundColor: AppTheme.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: AppTheme.border,
                    ),
                  ),
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop();
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
