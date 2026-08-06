import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:correctv1/discover/buy_alignpod_sheet.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.pageBackgroundGradientFor(context),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            children: [
              Text(
                'Discover',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Tools to understand your posture',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              const _PostureCheckHeroCard(),
              const SizedBox(height: 16),
              const _BuyAlignPodCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostureCheckHeroCard extends StatelessWidget {
  const _PostureCheckHeroCard();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://aligneye.com/posture-check'),
        mode: LaunchMode.inAppWebView,
      ),
      child: Container(
        height: 320,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: isDark ? const Color(0xFF0D1117) : Colors.white,
          border: isDark
              ? null
              : Border.all(
                  color: const Color(0xFF9333EA).withValues(alpha: 0.15),
                ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF9333EA).withValues(
                alpha: isDark ? 0.25 : 0.12,
              ),
              blurRadius: isDark ? 40 : 30,
              offset: const Offset(0, 12),
              spreadRadius: -4,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Purple glow blob — top right
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF9333EA).withValues(
                        alpha: isDark ? 0.35 : 0.08,
                      ),
                      const Color(0xFF9333EA).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Blue glow blob — bottom left
            Positioned(
              bottom: -20,
              left: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF2563EB).withValues(
                        alpha: isDark ? 0.3 : 0.07,
                      ),
                      const Color(0xFF2563EB).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Radar rings
            Positioned(
              right: -10,
              bottom: 20,
              child: _RadarRings(isDark: isDark),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Eyebrow
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppTheme.brandGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'POSTURE CHECK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'How does your\nposture compare?',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Take a quick assessment and see where\nyou stand against global benchmarks.',
                    style: TextStyle(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.55)
                          : const Color(0xFF64748B),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppTheme.alignWalkGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEC4899).withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Start Check',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFF9333EA).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : const Color(0xFF9333EA).withValues(alpha: 0.15),
                          ),
                        ),
                        child: Icon(
                          Icons.accessibility_new_rounded,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.7)
                              : const Color(0xFF9333EA),
                          size: 22,
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
    );
  }
}

class _RadarRings extends StatelessWidget {
  final bool isDark;
  const _RadarRings({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: CustomPaint(painter: _RadarPainter(isDark: isDark)),
    );
  }
}

class _BuyAlignPodCard extends StatelessWidget {
  const _BuyAlignPodCard();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => showBuyAlignPodSheet(context),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: isDark ? const Color(0xFF0D1117) : Colors.white,
          border: Border.all(
            color: isDark
                ? const Color(0xFFFBBF24).withValues(alpha: 0.15)
                : const Color(0xFFFBBF24).withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF97316).withValues(
                alpha: isDark ? 0.18 : 0.1,
              ),
              blurRadius: 28,
              offset: const Offset(0, 10),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppTheme.ridingGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF97316).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.shopping_bag_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Buy AlignPod',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Place a pre-order — team contacts you within 24h',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final bool isDark;
  const _RadarPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final ringColor = isDark ? const Color(0xFF9333EA) : const Color(0xFF9333EA);

    for (int i = 1; i <= 4; i++) {
      final radius = (size.width / 2) * (i / 4);
      paint.color = ringColor.withValues(
        alpha: isDark
            ? 0.08 + (4 - i) * 0.04
            : 0.06 + (4 - i) * 0.03,
      );
      canvas.drawCircle(center, radius, paint);
    }

    canvas.drawCircle(
      center,
      4,
      Paint()
        ..color = ringColor.withValues(alpha: isDark ? 0.4 : 0.3)
        ..style = PaintingStyle.fill,
    );

    paint
      ..color = ringColor.withValues(alpha: isDark ? 0.12 : 0.08)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(center.dx, center.dy - size.height / 2),
      Offset(center.dx, center.dy + size.height / 2),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - size.width / 2, center.dy),
      Offset(center.dx + size.width / 2, center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.isDark != isDark;
}