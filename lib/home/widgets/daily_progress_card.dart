import 'package:flutter/material.dart';
import 'package:correctv1/services/session_repository.dart';

/// Stats-row tile: score ring vs target, slouches today, change vs yesterday.
class DailyProgressTile extends StatelessWidget {
  const DailyProgressTile({
    super.key,
    required this.stats,
    required this.target,
    required this.onTap,
  });

  final TodayStats? stats;
  final int target;
  final VoidCallback onTap;

  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
  );

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final hasData = s?.hasTodayPostureData ?? false;
    final score = hasData ? s!.todayPct : 0;
    final met = hasData && score >= target;

    final String bottom;
    if (s == null) {
      bottom = '—';
    } else if (!hasData) {
      bottom = 'Start a\nsession';
    } else {
      bottom = '${s.todaySlouchCount} slouch${s.todaySlouchCount == 1 ? '' : 'es'}';
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white.withValues(alpha: 0.15),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFA855F7).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        Colors.white.withValues(alpha: 0.14),
                        Colors.white.withValues(alpha: 0.0),
                      ]),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ring(hasData ? score : null),
                          const Spacer(),
                          _pill(met ? '✓' : '🎯 $target'),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bottom,
                            maxLines: 2,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                          if (_trend(s) case final t?) ...[
                            const SizedBox(height: 6),
                            _pill(t),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(int? score) {
    final value = score == null ? 0.0 : (score / target).clamp(0.0, 1.0);
    return SizedBox(
      width: 56,
      height: 56,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: 5,
                strokeCap: StrokeCap.round,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
              ),
            ),
            Text(
              score == null ? '—' : '$score%',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Slouch/hr change first (fairer), else score change; null if neither.
  static String? _trend(TodayStats? s) {
    if (s == null) return null;
    final slouch = s.slouchChangePct?.round();
    if (slouch != null) {
      if (slouch == 0) return '= slouch';
      return '${slouch < 0 ? '↓' : '↑'}${slouch.abs()}% slouch';
    }
    final score = s.scoreChangePct?.round();
    if (score != null) {
      if (score == 0) return '= score';
      return '${score > 0 ? '↑' : '↓'}${score.abs()}% score';
    }
    return null;
  }

  static Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.0,
          ),
        ),
      );
}
