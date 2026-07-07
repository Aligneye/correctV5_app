import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Full-screen, non-interactive confetti burst that plays once.
///
/// Drop this into a Stack (e.g. inside a celebration popup) positioned
/// with Positioned.fill. It ignores touches so it never blocks the
/// dismiss/tap gestures underneath it.
class CelebrationConfetti extends StatefulWidget {
  const CelebrationConfetti({
    super.key,
    this.assetPath = 'assets/animations/Confetti - Full Screen.json',
    this.repeat = false,
  });

  final String assetPath;
  final bool repeat;

  @override
  State<CelebrationConfetti> createState() => _CelebrationConfettiState();
}

class _CelebrationConfettiState extends State<CelebrationConfetti> {
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    if (_finished) return const SizedBox.shrink();

    return IgnorePointer(
      child: Lottie.asset(
        widget.assetPath,
        fit: BoxFit.cover,
        repeat: widget.repeat,
        onLoaded: (composition) {
          if (widget.repeat) return;
          Future.delayed(composition.duration, () {
            if (mounted) setState(() => _finished = true);
          });
        },
        errorBuilder: (context, error, stackTrace) {
          // If the asset is missing, fail silently rather than crashing
          // the celebration popup — the burst-painter effect still shows.
          return const SizedBox.shrink();
        },
      ),
    );
  }
}// TODO Implement this library.