import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:correctv1/home/therapy_page.dart';

class TherapyArea {
  final String id;
  final String label;

  const TherapyArea(this.id, this.label);
}

const therapyAreas = <TherapyArea>[
  TherapyArea('neck', 'Neck & shoulders'),
  TherapyArea('upper_back', 'Upper back'),
  TherapyArea('lower_back', 'Lower back'),
  TherapyArea('left_hand', 'Left hand'),
  TherapyArea('right_hand', 'Right hand'),
  TherapyArea('left_leg', 'Left leg'),
  TherapyArea('right_leg', 'Right leg'),
  TherapyArea('left_foot', 'Left foot'),
  TherapyArea('right_foot', 'Right foot'),
];

/// Region cards and the sub-options shown in the toggle below them.
/// A region tap selects its first option (Back defaults to upper back,
/// where the GV acupressure points are).
const _regions =
    <
      ({
        String label,
        IconData icon,
        String prompt,
        List<(String id, String label)> options,
      })
    >[
      (
        label: 'Back',
        icon: Icons.accessibility_new_rounded,
        prompt: 'Which part?',
        options: [
          ('neck', 'Neck'),
          ('upper_back', 'Upper'),
          ('lower_back', 'Lower'),
        ],
      ),
      (
        label: 'Hand',
        icon: Icons.back_hand_rounded,
        prompt: 'Which side?',
        options: [('left_hand', 'Left'), ('right_hand', 'Right')],
      ),
      (
        label: 'Leg',
        icon: Icons.directions_walk_rounded,
        prompt: 'Which side?',
        options: [('left_leg', 'Left'), ('right_leg', 'Right')],
      ),
      (
        label: 'Foot',
        icon: Icons.ice_skating_rounded,
        prompt: 'Which side?',
        options: [('left_foot', 'Left'), ('right_foot', 'Right')],
      ),
    ];

const String _kPrefTherapyArea = 'therapy_last_area';

const _pinkGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFF1F5B), Color(0xFFED2CA6)],
);

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

  void _select(String id) {
    if (id == _selectedId) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedId = id);
  }

  Future<void> _continue() async {
    HapticFeedback.mediumImpact();
    final area = therapyAreas.firstWhere((a) => a.id == _selectedId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefTherapyArea, area.id);
    } catch (_) {
      // Non-critical.
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => TherapyPage(area: area)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = therapyAreas.firstWhere((a) => a.id == _selectedId);
    final region = _regions.firstWhere(
      (r) => r.options.any((o) => o.$1 == _selectedId),
    );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(23, 20, 22, 22),
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
              'Pick the spot where you will place your Align Pod.',
              style: TextStyle(
                color: Color(0xFF667085),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                for (final r in _regions)
                  _RegionCard(
                    label: r.label,
                    icon: r.icon,
                    isSelected: identical(r, region),
                    onTap: () => _select(
                      r.label == 'Back' ? 'upper_back' : r.options.first.$1,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              region.prompt,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: [
                  for (final o in region.options)
                    ButtonSegment(value: o.$1, label: Text(o.$2)),
                ],
                selected: {_selectedId},
                onSelectionChanged: (s) => _select(s.first),
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: const Color(0xFFFF2B62),
                  selectedForegroundColor: Colors.white,
                  foregroundColor: scheme.onSurface,
                  minimumSize: const Size.fromHeight(46),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _continue,
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: _pinkGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF43F5E).withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'Continue with ${selected.label.toLowerCase()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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

class _RegionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RegionCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = isSelected ? Colors.white : scheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: isSelected ? _pinkGradient : null,
            color: isSelected ? null : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: isSelected ? null : Border.all(color: scheme.outline),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.27),
                      blurRadius: 13,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 32,
                color: isSelected ? Colors.white : const Color(0xFFFF2B62),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
