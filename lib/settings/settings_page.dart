import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:correctv1/bluetooth/device_connect_page.dart';
import 'package:correctv1/bluetooth/bluetooth_service_manager.dart';
import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:correctv1/auth/auth_service.dart';
import 'package:correctv1/settings/firmware_update_page.dart';
import 'package:correctv1/calibration/calibration_manager_page.dart';
import 'package:correctv1/bluetooth/pod_disconnected_dialog.dart';
import 'package:correctv1/services/theme_service.dart';
import 'package:correctv1/legal/medical_disclaimer_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final AnimationController _ringCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out',
                style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (confirmed == true) await AuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.pageBackgroundGradientFor(context),
        ),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            physics: const BouncingScrollPhysics(),
            child: AnimatedBuilder(
              animation: _entryCtrl,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fade(0.0, _ProfileHeroCard(ringCtrl: _ringCtrl)),
                  const SizedBox(height: 28),
                  _fade(0.15, _SectionLabel(label: 'DEVICE')),
                  const SizedBox(height: 10),
                  _fade(0.2, _DeviceSection()),
                  const SizedBox(height: 24),
                  _fade(0.35, _SectionLabel(label: 'APPEARANCE')),
                  const SizedBox(height: 10),
                  _fade(0.4, _AppearanceSection()),
                  const SizedBox(height: 24),
                  _fade(0.5, _SectionLabel(label: 'LEGAL')),
                  const SizedBox(height: 10),
                  _fade(0.55, _LegalSection()),
                  const SizedBox(height: 32),
                  _fade(
                    0.65,
                    Center(
                      child: GestureDetector(
                        onTap: _confirmLogout,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Log out',
                            style: TextStyle(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.85),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _fade(0.7, const _AppVersionLabel()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fade(double start, Widget child) {
    final v = Curves.easeOutCubic.transform(
      ((_entryCtrl.value - start) / (1.0 - start)).clamp(0.0, 1.0),
    );
    return Opacity(
      opacity: v,
      child:
          Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
    );
  }
}

// ── Profile Hero ──────────────────────────────────────────────────────────────

class _ProfileHeroCard extends StatelessWidget {
  final AnimationController ringCtrl;
  const _ProfileHeroCard({required this.ringCtrl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    final name = user?.userMetadata?['full_name'] as String? ??
        email.split('@').first.replaceAll(RegExp(r'[._\-]'), ' ');
    final avatarUrl = user?.userMetadata?['avatar_url'] as String?;
    final initials = _initials(email);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1F26) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? const Color(0xFF2A2D35)
              : const Color(0xFF9333EA).withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9333EA)
                .withValues(alpha: isDark ? 0.12 : 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: ringCtrl,
            builder: (context, _) => CustomPaint(
              painter: _GradientRingPainter(progress: ringCtrl.value),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ClipOval(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: avatarUrl != null
                        ? Image.network(avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, st) =>
                                _InitialsAvatar(initials: initials))
                        : _InitialsAvatar(initials: initials),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _capitalize(name),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<DeviceConnectionStatus>(
            valueListenable:
                BluetoothServiceManager().deviceService.connectionStatus,
            builder: (context, status, _) {
              final connected = status == DeviceConnectionStatus.connected;
              if (!connected) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text('No pod',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                );
              }
              return ValueListenableBuilder<String>(
                valueListenable:
                    BluetoothServiceManager().deviceService.activeProfileName,
                builder: (context, profileName, _) {
                  final label =
                      profileName.isNotEmpty ? profileName : 'Pod';
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF22C55E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF22C55E)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF22C55E),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(label,
                            style: const TextStyle(
                              color: Color(0xFF22C55E),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  static String _initials(String email) {
    final parts =
        email.split('@').first.split(RegExp(r'[._\-]'));
    if (parts.length >= 2 &&
        parts[0].isNotEmpty &&
        parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final s = email.split('@').first;
    return s.length >= 2 ? s.substring(0, 2).toUpperCase() : '?';
  }

  static String _capitalize(String s) => s
      .split(' ')
      .map((w) =>
          w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class _InitialsAvatar extends StatelessWidget {
  final String initials;
  const _InitialsAvatar({required this.initials});

  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          gradient: AppTheme.brandGradient,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(initials,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
      );
}

class _GradientRingPainter extends CustomPainter {
  final double progress;
  const _GradientRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..shader = SweepGradient(
        colors: const [
          Color(0xFF9333EA),
          Color(0xFF2563EB),
          Color(0xFFEC4899),
          Color(0xFF9333EA),
        ],
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(Offset.zero & size);
    canvas.drawOval((Offset.zero & size).deflate(1.25), paint);
  }

  @override
  bool shouldRepaint(covariant _GradientRingPainter old) =>
      old.progress != progress;
}

// ── Section Label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.6),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ── Group Card ────────────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1F26) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? const Color(0xFF2A2D35)
              : const Color(0xFFE5E7EB),
        ),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 56,
                color:
                    scheme.outline.withValues(alpha: 0.5),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Row Item ──────────────────────────────────────────────────────────────────

class _RowItem extends StatelessWidget {
  final LinearGradient gradient;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  const _RowItem({
    required this.gradient,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap != null
            ? () {
                HapticFeedback.selectionClick();
                onTap!();
              }
            : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: destructive ? null : gradient,
                  color: destructive
                      ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    size: 18,
                    color: destructive
                        ? const Color(0xFFEF4444)
                        : Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: destructive
                            ? const Color(0xFFEF4444)
                            : scheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant
                        .withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Device Section ────────────────────────────────────────────────────────────

class _DeviceSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final svc = BluetoothServiceManager().deviceService;

    return _GroupCard(children: [
      // Pod connect / disconnect
      ValueListenableBuilder<DeviceConnectionStatus>(
        valueListenable: svc.connectionStatus,
        builder: (context, status, _) {
          final connected = status == DeviceConnectionStatus.connected;
          return _RowItem(
            gradient: AppTheme.brandGradient,
            icon: Icons.bluetooth_rounded,
            title: 'Align Pod',
            subtitle: connected ? 'Connected' : 'Tap to connect',
            trailing: _StatusDot(connected: connected),
            onTap: () async {
              if (connected) {
                await BluetoothServiceManager().disconnectByUser();
              } else {
                final readiness = await svc.checkReadiness();
                if (!context.mounted) return;
                if (readiness == BleReadiness.bluetoothOff) {
                  try {
                    await FlutterBluePlus.turnOn();
                    await FlutterBluePlus.adapterState
                        .where((s) => s == BluetoothAdapterState.on)
                        .first
                        .timeout(const Duration(seconds: 8));
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Please enable Bluetooth to connect.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                    return;
                  }
                  if (!context.mounted) return;
                }
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const DeviceConnectPage(),
                ));
              }
            },
          );
        },
      ),
      // Firmware
      ValueListenableBuilder(
        valueListenable: svc.deviceInfo,
        builder: (context, info, _) {
          final fw = (info?.firmwareVersion.isNotEmpty == true)
              ? 'Firmware v${info!.firmwareVersion}'
              : null;
          return _RowItem(
            gradient: AppTheme.trackingGradient,
            icon: Icons.download_rounded,
            title: 'Firmware Update',
            subtitle: fw,
            onTap: () {
              svc.getDeviceInfo();
              Navigator.of(context).push(_slideRoute(
                const FirmwareUpdatePage(),
              ));
            },
          );
        },
      ),
      // Calibration with active profile subtitle
      ValueListenableBuilder<String>(
        valueListenable: svc.activeProfileName,
        builder: (context, profileName, _) => _RowItem(
          gradient: AppTheme.goodPostureGradient,
          icon: Icons.wifi_tethering_rounded,
          title: 'Alignment Calibration',
          subtitle: profileName.isNotEmpty ? profileName : null,
          onTap: () async {
            if (svc.connectionStatus.value !=
                DeviceConnectionStatus.connected) {
              await showPodDisconnectedDialog(context);
              return;
            }
            if (!context.mounted) return;
            Navigator.of(context).push(_slideRoute(
              CalibrationManagerPage(deviceService: svc),
            ));
          },
        ),
      ),
      // About Device
      ValueListenableBuilder(
        valueListenable: svc.deviceInfo,
        builder: (context, info, _) => _RowItem(
          gradient: AppTheme.vibrationTherapyGradient,
          icon: Icons.info_outline_rounded,
          title: 'About Device',
          subtitle: (info?.serial.isNotEmpty == true)
              ? 'SN: ${info!.serial}'
              : null,
          onTap: () => _showAboutSheet(context, info),
        ),
      ),
      // Forget device
      _RowItem(
        gradient: AppTheme.therapyGradient,
        icon: Icons.delete_outline_rounded,
        title: 'Forget Device',
        destructive: true,
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Forget device?'),
              content: const Text(
                  'Removes all saved pod data. You will need to pair again.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Forget',
                        style: TextStyle(color: Colors.red))),
              ],
            ),
          );
          if (confirmed == true) {
            await BluetoothServiceManager().forgetDevice();
          }
        },
      ),
    ]);
  }
}

class _StatusDot extends StatelessWidget {
  final bool connected;
  const _StatusDot({required this.connected});

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected
              ? const Color(0xFF22C55E)
              : const Color(0xFF6B7280),
        ),
      );
}


void _showAboutSheet(BuildContext context, DeviceInfo? info) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _AboutSheet(info: info),
  );
}

class _AboutSheet extends StatelessWidget {
  final DeviceInfo? info;
  const _AboutSheet({required this.info});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final rows = <(String, String)>[
      if (info?.serial.isNotEmpty == true) ('Serial Number', info!.serial),
      if (info?.model.isNotEmpty == true) ('Model', info!.model),
      if (info?.hardwareRevision.isNotEmpty == true)
        ('Hardware', info!.hardwareRevision),
      if (info?.firmwareVersion.isNotEmpty == true)
        ('Firmware', info!.firmwareVersion),
      if (info?.firmwareBuildDate.isNotEmpty == true)
        ('Build Date', info!.firmwareBuildDate),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1F26) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'About Device',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Connect your Align Pod to see device info.',
                style:
                    TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              ),
            )
          else
            ...rows.map((r) => _InfoRow(label: r.$1, value: r.$2)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: Text(
                value,
                style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

PageRouteBuilder<void> _slideRoute(Widget page) => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, anim, sec) => page,
      transitionsBuilder: (ctx, anim, sec, child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );

// ── Appearance Section ────────────────────────────────────────────────────────

class _AppearanceSection extends StatelessWidget {
  static const _options = [
    (ThemeMode.system, 'System'),
    (ThemeMode.light, 'Light'),
    (ThemeMode.dark, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return _GroupCard(children: [
      Padding(
        padding:
            const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF818CF8), Color(0xFF3B82F6)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.palette_rounded,
                  size: 18, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text('Theme',
                  style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeService.instance.themeMode,
              builder: (context, currentMode, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: _options.map((opt) {
                  final sel = currentMode == opt.$1;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ThemeService.instance.setMode(opt.$1);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient:
                            sel ? AppTheme.brandGradient : null,
                        color: sel
                            ? null
                            : isDark
                                ? Colors.white
                                    .withValues(alpha: 0.08)
                                : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        opt.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? Colors.white
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

// ── Legal Section ─────────────────────────────────────────────────────────────

class _LegalSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _GroupCard(children: [
      _RowItem(
        gradient: AppTheme.meditationGradient,
        icon: Icons.shield_outlined,
        title: 'Medical Disclaimer',
        subtitle: 'Health & wellness information',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
              builder: (_) => const MedicalDisclaimerPage()),
        ),
      ),
    ]);
  }
}

// ── App Version ───────────────────────────────────────────────────────────────

class _AppVersionLabel extends StatefulWidget {
  const _AppVersionLabel();

  @override
  State<_AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<_AppVersionLabel> {
  String _v = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((i) {
          if (mounted) setState(() => _v = 'Align Pod v${i.version}');
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_v.isEmpty) return const SizedBox.shrink();
    return Center(
      child: Text(_v,
          style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.4),
              fontSize: 12)),
    );
  }
}
