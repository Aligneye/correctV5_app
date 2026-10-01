import 'package:flutter/material.dart';
import 'package:correctv1/analytics/analytics_insights.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:correctv1/home/widgets/surface_card.dart';
import 'package:correctv1/services/session_repository.dart';
import 'package:correctv1/theme/app_theme.dart';

const String _kDailyScoreTarget = 'daily_score_target';
const int kDefaultDailyScoreTarget = 70;
const int kMinDailyScoreTarget = 70;
const int kMaxDailyScoreTarget = 95;

Future<int> loadDailyScoreTarget() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_kDailyScoreTarget) ?? kDefaultDailyScoreTarget)
        .clamp(kMinDailyScoreTarget, kMaxDailyScoreTarget);
  } catch (_) {
    return kDefaultDailyScoreTarget;
  }
}

Future<void> saveDailyScoreTarget(int value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kDailyScoreTarget, value);
}

/// "25% fewer" style label; [lowerIsBetter] flips the good/bad colour.
({String text, bool good})? changeLabel(
  double? pct, {
  required String up,
  required String down,
  bool lowerIsBetter = false,
}) {
  if (pct == null) return null;
  final rounded = pct.round();
  if (rounded == 0) return (text: 'Same as yesterday', good: true);
  final increased = rounded > 0;
  return (
    text: '${rounded.abs()}% ${increased ? up : down} than yesterday',
    good: increased != lowerIsBetter,
  );
}

class DailyProgressPage extends StatefulWidget {
  const DailyProgressPage({
    super.key,
    required this.stats,
    required this.target,
  });

  final TodayStats? stats;
  final int target;

  @override
  State<DailyProgressPage> createState() => _DailyProgressPageState();
}

class _DailyProgressPageState extends State<DailyProgressPage> {
  late int _target = widget.target;
  List<DailyProgress>? _days;

  @override
  void initState() {
    super.initState();
    SessionRepository()
        .fetchDailyProgress(7)
        .then((d) => mounted ? setState(() => _days = d) : null)
        .catchError((_) => mounted ? setState(() => _days = const []) : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.stats;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_target);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Daily progress')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            HomeSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Today vs yesterday', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _compareRow(context, 'Posture score',
                      s?.hasTodayPostureData == true ? '${s!.todayPct}%' : '—',
                      s?.yesterdayHasPostureData == true ? '${s!.yesterdayPct}%' : '—'),
                  _compareRow(context, 'Slouches / day',
                      s?.hasTodayPostureData == true ? '${s!.todaySlouchCount}' : '—',
                      s?.yesterdayHasPostureData == true ? '${s!.yesterdaySlouchCount}' : '—'),
                  _compareRow(context, 'Slouches / hour',
                      s?.hasTodayPostureData == true ? s!.todaySlouchPerHour.toStringAsFixed(1) : '—',
                      s?.yesterdayHasPostureData == true ? s!.yesterdaySlouchPerHour.toStringAsFixed(1) : '—'),
                  _compareRow(context, 'Posture time',
                      _fmtDur(s?.todayPostureDurationSec ?? 0),
                      _fmtDur(s?.yesterdayPostureDurationSec ?? 0)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            HomeSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Daily score target',
                            style: theme.textTheme.titleMedium),
                      ),
                      Text('$_target%',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Slider(
                    value: _target.toDouble(),
                    min: kMinDailyScoreTarget.toDouble(),
                    max: kMaxDailyScoreTarget.toDouble(),
                    divisions: (kMaxDailyScoreTarget - kMinDailyScoreTarget) ~/ 5,
                    activeColor: const Color(0xFFA855F7),
                    label: '$_target%',
                    onChanged: (v) => setState(() => _target = v.round()),
                    onChangeEnd: (v) => saveDailyScoreTarget(v.round()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            HomeSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last 7 days', style: theme.textTheme.titleMedium),
                  if (_days != null)
                    if (PeriodSummary.of(_days!, _target) case final p
                        when p.hasData)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Avg ${p.slouchPerDay!.round()} slouches / day'
                          '  ·  ${p.slouchPerHour!.toStringAsFixed(1)} / hour',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                  const SizedBox(height: 8),
                  if (_days == null)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    for (final d in _days!.reversed) _dayRow(context, d),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compareRow(BuildContext context, String label, String today, String yesterday) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          SizedBox(
            width: 64,
            child: Text(today,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            width: 64,
            child: Text(yesterday,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          ),
        ],
      ),
    );
  }

  Widget _dayRow(BuildContext context, DailyProgress d) {
    final theme = Theme.of(context);
    final met = d.hasData && d.score >= _target;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text('${weekdays[d.date.weekday - 1]} ${d.date.day}',
                style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              d.hasData ? '${d.score}%  ·  ${d.slouchCount} slouches' : 'No posture session',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: d.hasData
                    ? null
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          if (met)
            const Icon(Icons.check_circle_rounded,
                size: 20, color: AppTheme.goodPostureEnd),
        ],
      ),
    );
  }

  static String _fmtDur(int sec) {
    if (sec <= 0) return '—';
    final m = sec ~/ 60;
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
  }
}

const String _kTargetCelebratedDay = 'daily_target_celebrated_day';

/// Shows a one-time-per-day popup once today's score reaches [target].
Future<void> maybeCelebrateDailyTarget(
  BuildContext context,
  TodayStats? stats,
  int target,
) async {
  if (stats == null || !stats.hasTodayPostureData || stats.todayPct < target) {
    return;
  }
  final now = DateTime.now();
  final todayKey = '${now.year}-${now.month}-${now.day}';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(_kTargetCelebratedDay) == todayKey) return;
  await prefs.setString(_kTargetCelebratedDay, todayKey);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF0D1A1D),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 400),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: const Text('🎯', style: TextStyle(fontSize: 56)),
            ),
            const SizedBox(height: 12),
            const Text('Daily target reached!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Posture score ${stats.todayPct}% (target $target%). Keep it up!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFA855F7), Color(0xFFEC4899)]),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Awesome',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
