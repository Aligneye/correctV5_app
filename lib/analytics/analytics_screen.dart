import 'package:flutter/material.dart';
import 'package:correctv1/analytics/analytics_cards.dart';
import 'package:correctv1/analytics/analytics_insights.dart';
import 'package:correctv1/home/daily_progress_page.dart';
import 'package:correctv1/services/device_manager.dart';
import 'package:correctv1/services/session_repository.dart';
import 'package:correctv1/services/therapy_pattern_names.dart';
import 'package:correctv1/sessions/sessions_history_page.dart';
import 'package:correctv1/theme/app_theme.dart';

// ─── Data Models ─────────────────────────────────────────────────────────────

enum SessionType { posture, therapy }

/// One slouch -> correction pair from the firmware's session_log event file.
/// `slouchSec` is the offset from session start where bad posture began;
/// `correctionSec` is when it was corrected. The firmware sentinel `0xFFFF`
/// (== [PostureEvent.uncorrected]) means the user was still slouching when
/// the session ended.
class PostureEvent {
  final int slouchSec;
  final int correctionSec;

  const PostureEvent({required this.slouchSec, required this.correctionSec});

  static const int uncorrected = 0xFFFF;

  bool get wasCorrected => correctionSec != uncorrected;

  int get durationSec {
    if (!wasCorrected) return 0;
    final d = correctionSec - slouchSec;
    return d > 0 ? d : 0;
  }

  Map<String, dynamic> toJson() => {'s': slouchSec, 'c': correctionSec};

  factory PostureEvent.fromJson(Map<String, dynamic> json) => PostureEvent(
    slouchSec: (json['s'] as num?)?.toInt() ?? 0,
    correctionSec: (json['c'] as num?)?.toInt() ?? uncorrected,
  );
}

class TherapyPatternEvent {
  final int patternIndex;
  final int startOffsetSec;
  final int durationSec;

  const TherapyPatternEvent({
    required this.patternIndex,
    required this.startOffsetSec,
    required this.durationSec,
  });

  int get endOffsetSec => startOffsetSec + durationSec;

  Map<String, dynamic> toJson() => {
    'p': patternIndex,
    's': startOffsetSec,
    'd': durationSec,
  };

  factory TherapyPatternEvent.fromJson(Map<String, dynamic> json) {
    int readInt(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is num) return value.toInt();
        final parsed = int.tryParse(value?.toString() ?? '');
        if (parsed != null) return parsed;
      }
      return 0;
    }

    return TherapyPatternEvent(
      patternIndex: readInt(['p', 'pattern', 'pattern_index']),
      startOffsetSec: readInt(['s', 'start', 'start_sec', 'offset_sec']),
      durationSec: readInt(['d', 'duration', 'duration_sec']),
    );
  }
}

class SessionData {
  final int id;
  final String? dbId;
  final SessionType type;
  final String name;
  final String time;
  final String date;
  final String duration;
  final int durationSec;
  final int? alerts;
  final int? score;
  final int? pattern;
  final int? wrongDurSec;
  final bool isLive;
  final bool tsSynced;
  final bool cloudSynced;
  final DateTime? startTs;
  final List<PostureEvent>? postureEvents;
  final List<int>? therapyPatterns;
  final List<TherapyPatternEvent>? therapyPatternEvents;

  const SessionData({
    required this.id,
    this.dbId,
    required this.type,
    required this.name,
    required this.time,
    required this.date,
    required this.duration,
    required this.durationSec,
    this.alerts,
    this.score,
    this.pattern,
    this.wrongDurSec,
    this.isLive = false,
    this.tsSynced = true,
    this.cloudSynced = true,
    this.startTs,
    this.postureEvents,
    this.therapyPatterns,
    this.therapyPatternEvents,
  });
}

// ─── Palette (used by session detail below) ──────────────────────────────────

const _kBlue = AppTheme.brandPrimary; // #2563EB
const _kGreen = AppTheme.successText; // #16A34A
const _kGreenLight = AppTheme.successBg; // #F0FDF4
const _kRed = AppTheme.destructive; // #EF4444

const _kCardShadow = [
  BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x05000000), blurRadius: 2, offset: Offset(0, 1)),
];

BoxDecoration _cardDecoration(ColorScheme scheme, {double radius = 16}) =>
    BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: scheme.outline, width: 0.5),
      boxShadow: _kCardShadow,
    );

// ─── Analytics Screen ────────────────────────────────────────────────────────

class AnalyticsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const AnalyticsScreen({super.key, this.onBack});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  static const _periodLabels = ['7D', '30D'];
  static const _periodDays = [7, 30];
  static const _previousLabels = ['last week', 'last month'];

  final SessionRepository _repo = SessionRepository();
  final DeviceManager _deviceManager = DeviceManager();

  int _period = 0;
  int _target = kDefaultDailyScoreTarget;
  List<DailyProgress>? _current;
  List<DailyProgress>? _previous;
  SlouchInsights? _insights;
  int _lastSyncTick = 0;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _lastSyncTick = _deviceManager.syncCompletedTick.value;
    _deviceManager.syncCompletedTick.addListener(_onSyncFinished);
    _deviceManager.isSyncing.addListener(_onSyncingChanged);
    _load();
  }

  @override
  void dispose() {
    _deviceManager.syncCompletedTick.removeListener(_onSyncFinished);
    _deviceManager.isSyncing.removeListener(_onSyncingChanged);
    super.dispose();
  }

  void _onSyncFinished() {
    final tick = _deviceManager.syncCompletedTick.value;
    if (tick == _lastSyncTick) return;
    _lastSyncTick = tick;
    Future<void>.delayed(const Duration(milliseconds: 400), _load);
  }

  void _onSyncingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    final seq = ++_loadSeq;
    final n = _periodDays[_period];
    final now = DateTime.now();
    try {
      final results = await Future.wait([
        _repo.fetchDailyProgress(n * 2),
        _repo.fetchSessionsBetween(
          DateTime(now.year, now.month, now.day - (n - 1)),
          DateTime(now.year, now.month, now.day + 1),
        ),
        loadDailyScoreTarget(),
      ]);
      // Ignore results from a period the user already switched away from.
      if (!mounted || seq != _loadSeq) return;
      final days = results[0] as List<DailyProgress>;
      setState(() {
        _previous = days.sublist(0, n);
        _current = days.sublist(n);
        _insights = SlouchInsights.of(results[1] as List<SessionData>);
        _target = results[2] as int;
      });
    } catch (e) {
      debugPrint('Analytics load failed: $e');
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _previous = const [];
        _current = const [];
        _insights = SlouchInsights.of(const []);
      });
    }
  }

  void _selectPeriod(int i) {
    if (i == _period) return;
    setState(() => _period = i);
    _load();
  }

  void _openDay(DateTime day) => showDaySessionsSheet(context, day);

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final previous = _previous;
    final insights = _insights;
    final loaded = current != null && previous != null && insights != null;
    final summary = loaded ? PeriodSummary.of(current, _target) : null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_deviceManager.isSyncing.value) _buildSyncingBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    if (!loaded)
                      const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        child: KeyedSubtree(
                          key: ValueKey(_period),
                          child: summary!.hasData
                              ? _buildContent(current, previous, insights, summary)
                              : _buildEmptyState(),
                        ),
                      ),
                    const SizedBox(height: 8),
                    _buildAllSessionsLink(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.arrow_back_rounded, color: scheme.onSurfaceVariant),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        const SizedBox(width: 4),
        const Expanded(
          child: Text(
            'Your posture',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        PeriodChips(
          labels: _periodLabels,
          selected: _period,
          onChanged: _selectPeriod,
        ),
      ],
    );
  }

  Widget _buildContent(
    List<DailyProgress> current,
    List<DailyProgress> previous,
    SlouchInsights insights,
    PeriodSummary summary,
  ) {
    return Column(
      children: [
        AnalyticsHeroCard(
          current: summary,
          previous: PeriodSummary.of(previous, _target),
          previousLabel: _previousLabels[_period],
        ),
        const SizedBox(height: 16),
        AnalyticsSection(
          title: 'Score trend',
          subtitle: 'Tap a day to see its sessions',
          child: ScoreTrendChart(
            days: current,
            target: _target,
            onDayTap: _openDay,
          ),
        ),
        const SizedBox(height: 16),
        AnalyticsSection(
          title: 'When do you slouch?',
          subtitle: insights.total == 0
              ? 'No slouches recorded in this period 🎉'
              : '${insights.total} slouches by time of day',
          child: insights.total == 0
              ? const SizedBox.shrink()
              : SlouchHoursChart(insights: insights),
        ),
        const SizedBox(height: 16),
        AnalyticsSection(
          title: 'Highlights',
          child: HighlightsList(
            days: current,
            summary: summary,
            insights: insights,
            onDayTap: _openDay,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return AnalyticsSection(
      title: 'No data yet',
      child: Column(
        children: [
          const Text('📈', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(
            'Wear your pod for a posture session and your insights will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, height: 1.4),
          ),
          if (widget.onBack != null) ...[
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kAnalyticsPurple, kAnalyticsPink],
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: TextButton(
                onPressed: widget.onBack,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text(
                  'Start a session',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildAllSessionsLink() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.history_rounded),
      title: const Text(
        'All sessions',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SessionsHistoryPage()),
      ),
    );
  }

  Widget _buildSyncingBanner() {
    return Container(
      width: double.infinity,
      color: kAnalyticsPurple.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: const Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              valueColor: AlwaysStoppedAnimation<Color>(kAnalyticsPurple),
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Syncing…',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: kAnalyticsPurple,
            ),
          ),
        ],
      ),
    );
  }
}


// ─── Session Detail Screen ────────────────────────────────────────────────────

class SessionDetailScreen extends StatelessWidget {
  final SessionData session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPosture = session.type == SessionType.posture;
    return Scaffold(
      backgroundColor: null,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chevron_left_rounded, color: _kBlue, size: 28),
            ],
          ),
        ),
        title: Text(
          isPosture ? 'Posture session' : 'Therapy session',
          style: const TextStyle(
            fontSize: 14,
            color: _kBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: scheme.outline),
        ),
      ),
      body: _SessionDetailBody(session: session),
    );
  }
}

Future<void> showSessionDetailSheet(
  BuildContext context, {
  required SessionData session,
}) {
  final isPosture = session.type == SessionType.posture;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        initialChildSize: 0.86,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (_, scrollController) {
          final scheme = Theme.of(sheetContext).colorScheme;
          return Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isPosture ? 'Posture session' : 'Therapy session',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: scheme.onSurfaceVariant,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _SessionDetailBody(
                    session: session,
                    controller: scrollController,
                    bottomPadding: 28,
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _SessionDetailBody extends StatelessWidget {
  final SessionData session;
  final ScrollController? controller;
  final double bottomPadding;

  const _SessionDetailBody({
    required this.session,
    this.controller,
    this.bottomPadding = 40,
  });

  @override
  Widget build(BuildContext context) {
    final isPosture = session.type == SessionType.posture;
    final accent = isPosture ? _kBlue : _kGreen;
    final lastPatternIndex =
        session.therapyPatternEvents
            ?.where((event) => event.durationSec > 0)
            .lastOrNull
            ?.patternIndex ??
        session.therapyPatternEvents?.lastOrNull?.patternIndex ??
        session.therapyPatterns?.lastOrNull ??
        session.pattern;
    final patternName = lastPatternIndex == null
        ? 'Unknown'
        : therapyPatternName(lastPatternIndex);
    final patternDescription = lastPatternIndex == null
        ? null
        : therapyPatternDescription(lastPatternIndex);

    return SingleChildScrollView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(14, 14, 14, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isPosture
                    ? const [Color(0xFF2F7BFF), Color(0xFF08B4CB)]
                    : const [Color(0xFF22C55E), Color(0xFF0EA5E9)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2A0EA5E9),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPosture ? '${session.score ?? 0}%' : patternName,
                        style: TextStyle(
                          fontSize: isPosture ? 56 : 34,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPosture
                            ? 'Good posture score'
                            : 'Last vibration pattern',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!isPosture && patternDescription != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          patternDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.78),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isPosture
                        ? Icons.accessibility_new_rounded
                        : Icons.graphic_eq,
                    size: 30,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          if (!session.tsSynced) ...[
            const SizedBox(height: 12),
            _UnsyncedBanner(),
          ],

          const SizedBox(height: 14),
          _label('Session details', context),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DetailStat(
                      value: session.duration,
                      label: 'Duration',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DetailStat(
                      value: isPosture
                          ? _formatDateTimeLong(session.startTs) ?? session.date
                          : _formatDateLong(session.startTs) ?? session.date,
                      label: isPosture ? 'Started' : 'Date',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (isPosture) ...[
                    Expanded(
                      child: _DetailStat(
                        value: '${session.alerts ?? 0}×',
                        label: 'Vibration alerts',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DetailStat(
                        value: _formatBadDuration(session),
                        label: 'Bad posture',
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: _DetailStat(
                        value: '${_therapyPatternCount(session)}',
                        label: 'Patterns played',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DetailStat(
                        value: _formatStartTime(session.startTs) ?? '—',
                        label: 'Started',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          if (isPosture) ...[
            Builder(
              builder: (context) {
                final postureEvents = _postureEventsForSession(session);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Session timeline', context),
                    _PostureTimelineCard(
                      session: session,
                      precomputedEvents: postureEvents,
                    ),
                    _label('Slouch events', context),
                    _PostureEventsList(
                      session: session,
                      precomputedEvents: postureEvents,
                    ),
                  ],
                );
              },
            ),
          ] else ...[
            _label('Patterns played', context),
            _TherapyPatternsCard(session: session, accent: accent),
          ],
        ],
      ),
    );
  }

  Widget _label(String text, BuildContext ctx) {
    final scheme = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10, left: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  static String _formatBadDuration(SessionData session) {
    final wrong = session.wrongDurSec ?? 0;
    if (wrong <= 0) return '0s';
    if (wrong < 60) return '${wrong}s';
    final m = wrong ~/ 60;
    final s = wrong % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  static String? _formatDateLong(DateTime? ts) {
    if (ts == null) return null;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[ts.month - 1]} ${ts.day}';
  }

  static String? _formatDateTimeLong(DateTime? ts) {
    final date = _formatDateLong(ts);
    final time = _formatStartTime(ts);
    if (date == null || time == null) return null;
    return '$time, $date';
  }

  static String? _formatStartTime(DateTime? ts) {
    if (ts == null) return null;
    final hour = ts.hour == 0 ? 12 : (ts.hour > 12 ? ts.hour - 12 : ts.hour);
    final minute = ts.minute.toString().padLeft(2, '0');
    final ampm = ts.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  static int _therapyPatternCount(SessionData session) {
    final eventCount = session.therapyPatternEvents?.length ?? 0;
    if (eventCount > 0) return eventCount;
    final patternCount = session.therapyPatterns?.length ?? 0;
    if (patternCount > 0) return patternCount;
    return session.pattern == null ? 0 : 1;
  }
}

// ─── Unsynced time warning banner ────────────────────────────────────────────

class _UnsyncedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE2A8)),
      ),
      child: Row(
        children: const [
          Icon(Icons.history_toggle_off, size: 18, color: Color(0xFFB45309)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Recorded while the device clock was unsynced. The start time '
              'was estimated.',
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFFB45309),
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Posture timeline (real event data) ──────────────────────────────────────

class _PostureTimelineCard extends StatelessWidget {
  final SessionData session;
  final List<PostureEvent> precomputedEvents;

  const _PostureTimelineCard({
    required this.session,
    required this.precomputedEvents,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final events = precomputedEvents;
    final hasExactEvents = session.postureEvents?.isNotEmpty ?? false;
    final durationSec = session.durationSec.clamp(1, 1 << 30).toInt();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: _cardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stripe visualization
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 18,
              child: CustomPaint(
                size: Size.infinite,
                painter: _PostureStripePainter(
                  events: events,
                  totalSec: durationSec,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Time axis
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0:00',
                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
              ),
              Text(
                _formatMinSec(durationSec),
                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const _LegendDot(color: _kGreen),
              const SizedBox(width: 6),
              Text(
                'Good ${_formatMinSec((durationSec - (session.wrongDurSec ?? 0)).clamp(0, durationSec).toInt())}',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              const _LegendDot(color: _kRed),
              const SizedBox(width: 6),
              Text(
                'Bad ${_formatMinSec(session.wrongDurSec ?? 0)}',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (!hasExactEvents && events.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Timeline estimated from the saved slouch summary.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ] else if (events.isEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'No slouch events recorded — your posture stayed within range '
              'the entire session.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _PostureStripePainter extends CustomPainter {
  _PostureStripePainter({required this.events, required this.totalSec});

  final List<PostureEvent> events;
  final int totalSec;

  @override
  void paint(Canvas canvas, Size size) {
    final goodPaint = Paint()..color = const Color(0xFFD1FAE5);
    final badPaint = Paint()..color = _kRed;
    canvas.drawRect(Offset.zero & size, goodPaint);

    if (totalSec <= 0) return;
    for (final e in events) {
      final start = e.slouchSec.clamp(0, totalSec).toDouble();
      final end = e.wasCorrected
          ? e.correctionSec.clamp(0, totalSec).toDouble()
          : totalSec.toDouble();
      if (end <= start) continue;
      final x = size.width * (start / totalSec);
      final w = size.width * ((end - start) / totalSec);
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), badPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PostureStripePainter old) {
    if (old.totalSec != totalSec) return true;
    if (old.events.length != events.length) return true;
    for (int i = 0; i < events.length; i++) {
      if (old.events[i].slouchSec != events[i].slouchSec ||
          old.events[i].correctionSec != events[i].correctionSec) {
        return true;
      }
    }
    return false;
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;

  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _PostureEventsList extends StatelessWidget {
  final SessionData session;
  final List<PostureEvent> precomputedEvents;

  const _PostureEventsList({
    required this.session,
    required this.precomputedEvents,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final events = precomputedEvents;
    final hasExactEvents = session.postureEvents?.isNotEmpty ?? false;

    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: _cardDecoration(scheme),
        child: Row(
          children: [
            const Icon(Icons.shield_rounded, size: 22, color: _kGreen),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Zero slouch alerts. Picture-perfect posture.',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: _cardDecoration(scheme),
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++)
            _PostureEventRow(
              index: i + 1,
              event: events[i],
              isEstimated: !hasExactEvents,
              isLast: i == events.length - 1,
            ),
        ],
      ),
    );
  }
}

List<PostureEvent> _postureEventsForSession(SessionData session) {
  final exact = session.postureEvents;
  if (exact != null && exact.isNotEmpty) return exact;

  final count = session.alerts ?? 0;
  final totalBad = session.wrongDurSec ?? 0;
  final duration = session.durationSec;
  if (count <= 0 || duration <= 0) return const <PostureEvent>[];

  final badPerEvent = (totalBad / count).ceil().clamp(1, duration).toInt();
  final spacing = (duration / (count + 1)).floor().clamp(1, duration).toInt();
  final events = <PostureEvent>[];

  for (var i = 0; i < count; i++) {
    final preferredStart = spacing * (i + 1);
    final latestStart = (duration - badPerEvent).clamp(0, duration).toInt();
    final slouchSec = preferredStart.clamp(0, latestStart).toInt();
    final correctionSec = (slouchSec + badPerEvent)
        .clamp(slouchSec, duration)
        .toInt();
    events.add(
      PostureEvent(slouchSec: slouchSec, correctionSec: correctionSec),
    );
  }

  return events;
}

class _PostureEventRow extends StatelessWidget {
  final int index;
  final PostureEvent event;
  final bool isEstimated;
  final bool isLast;

  const _PostureEventRow({
    required this.index,
    required this.event,
    this.isEstimated = false,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final corrected = event.wasCorrected;
    final dur = event.durationSec;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : scheme.outline,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: corrected
                  ? _kRed.withValues(alpha: 0.10)
                  : _kRed.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _kRed.withValues(alpha: 0.95),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEstimated
                      ? 'Estimated slouch ${_formatMinSec(event.slouchSec)} → ${_formatMinSec(event.correctionSec)}'
                      : corrected
                      ? 'Slouched at ${_formatMinSec(event.slouchSec)} → corrected at ${_formatMinSec(event.correctionSec)}'
                      : 'Slouched at ${_formatMinSec(event.slouchSec)} (still bad at end)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  corrected
                      ? 'Bad posture for ${_formatMinSec(dur)}'
                      : 'Open-ended slouch',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: corrected ? _kGreenLight : const Color(0xFFFFE4E6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              corrected ? 'fixed' : 'open',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: corrected ? _kGreen : _kRed,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Therapy patterns card ───────────────────────────────────────────────────

class _TherapyPatternsCard extends StatelessWidget {
  final SessionData session;
  final Color accent;

  const _TherapyPatternsCard({required this.session, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final events =
        session.therapyPatternEvents ?? const <TherapyPatternEvent>[];
    final patternName = session.pattern == null
        ? null
        : therapyPatternName(session.pattern!);
    final patternDescription = session.pattern == null
        ? null
        : therapyPatternDescription(session.pattern!);

    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: _cardDecoration(scheme),
        child: Row(
          children: [
            Icon(Icons.vibration_rounded, size: 22, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                session.pattern != null
                    ? '$patternName ran for ${session.duration}. ${patternDescription ?? ''}'
                    : 'No pattern data captured for this session.',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: _cardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${events.length} pattern${events.length == 1 ? '' : 's'} '
            'in this ${session.duration} session',
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < events.length; i++)
            _TherapyPatternEventRow(
              step: i + 1,
              event: events[i],
              sessionStart: session.startTs,
              accent: accent,
              isLast: i == events.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TherapyPatternEventRow extends StatelessWidget {
  final int step;
  final TherapyPatternEvent event;
  final DateTime? sessionStart;
  final Color accent;
  final bool isLast;

  const _TherapyPatternEventRow({
    required this.step,
    required this.event,
    required this.sessionStart,
    required this.accent,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final startClock = _formatClockAt(sessionStart, event.startOffsetSec);
    final endClock = _formatClockAt(sessionStart, event.endOffsetSec);
    final description = therapyPatternDescription(event.patternIndex);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : scheme.outline,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$step',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  therapyPatternName(event.patternIndex),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  startClock == null
                      ? '${_formatMinSec(event.startOffsetSec)} to ${_formatMinSec(event.endOffsetSec)}'
                      : '$startClock to ${endClock ?? 'end'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withValues(alpha: 0.16)),
            ),
            child: Text(
              _formatMinSec(event.durationSec),
              style: TextStyle(
                fontSize: 11,
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String? _formatClockAt(DateTime? start, int offsetSec) {
    if (start == null) return null;
    final ts = start.add(Duration(seconds: offsetSec));
    final hour = ts.hour == 0 ? 12 : (ts.hour > 12 ? ts.hour - 12 : ts.hour);
    final minute = ts.minute.toString().padLeft(2, '0');
    final second = ts.second.toString().padLeft(2, '0');
    final ampm = ts.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute:$second $ampm';
  }
}

String _formatMinSec(int seconds) {
  if (seconds < 0) seconds = 0;
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

// ─── Detail Stat ──────────────────────────────────────────────────────────────

class _DetailStat extends StatelessWidget {
  final String value, label;

  const _DetailStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _cardDecoration(scheme, radius: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
