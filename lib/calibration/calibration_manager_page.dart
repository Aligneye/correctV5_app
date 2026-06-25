import 'dart:async';

import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/calibration/calibration_page.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class CalibrationManagerPage extends StatefulWidget {
  const CalibrationManagerPage({
    super.key,
    required this.deviceService,
  });

  final AlignEyeDeviceService deviceService;

  @override
  State<CalibrationManagerPage> createState() => _CalibrationManagerPageState();
}

class _CalibrationManagerPageState extends State<CalibrationManagerPage>
    with SingleTickerProviderStateMixin {
  List<FirmwareProfile> _profiles = [];
  bool _loading = true;
  bool _actionInProgress = false;
  late final AnimationController _fadeController;
  StreamSubscription<List<FirmwareProfile>>? _profileListSub;

  static const int _maxSlots = 8;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _initProfiles();
  }

  @override
  void dispose() {
    _profileListSub?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _initProfiles() async {
    // Subscribe to live firmware profile updates
    _profileListSub = widget.deviceService.profileListStream.listen((profiles) {
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _loading = false;
        debugPrint('📋 Manager got ${profiles.length} profiles');
        _actionInProgress = false;
      });
      if (!_fadeController.isAnimating && _fadeController.value < 1.0) {
        _fadeController.forward();
      }
    });

    // Seed UI immediately from cache if available
    final cached = widget.deviceService.lastKnownProfiles;
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _profiles = cached;
        _loading = false;
      });
      _fadeController.forward();
    }

    // If device is not connected, getProfiles() returns false immediately
    // and profileListStream never emits — causing infinite loading spinner.
    // Stop loading right away when disconnected.
    final isConnected = widget.deviceService.connectionStatus.value ==
        DeviceConnectionStatus.connected;
    if (!isConnected) {
      if (mounted && _loading) {
        setState(() => _loading = false);
        _fadeController.forward();
      }
      return;
    }

    // Always fetch fresh from firmware
    await widget.deviceService.getProfiles();

    // Fallback: stop loading if firmware doesn't respond or completes in 3 seconds
    Timer(const Duration(seconds: 3), () {
      if (mounted && _loading) {
        setState(() => _loading = false);
        _fadeController.forward();
      }
    });
  }

  Future<void> _refreshProfiles() async {
    await widget.deviceService.getProfiles();
  }

  Future<void> _setDefault(FirmwareProfile profile) async {
    if (_actionInProgress) return;
    HapticFeedback.selectionClick();
    setState(() => _actionInProgress = true);
    await widget.deviceService.setDefaultProfile(profile.id);
    await widget.deviceService.getProfiles();
  }

  Future<void> _deleteProfile(FirmwareProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteDialog(profileName: profile.name, isDefault: profile.isDefault),
    );
    if (confirmed != true || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _actionInProgress = true);
    await widget.deviceService.deleteProfile(profile.id);
    await widget.deviceService.getProfiles();
  }

  Future<void> _addCalibration() async {
    if (_profiles.length >= _maxSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Maximum 8 calibrations reached. Delete one to add new.'),
          backgroundColor: AppTheme.destructive,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final newSlot = _profiles.length + 1;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CalibrationPage(
          deviceService: widget.deviceService,
          autoStart: false,
          profileName: 'Profile $newSlot',
        ),
      ),
    );
    if (!mounted || result != true) return;

    HapticFeedback.lightImpact();
    // Firmware already saved the profile during calibration success.
    // Just refresh the list.
    await widget.deviceService.getProfiles();
  }

  Future<void> _recalibrateProfile(FirmwareProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RecalibrateDialog(profileName: profile.name),
    );
    if (confirmed != true || !mounted) return;

    // Select this profile as active before recalibrating
    await widget.deviceService.selectProfile(profile.id);

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CalibrationPage(
          deviceService: widget.deviceService,
          autoStart: false,
          profileName: profile.name,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await widget.deviceService.getProfiles();
    }
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
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _loading
                    ? Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.brandPrimary,
                    strokeWidth: 2.5,
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _refreshProfiles,
                  color: AppTheme.brandPrimary,
                  child: FadeTransition(
                    opacity: _fadeController,
                    child: _buildBody(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop(false);
            },
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppTheme.textPrimary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Calibrations',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          if (_actionInProgress)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.brandPrimary,
              ),
            ),
          const SizedBox(width: 8),
          // Slot counter pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppTheme.brandPrimary.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              '${_profiles.length} / $_maxSlots',
              style: const TextStyle(
                color: AppTheme.brandPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_profiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_tethering_off_rounded,
                  size: 48, color: AppTheme.textMuted.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              const Text(
                'No calibrations yet',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap + Add Calibration to start',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 32),
              _AddCalibrationButton(onTap: _addCalibration),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...List.generate(_profiles.length, (index) {
            final profile = _profiles[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CalibrationSlotCard(
                profile: profile,
                totalSlots: _maxSlots,
                onSelect: () => _recalibrateProfile(profile),
                onSetDefault: () => _setDefault(profile),
                onDelete: () => _deleteProfile(profile),
              ),
            );
          }),

          if (_profiles.length < _maxSlots) ...[
            const SizedBox(height: 4),
            _AddCalibrationButton(onTap: _addCalibration),
          ],

          const SizedBox(height: 24),
          _SlotUsageBar(used: _profiles.length, total: _maxSlots),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Calibration card
// ─────────────────────────────────────────────────────────────────────────────

class _CalibrationSlotCard extends StatelessWidget {
  const _CalibrationSlotCard({
    required this.profile,
    required this.totalSlots,
    required this.onSelect,
    required this.onSetDefault,
    required this.onDelete,
  });

  final FirmwareProfile profile;
  final int totalSlots;
  final VoidCallback onSelect;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDefault = profile.isDefault;
    final isActive = profile.isActive;

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDefault
              ? AppTheme.brandPrimary.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: isDefault
                ? AppTheme.brandPrimary.withValues(alpha: 0.35)
                : AppTheme.border,
            width: isDefault ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDefault
                  ? AppTheme.brandPrimary.withValues(alpha: 0.08)
                  : const Color(0x0A000000),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Slot number badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: isDefault ? AppTheme.brandGradient : null,
                color: isDefault ? null : AppTheme.brandPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: isDefault
                    ? null
                    : Border.all(color: AppTheme.brandPrimary.withValues(alpha: 0.18)),
              ),
              child: Center(
                child: Text(
                  '${profile.slot}',
                  style: TextStyle(
                    color: isDefault ? Colors.white : AppTheme.brandPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.name,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: isDefault ? FontWeight.w600 : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: AppTheme.brandGradient,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      if (isActive && !isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: Color(0xFF22C55E),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        _formatDate(profile.createdAt),
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      if (profile.quality > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '· ${profile.qualityLabel}',
                          style: TextStyle(
                            color: _qualityColor(profile.quality),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDefault)
                  _ActionIcon(
                    icon: Icons.star_border_rounded,
                    tooltip: 'Set Default',
                    color: const Color(0xFFF59E0B),
                    onTap: onSetDefault,
                  ),
                if (isDefault)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 22),
                  ),
                const SizedBox(width: 4),
                _ActionIcon(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete',
                  color: AppTheme.destructive,
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _qualityColor(int quality) {
    if (quality >= 85) return const Color(0xFF22C55E);
    if (quality >= 70) return const Color(0xFF3B82F6);
    if (quality >= 50) return const Color(0xFFF59E0B);
    return AppTheme.destructive;
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add calibration button
// ─────────────────────────────────────────────────────────────────────────────

class _AddCalibrationButton extends StatelessWidget {
  const _AddCalibrationButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            boxShadow: [
              BoxShadow(
                color: AppTheme.brandPrimary.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'Add Calibration',
                  style: TextStyle(
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

// ─────────────────────────────────────────────────────────────────────────────
// Action icon button
// ─────────────────────────────────────────────────────────────────────────────

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slot usage bar
// ─────────────────────────────────────────────────────────────────────────────

class _SlotUsageBar extends StatelessWidget {
  const _SlotUsageBar({required this.used, required this.total});

  final int used;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = used / total;
    final color = fraction < 0.5
        ? AppTheme.brandPrimary
        : fraction < 0.875
        ? const Color(0xFFF59E0B)
        : AppTheme.destructive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Slot usage',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const Spacer(),
            Text(
              '$used of $total used',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: AppTheme.brandPrimary.withValues(alpha: 0.10),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialogs
// ─────────────────────────────────────────────────────────────────────────────

class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.profileName, required this.isDefault});

  final String profileName;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.destructive.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.delete_outline_rounded,
                  color: AppTheme.destructive, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Delete Calibration?',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Are you sure you want to delete "$profileName"?'
                  '${isDefault ? '\n\nThe next calibration will become the default.' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: BorderSide(color: AppTheme.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.destructive,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Delete',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecalibrateDialog extends StatelessWidget {
  const _RecalibrateDialog({required this.profileName});

  final String profileName;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.wifi_tethering_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Recalibrate?',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Do you want to recalibrate "$profileName"?\n\nSit in your ideal posture before starting.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: BorderSide(color: AppTheme.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: EdgeInsets.zero,
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: const Text(
                          'Recalibrate',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}