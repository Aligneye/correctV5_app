import 'package:flutter/material.dart';

class StaggeredFadeSlide extends StatelessWidget {
  final Animation<double> controller;
  final int delayMs;
  final Widget child;

  const StaggeredFadeSlide({
    super.key,
    required this.controller,
    required this.delayMs,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final start = delayMs / 1000.0;
        final value = Curves.easeOut.transform(
          ((controller.value - start) / 0.6).clamp(0.0, 1.0),
        );

        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
