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

  // App theme colors
  static const Color _bg = Color(0xFF0D1117);
  static const Color _surface = Color(0xFF161B22);
  static const Color _surfaceHigh = Color(0xFF1C2128);
  static const Color _border = Color(0xFF30363D);
  static const Color _textPrimary = Color(0xFFF0F6FC);
  static const Color _textSecondary = Color(0xFF8B949E);
  static const Color _accentTeal = Color(0xFF14B8A6);
  static const Color _accentPurple = Color(0xFFA855F7);
  static const Color _accentPink = Color(0xFFEC4899);
  static const Color _accentRed = Color(0xFFEF4444);
  static const Color _accentGold = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
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
      // Seed default calibration on first launch
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

      // Re-number
      _calibrations = _calibrations.asMap().entries.map((e) {
        final newId = e.key + 1;
        final c = e.value;
        // Auto-rename only if it still matches the default pattern
        final autoName = RegExp(r'^Calibration \d+$').hasMatch(c.name)
            ? 'Calibration $newId'
            : c.name;
        return c.copyWith(id: newId, name: autoName);
      }).toList();

      // If deleted was default, make next (first) the default
      if (_calibrations.isNotEmpty && !_calibrations.any((c) => c.isDefault)) {
        _calibrations[0] = _calibrations[0].copyWith(isDefault: true);
      }
    });
    _saveCalibrations();
  }

  Future<void> _addCalibration() async {
    if (_calibrations.length >= _maxSlots) {
      _showMaxSlotsSnackbar();
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
      isDefault: true, // newest becomes default
    );

    HapticFeedback.lightImpact();
    setState(() {
      // Remove default from others
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
    if (!mounted) return;
    if (result == true) {
      Navigator.of(context).pop(true);
    }
  }

  void _showMaxSlotsSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Maximum 8 calibrations allowed. Delete one to add new.',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1C2128),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(
                child: CircularProgressIndicator(color: _accentTeal),
              )
                  : FadeTransition(
                opacity: _fadeController,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(false),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _textSecondary, size: 16),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Calibrations',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${_calibrations.length} / $_maxSlots slots used',
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (_calibrations.length < _maxSlots)
            GestureDetector(
              onTap: _addCalibration,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_accentPurple, _accentPink],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _accentPurple.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'New',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          _InfoBanner(),
          const SizedBox(height: 20),

          // Slots header
          Row(
            children: [
              const Text(
                'Saved Calibrations',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _surfaceHigh,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  '${_calibrations.length}/$_maxSlots',
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Calibration cards
          ...List.generate(_calibrations.length, (index) {
            final cal = _calibrations[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CalibrationSlotCard(
                calibration: cal,
                onSelect: () => _startWithCalibration(cal),
                onSetDefault: () => _setDefault(cal),
                onDelete: () => _deleteCalibration(cal),
              ),
            );
          }),

          // Empty slots
          if (_calibrations.length < _maxSlots) ...[
            const SizedBox(height: 4),
            ...List.generate(_maxSlots - _calibrations.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _EmptySlotCard(
                  slotNumber: _calibrations.length + i + 1,
                  onTap: _addCalibration,
                ),
              );
            }),
          ],

          const SizedBox(height: 24),

          // Slot usage indicator
          _SlotUsageBar(used: _calibrations.length, total: _maxSlots),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF14B8A6).withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF14B8A6).withOpacity(0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF14B8A6), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Select a calibration to use it. The default calibration is applied automatically on startup. Tap + New to run a fresh calibration.',
              style: TextStyle(
                color: Color(0xFFB2DFDB),
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalibrationSlotCard extends StatelessWidget {
  const _CalibrationSlotCard({
    required this.calibration,
    required this.onSelect,
    required this.onSetDefault,
    required this.onDelete,
  });

  final SavedCalibration calibration;
  final VoidCallback onSelect;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  static const Color _bg = Color(0xFF161B22);
  static const Color _border = Color(0xFF30363D);
  static const Color _textPrimary = Color(0xFFF0F6FC);
  static const Color _textSecondary = Color(0xFF8B949E);
  static const Color _accentTeal = Color(0xFF14B8A6);
  static const Color _accentGold = Color(0xFFF59E0B);
  static const Color _accentRed = Color(0xFFEF4444);
  static const Color _surfaceHigh = Color(0xFF1C2128);

  @override
  Widget build(BuildContext context) {
    final isDefault = calibration.isDefault;

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDefault
              ? const Color(0xFF14B8A6).withOpacity(0.06)
              : _bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDefault
                ? _accentTeal.withOpacity(0.35)
                : _border,
            width: isDefault ? 1.5 : 1,
          ),
          boxShadow: isDefault
              ? [
            BoxShadow(
              color: _accentTeal.withOpacity(0.08),
              blurRadius: 12,
              spreadRadius: 0,
            )
          ]
              : null,
        ),
        child: Row(
          children: [
            // Number badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: isDefault
                    ? const LinearGradient(
                  colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                    : null,
                color: isDefault ? null : _surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: isDefault
                    ? null
                    : Border.all(color: _border),
              ),
              child: Center(
                child: Text(
                  '${calibration.id}',
                  style: TextStyle(
                    color: isDefault ? Colors.white : _textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        calibration.name,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 15,
                          fontWeight: isDefault ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _accentTeal.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              color: _accentTeal,
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
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
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
                    color: _accentGold,
                    onTap: onSetDefault,
                  ),
                if (isDefault)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.star_rounded, color: _accentGold, size: 22),
                  ),
                const SizedBox(width: 4),
                _ActionIcon(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete',
                  color: _accentRed,
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
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

class _EmptySlotCard extends StatelessWidget {
  const _EmptySlotCard({required this.slotNumber, required this.onTap});

  final int slotNumber;
  final VoidCallback onTap;

  static const Color _bg = Color(0xFF0D1117);
  static const Color _border = Color(0xFF21262D);
  static const Color _textMuted = Color(0xFF484F58);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border, style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Center(
                child: Text(
                  '$slotNumber',
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            const Text(
              'Empty slot — tap to calibrate',
              style: TextStyle(
                color: _textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const Spacer(),
            Icon(Icons.add_circle_outline_rounded, color: _textMuted.withOpacity(0.6), size: 20),
          ],
        ),
      ),
    );
  }
}

class _SlotUsageBar extends StatelessWidget {
  const _SlotUsageBar({required this.used, required this.total});

  final int used;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = used / total;
    final color = fraction < 0.5
        ? const Color(0xFF14B8A6)
        : fraction < 0.875
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Slot usage',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
            ),
            const Spacer(),
            Text(
              '$used of $total used',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: const Color(0xFF21262D),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Delete dialog
// ─────────────────────────────────────────────────────────────────────────────

class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.calibration});

  final SavedCalibration calibration;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161B22),
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
                color: const Color(0xFFEF4444).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444), size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Delete Calibration?',
              style: TextStyle(
                color: Color(0xFFF0F6FC),
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
                color: Color(0xFF8B949E),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C2128),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF30363D)),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFF8B949E),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFEF4444).withOpacity(0.3),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Delete',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
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

class _RecalibrateDialog extends StatelessWidget {
  const _RecalibrateDialog({required this.calibration});

  final SavedCalibration calibration;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161B22),
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
                color: const Color(0xFF14B8A6).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_tethering_rounded,
                  color: Color(0xFF14B8A6), size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Recalibrate?',
              style: TextStyle(
                color: Color(0xFFF0F6FC),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Do you want to recalibrate "${calibration.name}"?\n\nSit in your ideal posture before starting.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C2128),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF30363D)),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFF8B949E),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF14B8A6).withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
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