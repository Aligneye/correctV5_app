import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:correctv1/services/session_repository.dart';

import '../../analytics/analytics_screen.dart';

void showXpDetailSheet(
  BuildContext context, {
  required XpStats xpStats,
  required SessionRepository repository,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _XpDetailSheet(
      xpStats: xpStats,
      repository: repository,
    ),
  );
}

class _XpDetailSheet extends StatefulWidget {
  const _XpDetailSheet({
    required this.xpStats,
    required this.repository,
  });

  final XpStats xpStats;
  final SessionRepository repository;

  @override
  State<_XpDetailSheet> createState() => _XpDetailSheetState();
}

class _XpDetailSheetState extends State<_XpDetailSheet>
    with SingleTickerProviderStateMixin {
  List<_SessionXpRow>? _recentXp;
  bool _loading = true;
  late final AnimationController _barCtrl;
  late final Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _barAnim = CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic);
    _load();
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sessions = await widget.repository.fetchByPeriod('all');
      if (!mounted) return;
      final rows = sessions
          .take(8)
          .map((s) {
            final xp = _xpForSession(s);
            return _SessionXpRow(
              label: s.type == SessionType.posture ? 'Training' : 'Therapy',
              duration: s.duration,
              xp: xp,
              isTraining: s.type == SessionType.posture,
              timeLabel: s.time,
            );
          })
          .where((r) => r.xp > 0)
          .toList();
      if (!mounted) return;
      setState(() {
        _recentXp = rows;
        _loading = false;
      });
      _barCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _barCtrl.forward();
    }
  }

  static int _xpForSession(SessionData s) {
    final minutes = s.durationSec ~/ 60;
    final xp = s.type == SessionType.posture ? minutes * 8 : minutes * 12;
    return math.max(xp, 5);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = widget.xpStats;

    const accentStart = Color(0xFFA855F7);
    const accentEnd = Color(0xFFEC4899);

    final xpToNext = stats.xpForNextLevel - stats.totalXp;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.75, 0.92],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: accentStart.withValues(alpha: 0.18),
                blurRadius: 32,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accentStart, accentEnd],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '${stats.currentLevel}',
                                  style: const TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.0,
                                    letterSpacing: -2,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.white.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'LEVEL',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${stats.totalXp} total XP',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$xpToNext XP',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                            Text(
                              'to level ${stats.currentLevel + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Progress bar
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${stats.xpProgress} / ${stats.xpNeeded} XP',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.80),
                              ),
                            ),
                            Text(
                              '${(stats.levelProgress * 100).round()}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.90),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        AnimatedBuilder(
                          animation: _barAnim,
                          builder: (context, _) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Stack(
                                children: [
                                  Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.white
                                          .withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor:
                                        (stats.levelProgress * _barAnim.value)
                                            .clamp(0.0, 1.0),
                                    child: Container(
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.92),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Scrollable body
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    // XP rate info
                    _XpRateCard(scheme: scheme),
                    const SizedBox(height: 20),
                    // Recent sessions XP breakdown
                    _SectionLabel(label: 'Recents Sessions XP'),
                    const SizedBox(height: 10),
                    if (_loading)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accentStart,
                          ),
                        ),
                      )
                    else if (_recentXp == null || _recentXp!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Koi session nahi mila.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      ..._recentXp!.map(
                        (row) => _SessionXpTile(row: row),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _XpRateCard extends StatelessWidget {
  const _XpRateCard({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFA855F7).withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'XP Rates',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _RatePill(
                icon: Icons.accessibility_new_rounded,
                label: 'Training',
                rate: '8 XP / min',
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 10),
              _RatePill(
                icon: Icons.graphic_eq_rounded,
                label: 'Therapy',
                rate: '12 XP / min',
                color: const Color(0xFF06B6D4),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Min 5 XP per session. Level = √(totalXP / 100) rounded down.',
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatePill extends StatelessWidget {
  const _RatePill({
    required this.icon,
    required this.label,
    required this.rate,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String rate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  rate,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
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

class _SessionXpTile extends StatelessWidget {
  const _SessionXpTile({required this.row});
  final _SessionXpRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        row.isTraining ? const Color(0xFF10B981) : const Color(0xFF06B6D4);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.15),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                row.isTraining
                    ? Icons.accessibility_new_rounded
                    : Icons.graphic_eq_rounded,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    '${row.duration}  ·  ${row.timeLabel}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+${row.xp} XP',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionXpRow {
  const _SessionXpRow({
    required this.label,
    required this.duration,
    required this.xp,
    required this.isTraining,
    required this.timeLabel,
  });

  final String label;
  final String duration;
  final int xp;
  final bool isTraining;
  final String timeLabel;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
