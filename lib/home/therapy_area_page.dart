import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:correctv1/home/therapy_page.dart';

class TherapyArea {
  final String id;
  final String label;
  final String hint; // where the pod goes, in plain words
  final String asset;

  const TherapyArea(this.id, this.label, this.hint, this.asset);
}

/// Ordered head to toe — the list reads like a body, top to bottom.
const therapyAreas = <TherapyArea>[
  TherapyArea(
    'neck',
    'Neck Therapy',
    'Back of the neck',
    'assets/Neck Pain Relief  therapy.png',
  ),
  TherapyArea(
    'shoulders',
    'Shoulder Therapy',
    'Top of either shoulder',
    'assets/Shoulder Therapy Backside Icon.png',
  ),
  TherapyArea(
    'upper_back',
    'Upper Back Therapy',
    'Between the shoulder blades',
    'assets/Upper Back Muscle Therapy Icon.png',
  ),
  TherapyArea(
    'lower_back',
    'Lower Back Therapy',
    'Just above the waist',
    'assets/lower back therapy.png',
  ),
  TherapyArea(
    'core',
    'Core & Abdomen Therapy',
    'Around the belly',
    'assets/Glowing Core Therapy Icon.png',
  ),
  TherapyArea(
    'biceps',
    'Biceps Therapy',
    'Front of the upper arm',
    'assets/Bicep Therapy Icon.png',
  ),
  TherapyArea(
    'triceps',
    'Triceps Therapy',
    'Back of the upper arm',
    'assets/Triceps Therapy Muscle Activation Badge.png',
  ),
  TherapyArea(
    'forearm',
    'Forearm Therapy',
    'Between elbow and wrist',
    'assets/Forearm Therapy Muscle.png',
  ),
  TherapyArea(
    'thigh',
    'Thigh Therapy',
    'Front of the thigh',
    'assets/Thigh Muscle Therapy.png',
  ),
  TherapyArea(
    'knee',
    'Knee Therapy',
    'Around the kneecap',
    'assets/Knee Muscle Anatomy Illustration.png',
  ),
  TherapyArea(
    'calf',
    'Calf Therapy',
    'Back of the lower leg',
    'assets/Calf  Therapy.png',
  ),
  TherapyArea(
    'ankle',
    'Ankle Therapy',
    'Around the ankle',
    'assets/Angel therapy.png',
  ),
];

const String _kPrefTherapyArea = 'therapy_last_area';

const _therapyPink = Color(0xFFFF2B62);

const _fast = Duration(milliseconds: 180);

/// First step of therapy: pick where on the body the pod will sit.
class TherapyAreaPage extends StatefulWidget {
  const TherapyAreaPage({super.key});

  @override
  State<TherapyAreaPage> createState() => _TherapyAreaPageState();
}

class _TherapyAreaPageState extends State<TherapyAreaPage> {
  String _selectedId = 'upper_back';

  @override
  void initState() {
    super.initState();
    _restoreLastArea();
  }

  Future<void> _restoreLastArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kPrefTherapyArea);
      if (!mounted || id == null) return;
      if (therapyAreas.any((a) => a.id == id)) {
        setState(() => _selectedId = id);
      }
    } catch (_) {
      // Default selection still applies.
    }
  }

  bool _opening = false;

  /// One tap picks the area and goes straight to therapy. The highlight
  /// only marks the last-used area.
  Future<void> _open(TherapyArea area) async {
    if (_opening) return; // ignore a fast double tap
    _opening = true;
    HapticFeedback.mediumImpact();
    setState(() => _selectedId = area.id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefTherapyArea, area.id);
    } catch (_) {
      // Non-critical.
    }
    if (!mounted) return;
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => TherapyPage(area: area)));
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(23, 20, 22, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.arrow_back_rounded),
                color: const Color(0xFF4B5563),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 34),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Hero(
                tag: 'mode_icon_therapy',
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF60A5FA), Color(0xFF06B6D4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.graphic_eq,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Where do you want therapy?',
              style: TextStyle(
                color: Color(0xFFFF0055),
                fontSize: 26,
                height: 1.15,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Pick the spot where you'll place your Align Pod.",
              style: TextStyle(
                color: Color(0xFF667085),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < therapyAreas.length; i++)
              _AreaRow(
                area: therapyAreas[i],
                isSelected: therapyAreas[i].id == _selectedId,
                isFirst: i == 0,
                isLast: i == therapyAreas.length - 1,
                onTap: () => _open(therapyAreas[i]),
              ),
          ],
        ),
      ),
    );
  }
}

/// One body area. The thin line behind the thumbnails runs head to toe
/// through every row, so the list reads as one body.
class _AreaRow extends StatelessWidget {
  final TherapyArea area;
  final bool isSelected;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const _AreaRow({
    required this.area,
    required this.isSelected,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  static const double _rowHeight = 84;
  static const double _thumb = 60;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spineColor = isDark ? scheme.outlineVariant : const Color(0xFFE5E7EB);
    final tint = isDark
        ? _therapyPink.withValues(alpha: 0.12)
        : const Color(0xFFFFF1F5);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${area.label}. ${area.hint}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: _fast,
            curve: Curves.easeOutCubic,
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isSelected ? tint : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: _thumb + 4,
                  height: _rowHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Spine: upper half joins the row above, lower half
                      // the row below.
                      Column(
                        children: [
                          Expanded(
                            child: Container(
                              width: 2,
                              color: isFirst ? Colors.transparent : spineColor,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              width: 2,
                              color: isLast ? Colors.transparent : spineColor,
                            ),
                          ),
                        ],
                      ),
                      AnimatedContainer(
                        duration: _fast,
                        curve: Curves.easeOutCubic,
                        width: _thumb + 4,
                        height: _thumb + 4,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? _therapyPink : spineColor,
                        ),
                        // Clipped to a circle: the source art has
                        // inconsistent corners (white, transparent).
                        child: ClipOval(
                          child: Image.asset(
                            area.asset,
                            fit: BoxFit.cover,
                            // Source files are ~1250px; decode small.
                            cacheWidth: 180,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        area.label,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        area.hint,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  duration: _fast,
                  opacity: isSelected ? 1 : 0,
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: _therapyPink,
                    size: 24,
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
