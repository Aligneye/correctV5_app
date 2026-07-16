import 'dart:math' as math;

import 'package:correctv1/services/session_repository.dart';
import 'package:correctv1/home/widgets/celebration_confetti.dart';
import 'package:flutter/material.dart';

class XpLevelTile extends StatefulWidget {
  final XpStats? xpStats;
  final VoidCallback? onTap;

  const XpLevelTile({super.key, this.xpStats, this.onTap});

  @override
  State<XpLevelTile> createState() => _XpLevelTileState();
}

class _XpLevelTileState extends State<XpLevelTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _glowAnim = Tween<double>(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.xpStats;
    final level = stats?.currentLevel ?? 1;
    final progress = stats?.levelProgress ?? 0.0;

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
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFA855F7).withValues(
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
                            Colors.white.withValues(alpha: 0.15),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Shimmer sweep
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: _shimmer.value * 132,
                    child: Transform.rotate(
                      angle: -0.4,
                      child: Container(
                        width: 30,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.1),
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$level',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.0,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'LVL',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Level',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.25,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // XP progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Stack(
                                children: [
                                  Container(
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: progress.clamp(0.0, 1.0),
                                    child: Container(
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (stats != null)
                              Text(
                                '${stats.xpProgress} / ${stats.xpNeeded} XP',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.75),
                                  letterSpacing: 0.2,
                                ),
                              ),
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
      },
    );
  }
}

class LevelUpPopup extends StatefulWidget {
  const LevelUpPopup({
    super.key,
    required this.xpStats,
    required this.resolveTarget,
  });

  final XpStats xpStats;
  final Rect? Function() resolveTarget;

  @override
  State<LevelUpPopup> createState() => _LevelUpPopupState();
}

class _LevelUpPopupState extends State<LevelUpPopup>
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

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    await _exit.forward();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismiss,
            ),
          ),
          const Positioned.fill(child: CelebrationConfetti()),
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_entrance, _exit]),
              builder: (context, child) => _buildAnimated(child!),
              child: _buildCard(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimated(Widget child) {
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

  Widget _buildCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = widget.xpStats;

    return Container(
      key: _cardKey,
      margin: const EdgeInsets.symmetric(horizontal: 28),
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFA855F7).withValues(alpha: 0.35),
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
                builder: (context, _) => CustomPaint(
                  painter: _XpBurstPainter(progress: _loop.value),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 40),
                AnimatedBuilder(
                  animation: _loop,
                  builder: (context, _) {
                    final pulse =
                        1.0 + math.sin(_loop.value * math.pi * 2) * 0.06;
                    return Transform.scale(
                      scale: pulse,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFA855F7).withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '${stats.currentLevel}',
                  style: const TextStyle(
                    fontSize: 68,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                    height: 1.0,
                    color: Color(0xFFA855F7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Level Up!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You reached Level ${stats.currentLevel}. Keep earning XP!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'XP Progress',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${stats.xpProgress} / ${stats.xpNeeded} XP',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFA855F7),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: stats.levelProgress,
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFA855F7),
                                      Color(0xFFEC4899),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                        onTap: _dismiss,
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              'Keep earning XP',
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

class _XpBurstPainter extends CustomPainter {
  const _XpBurstPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h * 0.95);

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFA855F7).withValues(alpha: 0.30),
          const Color(0xFFA855F7).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: w * 0.9));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), glow);

    const rayCount = 12;
    final rayPaint = Paint()
      ..color = const Color(0xFFA855F7).withValues(alpha: 0.20)
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
  bool shouldRepaint(_XpBurstPainter old) => old.progress != progress;
}