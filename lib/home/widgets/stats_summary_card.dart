import 'dart:math' as math;

import 'package:correctv1/home/widgets/surface_card.dart';
import 'package:correctv1/home/widgets/celebration_confetti.dart';
import 'package:correctv1/home/widgets/xp_level_tile.dart';
import 'package:correctv1/services/session_repository.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class DisplayValue {
  const DisplayValue(this.value, this.unit);
  final String value;
  final String unit;
}

class StatItemData {
  final String value;
  final String? unit;
  final String label;
  final String trendText;
  final IconData icon;
  final LinearGradient gradient;
  final bool positiveTrend;
  final bool trendNeutral;
  final VoidCallback? onTap;

  const StatItemData({
    required this.value,
    this.unit,
    required this.label,
    required this.trendText,
    required this.icon,
    required this.gradient,
    this.positiveTrend = true,
    this.trendNeutral = false,
    this.onTap,
  });
}

class StatsSummaryCard extends StatelessWidget {
  final List<StatItemData> items;
  final int streakDays;
  final bool streakTodayActive;
  final Key? streakTileKey;
  final int freezeTokens;
  final XpStats? xpStats;
  final Key? xpTileKey;
  final VoidCallback? onStreakTap;
  final VoidCallback? onXpTap;

  const StatsSummaryCard({
    super.key,
    required this.items,
    this.streakDays = 0,
    this.streakTodayActive = false,
    this.streakTileKey,
    this.freezeTokens = 0,
    this.xpStats,
    this.xpTileKey,
    this.onStreakTap,
    this.onXpTap,
  });

  @override
  Widget build(BuildContext context) {
    // index 0 = streak tile, index 1 = xp tile, index 2+ = stat items
    final totalCount = items.length + 2;
    return SizedBox(
      height: 156,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(right: 24),
        itemCount: totalCount,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return SizedBox(
              key: streakTileKey,
              width: 132,
              child: _StreakTile(
                days: streakDays,
                todayActive: streakTodayActive,
                freezeTokens: freezeTokens,
                onTap: onStreakTap,
              ),
            );
          }
          if (index == 1) {
            return SizedBox(
              key: xpTileKey,
              width: 132,
              child: XpLevelTile(xpStats: xpStats, onTap: onXpTap),
            );
          }
          return SizedBox(
            width: 132,
            child: _SummaryMetricTile(item: items[index - 2]),
          );
        },
      ),
    );
  }
}

class _StreakTile extends StatefulWidget {
  final int days;
  final bool todayActive;
  final int freezeTokens;
  final VoidCallback? onTap;

  const _StreakTile({
    required this.days,
    this.todayActive = true,
    this.freezeTokens = 0,
    this.onTap,
  });

  @override
  State<_StreakTile> createState() => _StreakTileState();
}

class _StreakPalette {
  const _StreakPalette(this.bgStart, this.bgMid, this.bgEnd, this.shadow);
  final Color bgStart;
  final Color bgMid;
  final Color bgEnd;
  final Color shadow;
}

const Map<int, ({String label, String compliment, String asset})> _kStreakMilestones = {
  7:   (label: 'Week Warrior',       compliment: 'Ek hafta solid! Habit ban rahi hai.',              asset: 'assets/badges/badge_7day.svg'),
  30:  (label: 'Monthly Master',     compliment: 'Poora mahina! Ab yeh lifestyle hai, phase nahi.',   asset: 'assets/badges/badge_30day.svg'),
  50:  (label: 'Steel Spine',        compliment: '50 din bina rukke — discipline dikh rahi hai.',     asset: 'assets/badges/badge_50day.svg'),
  75:  (label: 'Iron Will',          compliment: '75 din! Bahut kam log yahan tak pahunchte hain.',   asset: 'assets/badges/badge_75day.svg'),
  100: (label: 'Century Streak',     compliment: '100 days! Top 1% consistent users mein ho.',        asset: 'assets/badges/badge_100day.svg'),
  150: (label: 'Unstoppable',        compliment: '150 din — yeh ab habit nahi, identity hai.',         asset: 'assets/badges/badge_150day.svg'),
  200: (label: 'Elite Streaker',     compliment: '200 din ka streak — legendary level dedication.',    asset: 'assets/badges/badge_200day.svg'),
  250: (label: 'Diamond Discipline', compliment: '250 din! Bohot kam log yahan tak aate hain.',        asset: 'assets/badges/badge_250day.svg'),
  300: (label: 'Platinum Streak',    compliment: '300 din — saal ke 300 din khud ko choose kiya.',     asset: 'assets/badges/badge_300day.svg'),
  365: (label: 'Year of Discipline', compliment: 'Poora saal! Tum ab isse alag insaan ho gaye ho.',    asset: 'assets/badges/badge_365day.svg'),
};

const List<_StreakPalette> _kStreakPalettes = <_StreakPalette>[
  _StreakPalette(Color(0xFF60A5FA), Color(0xFF3B82F6), Color(0xFF1D4ED8), Color(0xFF3B82F6)),
  _StreakPalette(Color(0xFF818CF8), Color(0xFF6366F1), Color(0xFF4338CA), Color(0xFF6366F1)),
  _StreakPalette(Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF6D28D9), Color(0xFF8B5CF6)),
  _StreakPalette(Color(0xFFC084FC), Color(0xFFA855F7), Color(0xFF7E22CE), Color(0xFFA855F7)),
  _StreakPalette(Color(0xFFE879F9), Color(0xFFD946EF), Color(0xFFA21CAF), Color(0xFFD946EF)),
  _StreakPalette(Color(0xFFF472B6), Color(0xFFEC4899), Color(0xFFBE185D), Color(0xFFEC4899)),
  _StreakPalette(Color(0xFFFB7185), Color(0xFFF43F5E), Color(0xFFBE123C), Color(0xFFF43F5E)),
  _StreakPalette(Color(0xFFF87171), Color(0xFFEF4444), Color(0xFFB91C1C), Color(0xFFEF4444)),
  _StreakPalette(Color(0xFFFB923C), Color(0xFFF97316), Color(0xFFC2410C), Color(0xFFF97316)),
  _StreakPalette(Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFB45309), Color(0xFFF59E0B)),
  _StreakPalette(Color(0xFFFACC15), Color(0xFFEAB308), Color(0xFFA16207), Color(0xFFEAB308)),
  _StreakPalette(Color(0xFFA3E635), Color(0xFF84CC16), Color(0xFF4D7C0F), Color(0xFF84CC16)),
  _StreakPalette(Color(0xFF4ADE80), Color(0xFF22C55E), Color(0xFF15803D), Color(0xFF22C55E)),
  _StreakPalette(Color(0xFF34D399), Color(0xFF10B981), Color(0xFF047857), Color(0xFF10B981)),
  _StreakPalette(Color(0xFF2DD4BF), Color(0xFF14B8A6), Color(0xFF0F766E), Color(0xFF14B8A6)),
  _StreakPalette(Color(0xFF22D3EE), Color(0xFF06B6D4), Color(0xFF0E7490), Color(0xFF06B6D4)),
  _StreakPalette(Color(0xFF38BDF8), Color(0xFF0EA5E9), Color(0xFF0369A1), Color(0xFF0EA5E9)),
  _StreakPalette(Color(0xFF7DD3FC), Color(0xFF38BDF8), Color(0xFF0284C7), Color(0xFF38BDF8)),
  _StreakPalette(Color(0xFF93C5FD), Color(0xFF60A5FA), Color(0xFF2563EB), Color(0xFF60A5FA)),
  _StreakPalette(Color(0xFF6EE7B7), Color(0xFF34D399), Color(0xFF059669), Color(0xFF34D399)),
  _StreakPalette(Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFF8C00), Color(0xFFFFA500)),
  _StreakPalette(Color(0xFFFF8A65), Color(0xFFFF5722), Color(0xFFD84315), Color(0xFFFF5722)),
  _StreakPalette(Color(0xFFFF6B9D), Color(0xFFE91E63), Color(0xFFAD1457), Color(0xFFE91E63)),
  _StreakPalette(Color(0xFFBA68C8), Color(0xFF9C27B0), Color(0xFF6A1B9A), Color(0xFF9C27B0)),
  _StreakPalette(Color(0xFF7986CB), Color(0xFF3F51B5), Color(0xFF283593), Color(0xFF3F51B5)),
  _StreakPalette(Color(0xFF4FC3F7), Color(0xFF039BE5), Color(0xFF01579B), Color(0xFF039BE5)),
  _StreakPalette(Color(0xFF4DD0E1), Color(0xFF00ACC1), Color(0xFF006064), Color(0xFF00ACC1)),
  _StreakPalette(Color(0xFF81C784), Color(0xFF43A047), Color(0xFF1B5E20), Color(0xFF43A047)),
  _StreakPalette(Color(0xFFFFB74D), Color(0xFFFB8C00), Color(0xFFE65100), Color(0xFFFB8C00)),
  _StreakPalette(Color(0xFFFFEB3B), Color(0xFFFBC02D), Color(0xFFF57F17), Color(0xFFFBC02D)),
];

_StreakPalette _paletteForStreak(int days) {
  if (days <= 0) {
    return const _StreakPalette(
      Color(0xFF94A3B8),
      Color(0xFF64748B),
      Color(0xFF334155),
      Color(0xFF64748B),
    );
  }
  return _kStreakPalettes[(days - 1) % _kStreakPalettes.length];
}

class _StreakTileState extends State<_StreakTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;
  late final Animation<double> _flameFlicker;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(
      begin: 0.92,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _glowAnim = Tween<double>(
      begin: 0.0,
      end: 8.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _flameFlicker = Tween<double>(
      begin: -0.04,
      end: 0.04,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _paletteForStreak(widget.days);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            splashColor: Colors.white.withValues(alpha: 0.15),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.bgStart, palette.bgMid, palette.bgEnd],
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withValues(
                      alpha: 0.25 + _glowAnim.value * 0.02,
                    ),
                    blurRadius: 16 + _glowAnim.value,
                    offset: const Offset(0, 6),
                    spreadRadius: _glowAnim.value * 0.3,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                clipBehavior: Clip.antiAlias,
                children: [
                  Positioned(
                    top: -20,
                    right: -20,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.12),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: -60 + (_ctrl.value * 260),
                    child: Transform.rotate(
                      angle: -0.4,
                      child: Container(
                        width: 30,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.08),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${widget.days}',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.0,
                            letterSpacing: -1,
                          ),
                        ),
                        const Text(
                          'Streak\nDays',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.25,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: -6,
                    right: -2,
                    child: Transform.rotate(
                      angle: _flameFlicker.value,
                      child: Transform.scale(
                        scale: _scaleAnim.value,
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          width: 56,
                          height: 64,
                          child: CustomPaint(
                            painter: _StreakFirePainter(progress: _ctrl.value),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Freeze token badge — bottom-left, only when tokens > 0
                  if (widget.freezeTokens > 0)
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.ac_unit_rounded,
                              size: 10,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${widget.freezeTokens}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StreakFirePainter extends CustomPainter {
  final double progress;

  const _StreakFirePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final outerPath = Path()
      ..moveTo(w * 0.50, h * 0.02)
      ..cubicTo(w * 0.20, h * 0.20, w * -0.05, h * 0.45, w * 0.15, h * 0.70)
      ..cubicTo(w * 0.22, h * 0.82, w * 0.30, h * 0.95, w * 0.50, h * 0.98)
      ..cubicTo(w * 0.70, h * 0.95, w * 0.78, h * 0.82, w * 0.85, h * 0.70)
      ..cubicTo(w * 1.05, h * 0.45, w * 0.80, h * 0.20, w * 0.50, h * 0.02)
      ..close();

    final outerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFF6B35),
          Color.lerp(const Color(0xFFFF4500), const Color(0xFFFF6347), progress)!,
          const Color(0xFFFF8C00),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(outerPath, outerPaint);

    final innerPath = Path()
      ..moveTo(w * 0.50, h * 0.28)
      ..cubicTo(w * 0.30, h * 0.42, w * 0.18, h * 0.55, w * 0.28, h * 0.72)
      ..cubicTo(w * 0.34, h * 0.85, w * 0.42, h * 0.94, w * 0.50, h * 0.96)
      ..cubicTo(w * 0.58, h * 0.94, w * 0.66, h * 0.85, w * 0.72, h * 0.72)
      ..cubicTo(w * 0.82, h * 0.55, w * 0.70, h * 0.42, w * 0.50, h * 0.28)
      ..close();

    final innerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFFD700),
          Color.lerp(const Color(0xFFFFA500), const Color(0xFFFFD700), progress)!,
          const Color(0xFFFFE066),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(innerPath, innerPaint);

    final corePath = Path()
      ..moveTo(w * 0.50, h * 0.52)
      ..cubicTo(w * 0.40, h * 0.62, w * 0.36, h * 0.72, w * 0.42, h * 0.82)
      ..cubicTo(w * 0.45, h * 0.90, w * 0.48, h * 0.94, w * 0.50, h * 0.95)
      ..cubicTo(w * 0.52, h * 0.94, w * 0.55, h * 0.90, w * 0.58, h * 0.82)
      ..cubicTo(w * 0.64, h * 0.72, w * 0.60, h * 0.62, w * 0.50, h * 0.52)
      ..close();

    final corePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFDE0), Color(0xFFFFE082)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(corePath, corePaint);
  }

  @override
  bool shouldRepaint(_StreakFirePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

enum StreakPopupKind { increased, broken }

class StreakPopup extends StatefulWidget {
  const StreakPopup({
    super.key,
    required this.stats,
    required this.kind,
    required this.resolveTarget,
  });

  final StreakStats stats;
  final StreakPopupKind kind;
  final Rect? Function() resolveTarget;

  @override
  State<StreakPopup> createState() => _StreakPopupState();
}

class _StreakPopupState extends State<StreakPopup>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _exit;
  late final AnimationController _loop;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  final GlobalKey _cardKey = GlobalKey();
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _scale = CurvedAnimation(
      parent: _entrance,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeIn,
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _exit.dispose();
    _loop.dispose();
    super.dispose();
  }

  Future<void> _flyToTileAndClose() async {
    if (_dismissing) return;
    _dismissing = true;
    await _exit.forward();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _paletteForStreak(widget.stats.currentStreak);
    final isIncreased = widget.kind == StreakPopupKind.increased;
    final days = widget.stats.currentStreak;

    final isRecord = isIncreased && widget.stats.isNewRecord && days > 1;
    final milestone = isIncreased ? _kStreakMilestones[days] : null;
    final title = isIncreased
        ? (days <= 1
        ? 'Streak started!'
        : milestone != null
        ? '🏅 ${milestone.label}!'
        : isRecord
        ? 'New personal best!'
        : '$days-day streak!')
        : 'Streak reset';

    final subtitle = isIncreased
        ? (days <= 1
        ? 'One session in. Come back tomorrow to grow it.'
        : milestone != null
        ? milestone.compliment
        : isRecord
        ? 'You just set a new record of $days days. Keep the flame alive.'
        : 'You showed up ${days == 2 ? '2 days' : '$days days'} in a row. Best so far: ${widget.stats.highestStreak}.')
        : 'You missed a day. Start a new streak today — every day counts.';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _flyToTileAndClose();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _flyToTileAndClose,
            ),
          ),
          if (milestone != null)
            const Positioned.fill(child: CelebrationConfetti()),
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_entrance, _exit]),
              builder: (context, child) {
                return _buildCard(palette, child!);
              },
              child: _buildCardContent(palette, title, subtitle, milestone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(_StreakPalette palette, Widget child) {
    final screen = MediaQuery.of(context).size;
    final target = widget.resolveTarget();

    final cardBox = _cardKey.currentContext?.findRenderObject();
    Rect? cardRect;
    if (cardBox is RenderBox && cardBox.attached) {
      final tl = cardBox.localToGlobal(Offset.zero);
      cardRect = tl & cardBox.size;
    }

    final exitT = Curves.easeInCubic.transform(_exit.value);
    double dx = 0;
    double dy = 0;
    double exitScale = 1.0 - 0.95 * exitT;
    if (target != null && cardRect != null) {
      dx = (target.center.dx - cardRect.center.dx) * exitT;
      dy = (target.center.dy - cardRect.center.dy) * exitT;
      final targetScale = (target.width / cardRect.width).clamp(0.05, 1.0);
      exitScale = 1.0 + (targetScale - 1.0) * exitT;
    } else {
      dx = 0;
      dy = screen.height * 0.0 * exitT;
    }

    final entranceScale = Tween<double>(begin: 0.8, end: 1.0).evaluate(_scale);
    final combinedScale = entranceScale * exitScale;
    final opacity = (_fade.value * (1.0 - 0.9 * exitT)).clamp(0.0, 1.0);

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.scale(scale: combinedScale, child: child),
      ),
    );
  }

  Widget _buildCardContent(
      _StreakPalette palette,
      String title,
      String subtitle,
      ({String label, String compliment, String asset})? milestone,
      ) {
    final isIncreased = widget.kind == StreakPopupKind.increased;
    final days = widget.stats.currentStreak;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: _cardKey,
      margin: const EdgeInsets.symmetric(horizontal: 28),
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.35),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 180,
              child: AnimatedBuilder(
                animation: _loop,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _StreakBurstPainter(
                      progress: _loop.value,
                      palette: palette,
                      dimmed: !isIncreased,
                    ),
                  );
                },
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 40),
                AnimatedBuilder(
                  animation: _loop,
                  builder: (context, _) {
                    final flicker = math.sin(_loop.value * math.pi * 2) * 0.04;
                    final pulse =
                        1.0 + math.sin(_loop.value * math.pi * 2) * 0.06;
                    return Transform.rotate(
                      angle: flicker,
                      child: Transform.scale(
                        scale: isIncreased ? pulse : 0.92,
                        child: SizedBox(
                          width: 96,
                          height: 110,
                          child: CustomPaint(
                            painter: _StreakFirePainter(progress: _loop.value),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '$days',
                  style: TextStyle(
                    fontSize: 68,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                    height: 1.0,
                    color: palette.bgEnd,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  days == 1 ? 'day' : 'days',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (milestone != null) ...[
                  const SizedBox(height: 10),
                  SvgPicture.asset(milestone.asset, width: 84, height: 100),
                  const SizedBox(height: 6),
                  Text(
                    milestone.label,
                    style: TextStyle(color: palette.bgEnd, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ],
                if (widget.stats.highestStreak > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: palette.bgStart.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.emoji_events_rounded,
                          size: 14,
                          color: palette.bgEnd,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Best: ${widget.stats.highestStreak}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.bgEnd,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _flyToTileAndClose,
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [palette.bgMid, palette.bgEnd],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              'Keep going',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
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

class _StreakBurstPainter extends CustomPainter {
  _StreakBurstPainter({
    required this.progress,
    required this.palette,
    required this.dimmed,
  });

  final double progress;
  final _StreakPalette palette;
  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h * 0.95);

    final glowAlpha = dimmed ? 0.18 : 0.32;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.bgMid.withValues(alpha: glowAlpha),
          palette.bgMid.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: w * 0.9));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), glow);

    const rayCount = 12;
    final rayPaint = Paint()
      ..color = palette.bgStart.withValues(alpha: dimmed ? 0.08 : 0.22)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < rayCount; i++) {
      final t = i / rayCount;
      final angle = math.pi + t * math.pi;
      final len = w * (0.45 + 0.1 * math.sin(progress * math.pi * 2 + i));
      final dx = math.cos(angle) * len;
      final dy = math.sin(angle) * len;
      canvas.drawLine(center, center + Offset(dx, dy), rayPaint);
    }
  }

  @override
  bool shouldRepaint(_StreakBurstPainter oldDelegate) =>
      oldDelegate.progress != progress ||
          oldDelegate.dimmed != dimmed ||
          oldDelegate.palette != palette;
}

class _SummaryMetricTile extends StatelessWidget {
  final StatItemData item;

  const _SummaryMetricTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color trendColor;
    final Color trendBg;
    if (item.trendNeutral) {
      trendColor = scheme.onSurfaceVariant;
      trendBg = scheme.surfaceContainerHighest;
    } else if (item.positiveTrend) {
      trendColor = AppTheme.successText;
      trendBg = AppTheme.successBg;
    } else {
      trendColor = AppTheme.destructive;
      trendBg = AppTheme.destructive.withValues(alpha: 0.10);
    }

    return GestureDetector(
      onTap: item.onTap,
      child: HomeSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: item.gradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, color: Colors.white, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      item.value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                        height: 1.05,
                      ),
                    ),
                    if (item.unit != null && item.unit!.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        item.unit!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant,
                          height: 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxWidth: 104),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: trendBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!item.trendNeutral)
                      Icon(
                        item.positiveTrend
                            ? Icons.arrow_drop_up_rounded
                            : Icons.arrow_drop_down_rounded,
                        size: 16,
                        color: trendColor,
                      ),
                    Flexible(
                      child: Text(
                        item.trendText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: trendColor,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
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