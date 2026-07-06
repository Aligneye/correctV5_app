import 'package:flutter/material.dart';

/// GitHub-contribution-style heatmap showing the last 35 streak days (5 weeks).
///
/// Each cell state: 0 = inactive, 1 = active, 2 = freeze-used.
class StreakCalendarWidget extends StatelessWidget {
  /// List of day states, oldest first, length should be 35.
  /// 0 = no session, 1 = had session, 2 = freeze was used.
  final List<int> dayStates;

  /// Optional streak palette colors for active cells.
  final Color activeStart;
  final Color activeEnd;

  const StreakCalendarWidget({
    super.key,
    required this.dayStates,
    this.activeStart = const Color(0xFFA855F7),
    this.activeEnd = const Color(0xFFEC4899),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const weeks = 5;
    const daysPerWeek = 7;
    const cellSize = 28.0;
    const cellSpacing = 4.0;

    // Pad to exactly 35 entries
    final states = List<int>.filled(weeks * daysPerWeek, 0);
    for (var i = 0; i < dayStates.length && i < states.length; i++) {
      states[i] = dayStates[i];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Day labels
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(daysPerWeek, (i) {
            return SizedBox(
              width: cellSize + cellSpacing,
              child: Text(
                days[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        // Grid: rows = weeks, cols = days
        Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(weeks, (week) {
            return Padding(
              padding: const EdgeInsets.only(bottom: cellSpacing),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(daysPerWeek, (day) {
                  final idx = week * daysPerWeek + day;
                  final state = idx < states.length ? states[idx] : 0;
                  return Padding(
                    padding: const EdgeInsets.only(right: cellSpacing),
                    child: _DayCell(
                      state: state,
                      size: cellSize,
                      activeStart: activeStart,
                      activeEnd: activeEnd,
                      inactiveColor: scheme.surfaceContainerHighest,
                    ),
                  );
                }),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        // Legend
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendItem(
              color: scheme.surfaceContainerHighest,
              label: 'No session',
            ),
            const SizedBox(width: 12),
            _LegendItem(
              gradient: LinearGradient(colors: [activeStart, activeEnd]),
              label: 'Active',
            ),
            const SizedBox(width: 12),
            const _LegendItem(
              color: Color(0xFF38BDF8),
              label: 'Freeze used',
            ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.state,
    required this.size,
    required this.activeStart,
    required this.activeEnd,
    required this.inactiveColor,
  });

  final int state;
  final double size;
  final Color activeStart;
  final Color activeEnd;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    BoxDecoration decoration;
    Widget? child;

    switch (state) {
      case 1: // active
        decoration = BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [activeStart, activeEnd],
          ),
          borderRadius: BorderRadius.circular(6),
        );
      case 2: // freeze used
        decoration = BoxDecoration(
          color: const Color(0xFF38BDF8),
          borderRadius: BorderRadius.circular(6),
        );
        child = const Icon(
          Icons.ac_unit_rounded,
          size: 12,
          color: Colors.white,
        );
      default: // inactive
        decoration = BoxDecoration(
          color: inactiveColor,
          borderRadius: BorderRadius.circular(6),
        );
    }

    return Container(
      width: size,
      height: size,
      decoration: decoration,
      child: child != null ? Center(child: child) : null,
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({this.color, this.gradient, required this.label});

  final Color? color;
  final LinearGradient? gradient;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            gradient: gradient,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
