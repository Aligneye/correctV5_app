import 'package:correctv1/services/session_repository.dart';
import 'package:correctv1/services/therapy_pattern_names.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../../analytics/analytics_screen.dart';

const _kPrimaryBlue = AppTheme.brandPrimary;
const _kBadPostureRed = AppTheme.destructive;

class RecentSessionsCard extends StatelessWidget {
  final List<SessionData> sessions;
  final bool isLoading;
  final bool isSyncing;
  final bool isDeviceDisconnected;
  final bool isDeviceConnecting;
  final VoidCallback onViewAll;
  final ValueChanged<SessionData> onSessionTap;
  final VoidCallback onSyncNow;

  const RecentSessionsCard({
    super.key,
    required this.sessions,
    required this.isLoading,
    required this.isSyncing,
    required this.isDeviceDisconnected,
    required this.isDeviceConnecting,
    required this.onViewAll,
    required this.onSessionTap,
    required this.onSyncNow,
  });

  @override
  Widget build(BuildContext context) {
    final liveSessions = sessions.where((s) => s.isLive).toList();
    final finishedSessions = sessions.where((s) => !s.isLive).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header – matches Quick Modes style
        Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Sessions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: _kPrimaryBlue,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Text('View All'),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ],
            );
          },
        ),

        // Status banner: disconnect
        if (isDeviceDisconnected) ...[
          const SizedBox(height: 12),
          _DisconnectedBanner(
            isReconnecting: isDeviceConnecting,
            onSyncNow: onSyncNow,
          ),
        ],

        const SizedBox(height: 12),

        if (isLoading && sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: LinearProgressIndicator(minHeight: 3),
          )
        else if (sessions.isEmpty)
          const _EmptyRecentSessions()
        else ...[
          for (final live in liveSessions) ...[
            _LiveSessionRow(session: live, onTap: () => onSessionTap(live)),
            const SizedBox(height: 8),
          ],
          for (
            var i = 0;
            i < finishedSessions.length && (liveSessions.length + i) < 5;
            i++
          ) ...[
            _HomeSessionItem(
              session: finishedSessions[i],
              onTap: () => onSessionTap(finishedSessions[i]),
            ),
            if ((liveSessions.length + i + 1) <
                (liveSessions.length + finishedSessions.length).clamp(0, 5))
              const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _DisconnectedBanner extends StatelessWidget {
  final bool isReconnecting;
  final VoidCallback onSyncNow;
  const _DisconnectedBanner({
    required this.isReconnecting,
    required this.onSyncNow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE2A8)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.bluetooth_disabled_rounded,
            size: 18,
            color: Color(0xFFB45309),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device disconnected',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Sessions are still being saved on the pod. '
                  'Sync to pull them in.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB45309),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isReconnecting ? null : onSyncNow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isReconnecting
                    ? const Color(0xFFFFE2A8)
                    : const Color(0xFFB45309),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isReconnecting) ...[
                    const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFB45309),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ] else ...[
                    const Icon(
                      Icons.sync_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    isReconnecting ? 'Syncing' : 'Sync now',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isReconnecting
                          ? const Color(0xFFB45309)
                          : Colors.white,
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
}

class _EmptyRecentSessions extends StatelessWidget {
  const _EmptyRecentSessions();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _kPrimaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.history_rounded,
              size: 18,
              color: _kPrimaryBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No sessions yet',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Start a posture or therapy session and it shows up here.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveSessionRow extends StatelessWidget {
  final SessionData session;
  final VoidCallback onTap;
  const _LiveSessionRow({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPosture = session.type == SessionType.posture;
    final modeGradient = isPosture
        ? AppTheme.goodPostureGradient
        : AppTheme.vibrationTherapyGradient;
    final accent = isPosture
        ? AppTheme.goodPostureStart
        : const Color(0xFF60A5FA);
    final patternName = session.pattern == null
        ? null
        : therapyPatternName(session.pattern!);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.10),
                accent.withValues(alpha: 0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: accent.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: modeGradient.colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPosture
                      ? Icons.accessibility_new_rounded
                      : Icons.graphic_eq,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const _HomeLivePill(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.duration == '0s'
                          ? 'Just started · live now'
                          : 'In progress · ${session.duration}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isPosture && session.score != null)
                Text(
                  '${session.score}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    letterSpacing: -0.4,
                  ),
                )
              else if (!isPosture && patternName != null)
                Text(
                  patternName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSessionItem extends StatelessWidget {
  final SessionData session;
  final VoidCallback onTap;
  const _HomeSessionItem({required this.session, required this.onTap});

  static const _kTextHint = Color(0xFFBBBBCC);
  static const _kBlue = AppTheme.brandPrimary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPosture = session.type == SessionType.posture;
    final postureEventCount = session.postureEvents?.length ?? session.alerts;
    final correctionCount = session.postureEvents
        ?.where((event) => event.wasCorrected)
        .length;
    final playedTherapyEvents = session.therapyPatternEvents
        ?.where((event) => event.durationSec > 0)
        .toList(growable: false);
    final therapyPatternCount =
        playedTherapyEvents?.length ??
        session.therapyPatterns?.length ??
        (session.pattern == null ? null : 1);
    final lastPatternIndex =
        playedTherapyEvents?.lastOrNull?.patternIndex ??
        session.therapyPatternEvents?.lastOrNull?.patternIndex ??
        session.therapyPatterns?.lastOrNull ??
        session.pattern;
    final lastPatternName = lastPatternIndex == null
        ? null
        : therapyPatternName(lastPatternIndex);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 13, 10, 13),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.15), width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isPosture
                      ? AppTheme.goodPostureGradient.colors
                      : AppTheme.vibrationTherapyGradient.colors,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                isPosture ? Icons.accessibility_new_rounded : Icons.graphic_eq,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          session.name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (session.isLive) ...[
                        const SizedBox(width: 6),
                        const _HomeLivePill(),
                      ],
                      if (!session.cloudSynced && !session.isLive)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.cloud_off_rounded,
                            size: 13,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        session.time,
                        style: const TextStyle(fontSize: 10, color: _kTextHint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _HomeSessionMiniStat(
                        value: session.duration,
                        label: 'Duration',
                      ),
                      if (isPosture && postureEventCount != null)
                        _HomeSessionMiniStat(
                          value: '$postureEventCount',
                          label: 'Slouches',
                        ),
                      if (isPosture && correctionCount != null)
                        _HomeSessionMiniStat(
                          value: '$correctionCount',
                          label: 'Corrected',
                        ),
                      if (isPosture && (session.wrongDurSec ?? 0) > 0)
                        _HomeSessionMiniStat(
                          value: _formatCompactDuration(session.wrongDurSec!),
                          label: 'Bad time',
                        ),
                      if (!isPosture && therapyPatternCount != null)
                        _HomeSessionMiniStat(
                          value: '$therapyPatternCount',
                          label: 'Patterns',
                        ),
                      if (!isPosture && lastPatternName != null)
                        _HomeSessionMiniStat(
                          value: lastPatternName,
                          label: 'Last pattern',
                        ),
                    ],
                  ),
                  if (session.score != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: session.score! / 100,
                        backgroundColor: scheme.outline.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(_kBlue),
                        minHeight: 3.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFCCCCDD),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatCompactDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final rem = seconds % 60;
    return rem == 0 ? '${minutes}m' : '${minutes}m ${rem}s';
  }
}

class _HomeSessionMiniStat extends StatelessWidget {
  final String value, label;
  const _HomeSessionMiniStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            height: 1.2,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: scheme.onSurfaceVariant,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _HomeLivePill extends StatefulWidget {
  const _HomeLivePill();

  @override
  State<_HomeLivePill> createState() => _HomeLivePillState();
}

class _HomeLivePillState extends State<_HomeLivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _kBadPostureRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kBadPostureRed.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _kBadPostureRed.withValues(
                  alpha: 0.55 + 0.45 * _ctrl.value,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
              color: _kBadPostureRed,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
