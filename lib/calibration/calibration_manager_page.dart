import 'dart:convert';

import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/calibration/calibration_page.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class SavedCalibration {
  final int id;
  final String name;
  final DateTime createdAt;
  final bool isDefault;

  const SavedCalibration({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.isDefault,
  });

  SavedCalibration copyWith({int? id, String? name, DateTime? createdAt, bool? isDefault}) {
    return SavedCalibration(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'isDefault': isDefault,
  };

  factory SavedCalibration.fromJson(Map<String, dynamic> json) => SavedCalibration(
    id: json['id'] as int,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    isDefault: json['isDefault'] as bool,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Storage helper
// ─────────────────────────────────────────────────────────────────────────────

class _CalibrationStorage {
  static const String _key = 'saved_calibrations';

  static Future<List<SavedCalibration>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => SavedCalibration.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> save(List<SavedCalibration> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
}

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
  List<SavedCalibration> _calibrations = [];
  bool _loading = true;
  late final AnimationController _fadeController;

  static const int _maxSlots = 8;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _loadCalibrations();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadCalibrations() async {
    final list = await _CalibrationStorage.load();
    if (!mounted) return;

    if (list.isEmpty) {
      final defaultCal = SavedCalibration(
        id: 1,
        name: 'Calibration 1',
        createdAt: DateTime.now(),
        isDefault: true,
      );
      await _CalibrationStorage.save([defaultCal]);
      setState(() {
        _calibrations = [defaultCal];
        _loading = false;
      });
    } else {
      setState(() {
        _calibrations = list;
        _loading = false;
      });
    }
    _fadeController.forward();
  }

  Future<void> _saveCalibrations() async {
    await _CalibrationStorage.save(_calibrations);
  }

  void _setDefault(SavedCalibration cal) {
    HapticFeedback.selectionClick();
    setState(() {
      _calibrations = _calibrations.map((c) => c.copyWith(isDefault: c.id == cal.id)).toList();
    });
    _saveCalibrations();
  }

  Future<void> _deleteCalibration(SavedCalibration cal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteDialog(calibration: cal),
    );
    if (confirmed != true || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _calibrations.removeWhere((c) => c.id == cal.id);
      _calibrations = _calibrations.asMap().entries.map((e) {
        final newId = e.key + 1;
        final c = e.value;
        final autoName = RegExp(r'^Calibration \d+$').hasMatch(c.name)
            ? 'Calibration $newId'
            : c.name;
        return c.copyWith(id: newId, name: autoName);
      }).toList();
      if (_calibrations.isNotEmpty && !_calibrations.any((c) => c.isDefault)) {
        _calibrations[0] = _calibrations[0].copyWith(isDefault: true);
      }
    });
    _saveCalibrations();
  }

  Future<void> _addCalibration() async {
    if (_calibrations.length >= _maxSlots) {
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

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CalibrationPage(
          deviceService: widget.deviceService,
          autoStart: false,
        ),
      ),
    );
    if (!mounted || result != true) return;

    final newId = _calibrations.length + 1;
    final newCal = SavedCalibration(
      id: newId,
      name: 'Calibration $newId',
      createdAt: DateTime.now(),
      isDefault: true,
    );

    HapticFeedback.lightImpact();
    setState(() {
      _calibrations = _calibrations.map((c) => c.copyWith(isDefault: false)).toList();
      _calibrations.add(newCal);
    });
    _saveCalibrations();
  }

  Future<void> _startWithCalibration(SavedCalibration cal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RecalibrateDialog(calibration: cal),
    );
    if (confirmed != true || !mounted) return;

    _setDefault(cal);
    if (!mounted) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CalibrationPage(
          deviceService: widget.deviceService,
          autoStart: false,
        ),
      ),
    );
    // Calibration successful — stay on CalibrationManagerPage (1–8 list)
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
                    : FadeTransition(
                  opacity: _fadeController,
                  child: _buildBody(),
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
              '${_calibrations.length} / $_maxSlots',
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Only saved calibrations — no empty slots
          ...List.generate(_calibrations.length, (index) {
            final cal = _calibrations[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CalibrationSlotCard(
                calibration: cal,
                totalSlots: _maxSlots,
                onSelect: () => _startWithCalibration(cal),
                onSetDefault: () => _setDefault(cal),
                onDelete: () => _deleteCalibration(cal),
              ),
            );
          }),

          // Add button below the last calibration
          if (_calibrations.length < _maxSlots) ...[
            const SizedBox(height: 4),
            _AddCalibrationButton(onTap: _addCalibration),
          ],

          const SizedBox(height: 24),
          _SlotUsageBar(used: _calibrations.length, total: _maxSlots),
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
    required this.calibration,
    required this.totalSlots,
    required this.onSelect,
    required this.onSetDefault,
    required this.onDelete,
  });

  final SavedCalibration calibration;
  final int totalSlots;
  final VoidCallback onSelect;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDefault = calibration.isDefault;

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
            // Number badge with gradient if default
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
                  '${calibration.id}',
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
                      Text(
                        calibration.name,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: isDefault ? FontWeight.w600 : FontWeight.w500,
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
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatDate(calibration.createdAt),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
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

  String _formatDate(DateTime dt) {
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
            Text(
              'Slot usage',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
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
  const _DeleteDialog({required this.calibration});

  final SavedCalibration calibration;

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
              'Are you sure you want to delete "${calibration.name}"?'
                  '${calibration.isDefault ? '\n\nThe next calibration will become the default.' : ''}',
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
  const _RecalibrateDialog({required this.calibration});

  final SavedCalibration calibration;

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
              'Do you want to recalibrate "${calibration.name}"?\n\nSit in your ideal posture before starting.',
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