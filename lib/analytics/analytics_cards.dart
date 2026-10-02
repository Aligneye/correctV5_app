import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:correctv1/analytics/analytics_insights.dart';
import 'package:correctv1/analytics/analytics_screen.dart';
import 'package:correctv1/home/widgets/surface_card.dart';
import 'package:correctv1/services/session_repository.dart';
import 'package:correctv1/theme/app_theme.dart';

const kAnalyticsPurple = Color(0xFFA855F7);
const kAnalyticsPink = Color(0xFFEC4899);
const _brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kAnalyticsPurple, kAnalyticsPink],
);
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dayLabel(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day}';
String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String formatWornTime(int sec) {
  final m = sec ~/ 60;
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${m % 60}m';
}

Color _muted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

// ─── Period chips ────────────────────────────────────────────────────────────

class PeriodChips extends StatelessWidget {
  const PeriodChips({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  gradient: i == selected ? _brandGradient : null,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: i == selected ? Colors.white : _muted(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Hero ────────────────────────────────────────────────────────────────────

class AnalyticsHeroCard extends StatelessWidget {
  const AnalyticsHeroCard({
    super.key,
    required this.current,
    required this.previous,
    required this.previousLabel,
  });

  final PeriodSummary current;
  final PeriodSummary previous;

  /// e.g. "last week".
  final String previousLabel;

  @override
  Widget build(BuildContext context) {
    final score = current.score;
    final prevScore = previous.score;

    final String sentence;
    if (score == null) {
      sentence = 'No posture sessions in this period yet';
    } else if (prevScore == null || prevScore == 0) {
      sentence = 'Great start, keep wearing your pod 💪';
    } else {
      final pct = ((score - prevScore) / prevScore * 100).round();
      sentence = pct == 0
          ? 'Same as $previousLabel'
          : pct > 0
              ? '$pct% better than $previousLabel 👍'
              : '${pct.abs()}% lower than $previousLabel, you can fix it!';
    }

    int? pctChange(double? now, double? prev) =>
        now != null && prev != null && prev > 0
            ? ((now - prev) / prev * 100).round()
            : null;
    final slouchNow = current.slouchPerHour;
    final slouchDelta = pctChange(slouchNow, previous.slouchPerHour);
    final perDayNow = current.slouchPerDay;
    final perDayDelta = pctChange(perDayNow, previous.slouchPerDay);
    final wornDeltaMin = previous.hasData
        ? (current.postureSec - previous.postureSec) ~/ 60
        : null;
    final targetDelta =
        previous.hasData ? current.targetDays - previous.targetDays : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        gradient: _brandGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: [
          BoxShadow(
            color: kAnalyticsPurple.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (score ?? 0).toDouble()),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text(
                  score == null ? '—' : '${v.round()}%',
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.0,
                    letterSpacing: -1.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'avg posture\nscore',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sentence,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 14),
          Row(
            children: [
              _HeroStat(
                value: perDayNow == null ? '—' : perDayNow.round().toString(),
                label: 'slouches / day',
                delta: perDayDelta == null
                    ? null
                    : '${perDayDelta <= 0 ? '↓' : '↑'}${perDayDelta.abs()}%',
                good: (perDayDelta ?? 0) <= 0,
              ),
              _HeroStat(
                value: slouchNow == null ? '—' : slouchNow.toStringAsFixed(1),
                label: 'slouches / hr',
                delta: slouchDelta == null
                    ? null
                    : '${slouchDelta <= 0 ? '↓' : '↑'}${slouchDelta.abs()}%',
                good: (slouchDelta ?? 0) <= 0,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _HeroStat(
                value: current.hasData ? formatWornTime(current.postureSec) : '—',
                label: 'worn time',
                delta: wornDeltaMin == null
                    ? null
                    : '${wornDeltaMin >= 0 ? '↑' : '↓'}'
                        '${formatWornTime(wornDeltaMin.abs() * 60)}',
                good: (wornDeltaMin ?? 0) >= 0,
              ),
              _HeroStat(
                value: '${current.targetDays}/${current.days}',
                label: 'target days',
                delta: targetDelta == null
                    ? null
                    : '${targetDelta >= 0 ? '↑' : '↓'}${targetDelta.abs()}',
                good: (targetDelta ?? 0) >= 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    required this.delta,
    required this.good,
  });

  final String value;
  final String label;
  final String? delta;
  final bool good;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          if (delta != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: good ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$delta${good ? '' : ' ⚠'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Section card shell ──────────────────────────────────────────────────────

class AnalyticsSection extends StatelessWidget {
  const AnalyticsSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomeSurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(fontSize: 13, color: _muted(context))),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ─── Score trend ─────────────────────────────────────────────────────────────

class ScoreTrendChart extends StatelessWidget {
  const ScoreTrendChart({
    super.key,
    required this.days,
    required this.target,
    required this.onDayTap,
  });

  final List<DailyProgress> days;
  final int target;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final muted = _muted(context);
    final grid = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    final spots = [
      for (var i = 0; i < days.length; i++)
        days[i].hasData
            ? FlSpot(i.toDouble(), days[i].score.toDouble())
            : FlSpot.nullSpot,
    ];
    final labelEvery = days.length <= 7 ? 1 : (days.length / 5).ceil();

    return SizedBox(
      height: 190,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (days.length - 1).toDouble(),
          minY: 0,
          maxY: 100,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: grid, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(
              y: target.toDouble(),
              color: kAnalyticsPink.withValues(alpha: 0.7),
              strokeWidth: 1.5,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: kAnalyticsPink,
                ),
                labelResolver: (_) => 'Target $target%',
              ),
            ),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 25,
                getTitlesWidget: (v, _) => Text(
                  '${v.toInt()}',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= days.length || v != i) {
                    return const SizedBox.shrink();
                  }
                  if ((days.length - 1 - i) % labelEvery != 0) {
                    return const SizedBox.shrink();
                  }
                  final d = days[i].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      days.length <= 7
                          ? _weekdays[d.weekday - 1].substring(0, 1)
                          : _shortDate(d),
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchSpotThreshold: 20,
            touchCallback: (event, response) {
              if (event is! FlTapUpEvent) return;
              final spot = response?.lineBarSpots?.firstOrNull;
              if (spot == null) return;
              onDayTap(days[spot.x.toInt()].date);
            },
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1F1B2E),
              tooltipBorderRadius: BorderRadius.circular(10),
              getTooltipItems: (touched) => [
                for (final t in touched)
                  LineTooltipItem(
                    '${_dayLabel(days[t.x.toInt()].date)}\n',
                    const TextStyle(color: Colors.white70, fontSize: 11),
                    children: [
                      TextSpan(
                        text: '${t.y.toInt()}%  ·  '
                            '${days[t.x.toInt()].slouchCount} slouches',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              barWidth: 3,
              gradient: _brandGradient,
              dotData: FlDotData(
                show: days.length <= 31,
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: spot.y >= target
                      ? kAnalyticsPurple
                      : AppTheme.destructive,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    kAnalyticsPurple.withValues(alpha: 0.25),
                    kAnalyticsPurple.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

// ─── Slouch by hour ──────────────────────────────────────────────────────────

class SlouchHoursChart extends StatelessWidget {
  const SlouchHoursChart({super.key, required this.insights});

  final SlouchInsights insights;

  @override
  Widget build(BuildContext context) {
    final muted = _muted(context);
    final peak = insights.peakStartHour;
    final maxY = math.max(1, insights.byHour.reduce(math.max)).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (peak != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: kAnalyticsPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: '💡 You slouch most between '),
                TextSpan(
                  text: '${formatHour(peak)} – ${formatHour(peak + 2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const TextSpan(text: '. Plan a quick stretch break then.'),
              ]),
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        SizedBox(
          height: 140,
          child: BarChart(
            BarChartData(
              maxY: maxY * 1.15,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, _) {
                      final h = v.toInt();
                      if (h % 6 != 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          formatHour(h),
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF1F1B2E),
                  tooltipBorderRadius: BorderRadius.circular(10),
                  getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                    '${formatHour(group.x)}\n',
                    const TextStyle(color: Colors.white70, fontSize: 11),
                    children: [
                      TextSpan(
                        text: '${rod.toY.toInt()} slouches',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              barGroups: [
                for (var h = 0; h < 24; h++)
                  BarChartGroupData(x: h, barRods: [
                    BarChartRodData(
                      toY: insights.byHour[h].toDouble(),
                      width: 7,
                      borderRadius: BorderRadius.circular(3),
                      gradient: peak != null &&
                              (h == peak || h == (peak + 1) % 24)
                          ? const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [kAnalyticsPurple, kAnalyticsPink],
                            )
                          : null,
                      color: kAnalyticsPurple.withValues(alpha: 0.3),
                    ),
                  ]),
              ],
            ),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          ),
        ),
      ],
    );
  }
}

// ─── Highlights ──────────────────────────────────────────────────────────────

class HighlightsList extends StatelessWidget {
  const HighlightsList({
    super.key,
    required this.days,
    required this.summary,
    required this.insights,
    required this.onDayTap,
  });

  final List<DailyProgress> days;
  final PeriodSummary summary;
  final SlouchInsights insights;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final withData = days.where((d) => d.hasData).toList();
    final best = withData.isEmpty
        ? null
        : withData.reduce((a, b) => b.score >= a.score ? b : a);
    final fix = insights.avgCorrectionSec;

    return Column(
      children: [
        if (best != null)
          _HighlightRow(
            emoji: '🏆',
            title: 'Best day',
            value: '${_dayLabel(best.date)} · ${best.score}%',
            onTap: () => onDayTap(best.date),
          ),
        _HighlightRow(
          emoji: '🎯',
          title: 'Target met',
          value: '${summary.targetDays} of ${summary.activeDays} active days',
        ),
        if (fix != null)
          _HighlightRow(
            emoji: '⏱',
            title: 'You straighten up in',
            value: '${fix.round()}s on average',
          ),
      ],
    );
  }
}

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({
    required this.emoji,
    required this.title,
    required this.value,
    this.onTap,
  });

  final String emoji;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kAnalyticsPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: 12, color: _muted(context))),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: _muted(context)),
          ],
        ),
      ),
    );
  }
}

// ─── Day sessions sheet ──────────────────────────────────────────────────────

Future<void> showDaySessionsSheet(BuildContext context, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  final future = SessionRepository()
      .fetchSessionsBetween(start, DateTime(day.year, day.month, day.day + 1));
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: FutureBuilder<List<SessionData>>(
        future: future,
        builder: (context, snap) {
          final sessions = snap.data;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dayLabel(day),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (sessions == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (sessions.isEmpty)
                  Text('No sessions on this day',
                      style: TextStyle(color: _muted(context)))
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final s in sessions)
                          _DaySessionRow(
                            session: s,
                            onTap: () => showSessionDetailSheet(
                              sheetContext,
                              session: s,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _DaySessionRow extends StatelessWidget {
  const _DaySessionRow({required this.session, required this.onTap});

  final SessionData session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPosture = session.type == SessionType.posture;
    final ts = session.startTs;
    final time = ts == null
        ? ''
        : '${formatHour(ts.hour).split(' ').first}:'
            '${ts.minute.toString().padLeft(2, '0')} '
            '${ts.hour < 12 ? 'AM' : 'PM'}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: isPosture ? _brandGradient : AppTheme.therapyGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          isPosture ? Icons.accessibility_new_rounded : Icons.spa_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
      title: Text(
        isPosture ? 'Posture training' : 'Therapy',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('$time · ${session.duration}'),
      trailing: isPosture
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${session.score ?? 0}%',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                Text('${session.alerts ?? 0} slouches',
                    style: TextStyle(fontSize: 11, color: _muted(context))),
              ],
            )
          : const Icon(Icons.chevron_right_rounded),
    );
  }
}
