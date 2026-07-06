import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:correctv1/services/session_repository.dart';
import 'package:correctv1/home/widgets/streak_calendar_widget.dart';

void showStreakDetailSheet(
  BuildContext context, {
  required StreakStats streakStats,
  required SessionRepository repository,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StreakDetailSheet(
      streakStats: streakStats,
      repository: repository,
    ),
  );
}

class _StreakDetailSheet extends StatefulWidget {
  const _StreakDetailSheet({
    required this.streakStats,
    required this.repository,
  });

  final StreakStats streakStats;
  final SessionRepository repository;

  @override
  State<_StreakDetailSheet> createState() => _StreakDetailSheetState();
}

class _StreakDetailSheetState extends State<_StreakDetailSheet> {
  List<int>? _calendarStates;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final states = await widget.repository.fetchStreakCalendar(
        35,
        freezeUsedDays: widget.streakStats.freezeUsedDays,
      );
      if (!mounted) return;
      setState(() {
        _calendarStates = states;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = widget.streakStats;
    final palette = _paletteForDays(stats.currentStreak);

    // Next milestone CTA
    final int? nextMilestone = _nextMilestone(stats.currentStreak);
    final String ctaText = nextMilestone != null
        ? '${nextMilestone - stats.currentStreak} din aur — ${_milestoneLabel(nextMilestone)} milestone!'
        : 'Legendary streak! Jaari rakho.';

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.72, 0.92],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.18),
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
              // Header strip with gradient
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [palette.bgStart, palette.bgMid, palette.bgEnd],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${stats.currentStreak}',
                          style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.0,
                            letterSpacing: -2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Streak Days',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (stats.todayActive) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '✓ Aaj active',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Best',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          '${stats.highestStreak}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                            letterSpacing: -1,
                          ),
                        ),
                        const Text(
                          'days',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                          ),
                        ),
                        if (stats.freezeTokens > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.ac_unit_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${stats.freezeTokens} freeze',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                    // CTA motivational text
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.bgStart.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: palette.bgStart.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            nextMilestone != null ? '🎯' : '🏆',
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              ctaText,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: palette.bgEnd,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Freeze info row
                    if (stats.freezeTokens > 0 ||
                        stats.freezeUsedDays.isNotEmpty) ...[
                      _SectionLabel(label: 'Streak Shield'),
                      const SizedBox(height: 10),
                      _FreezeInfoCard(
                        tokens: stats.freezeTokens,
                        usedCount: stats.freezeUsedDays.length,
                        accentColor: palette.bgMid,
                      ),
                      const SizedBox(height: 20),
                    ],
                    // Calendar
                    _SectionLabel(label: 'Pichle 35 Din'),
                    const SizedBox(height: 10),
                    _loading
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.bgMid,
                              ),
                            ),
                          )
                        : StreakCalendarWidget(
                            dayStates: _calendarStates ?? List.filled(35, 0),
                            activeStart: palette.bgStart,
                            activeEnd: palette.bgEnd,
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

class _FreezeInfoCard extends StatelessWidget {
  const _FreezeInfoCard({
    required this.tokens,
    required this.usedCount,
    required this.accentColor,
  });

  final int tokens;
  final int usedCount;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.ac_unit_rounded,
                  size: 18,
                  color: Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Streak Freeze',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    'Miss hone par streak protect karta hai',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _FreezeStat(
                value: '$tokens',
                label: 'Available',
                color: const Color(0xFF38BDF8),
              ),
              const SizedBox(width: 16),
              _FreezeStat(
                value: '$usedCount',
                label: 'Used total',
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              _FreezeStat(
                value: '5',
                label: 'Max cap',
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Har 7-day milestone pe +1 freeze token milta hai.',
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

class _FreezeStat extends StatelessWidget {
  const _FreezeStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.0,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// Minimal palette struct (mirrors _StreakPalette in stats_summary_card.dart)
class _Palette {
  const _Palette(this.bgStart, this.bgMid, this.bgEnd, this.shadow);
  final Color bgStart;
  final Color bgMid;
  final Color bgEnd;
  final Color shadow;
}

// Uses the same logic as _paletteForStreak in stats_summary_card.dart
_Palette _paletteForDays(int days) {
  if (days <= 0) {
    return const _Palette(
      Color(0xFF94A3B8),
      Color(0xFF64748B),
      Color(0xFF334155),
      Color(0xFF64748B),
    );
  }
  const palettes = <_Palette>[
    _Palette(Color(0xFF60A5FA), Color(0xFF3B82F6), Color(0xFF1D4ED8), Color(0xFF3B82F6)),
    _Palette(Color(0xFF818CF8), Color(0xFF6366F1), Color(0xFF4338CA), Color(0xFF6366F1)),
    _Palette(Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF6D28D9), Color(0xFF8B5CF6)),
    _Palette(Color(0xFFC084FC), Color(0xFFA855F7), Color(0xFF7E22CE), Color(0xFFA855F7)),
    _Palette(Color(0xFFE879F9), Color(0xFFD946EF), Color(0xFFA21CAF), Color(0xFFD946EF)),
    _Palette(Color(0xFFF472B6), Color(0xFFEC4899), Color(0xFFBE185D), Color(0xFFEC4899)),
    _Palette(Color(0xFFFB7185), Color(0xFFF43F5E), Color(0xFFBE123C), Color(0xFFF43F5E)),
    _Palette(Color(0xFFF87171), Color(0xFFEF4444), Color(0xFFB91C1C), Color(0xFFEF4444)),
    _Palette(Color(0xFFFB923C), Color(0xFFF97316), Color(0xFFC2410C), Color(0xFFF97316)),
    _Palette(Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFB45309), Color(0xFFF59E0B)),
  ];
  return palettes[(days - 1) % palettes.length];
}

int? _nextMilestone(int current) {
  const milestones = [7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300, 365];
  for (final m in milestones) {
    if (m > current) return m;
  }
  return null;
}

String _milestoneLabel(int days) {
  const labels = {
    7: '7-day',
    14: '2-week',
    21: '3-week',
    30: '30-day',
    50: '50-day',
    75: '75-day',
    100: '100-day',
    150: '150-day',
    200: '200-day',
    250: '250-day',
    300: '300-day',
    365: '1-year',
  };
  return labels[days] ?? '$days-day';
}
