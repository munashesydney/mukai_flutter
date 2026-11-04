/// Bar chart for rich chat responses, painted by hand.
///
/// Kept dependency-free: no charting package, so the client stays light and the
/// colours come straight from the active Mukai palette. Bars grow in on first
/// paint and can be inspected by tapping or dragging across them.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/appearance.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../../../domain/models.dart';

class MukaiBarChart extends StatefulWidget {
  const MukaiBarChart({super.key, required this.block, this.height = 196});

  final ChartBlock block;
  final double height;

  @override
  State<MukaiBarChart> createState() => _MukaiBarChartState();
}

class _MukaiBarChartState extends State<MukaiBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  int? _selected;

  @override
  void initState() {
    super.initState();
    // Open on the outlier, the way the desktop chart surfaces the interesting
    // point rather than the first one.
    _selected = _outlierIndex();
  }

  @override
  void didUpdateWidget(covariant MukaiBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.points.length != widget.block.points.length) {
      _grow.forward(from: 0);
      _selected = _outlierIndex();
    }
  }

  /// Opens on the point worth reading first: a dip if there is one, otherwise
  /// the largest magnitude.
  int _outlierIndex() {
    if (widget.block.points.isEmpty) return 0;
    for (int i = 0; i < widget.block.points.length; i++) {
      if (widget.block.points[i].value < 0) return i;
    }
    int best = 0;
    double bestDistance = 0;
    for (int i = 0; i < widget.block.points.length; i++) {
      final double distance = widget.block.points[i].value.abs();
      if (distance >= bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  void _selectAt(double localX, Size size) {
    final _ChartScale scale = _ChartScale(
      points: widget.block.points,
      size: size,
    );
    final int index = scale.indexAt(localX);
    if (index == _selected) return;
    setState(() => _selected = index);
    Haptics.select();
  }

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, widget.height);
        final int? selected = _selected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: colors.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  widget.block.seriesLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: MukaiSpace.md),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails details) =>
                  _selectAt(details.localPosition.dx, size),
              onHorizontalDragUpdate: (DragUpdateDetails details) =>
                  _selectAt(details.localPosition.dx, size),
              child: AnimatedBuilder(
                animation: _grow,
                builder: (BuildContext context, Widget? _) {
                  return CustomPaint(
                    size: size,
                    painter: _BarPainter(
                      points: widget.block.points,
                      colors: colors,
                      progress: Curves.easeOutCubic.transform(_grow.value),
                      selected: selected,
                    ),
                  );
                },
              ),
            ),
            if (selected != null) ...<Widget>[
              const SizedBox(height: MukaiSpace.sm),
              _Callout(
                label: widget.block.points[selected].label,
                seriesLabel: widget.block.seriesLabel,
                value: widget.block.points[selected].value,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Maps bar slots to x positions and derives the value scale.
class _ChartScale {
  _ChartScale({required this.points, required this.size})
    : axisWidth = 30,
      labelHeight = 22 {
    double high = 0;
    double low = 0;
    for (final ({String label, double value}) point in points) {
      high = math.max(high, point.value);
      low = math.min(low, point.value);
    }
    final double span = (high - low) == 0 ? 1 : (high - low);
    max = high + span * 0.12;
    min = low - span * 0.12;
  }

  final List<({String label, double value})> points;
  final Size size;
  final double axisWidth;
  final double labelHeight;
  late final double max;
  late final double min;

  double get plotLeft => axisWidth;
  double get plotWidth => math.max(1, size.width - axisWidth - 6);
  double get plotHeight => math.max(1, size.height - labelHeight);

  double yFor(double value) {
    final double t = (max - value) / (max - min);
    return t * plotHeight;
  }

  double get zeroY => yFor(0);

  double slotWidth() => plotWidth / math.max(1, points.length);

  double centerFor(int index) => plotLeft + slotWidth() * (index + 0.5);

  double barWidth() => slotWidth() * 0.58;

  int indexAt(double localX) {
    if (points.isEmpty) return 0;
    final int index = ((localX - plotLeft) / slotWidth()).floor();
    return index.clamp(0, points.length - 1).toInt();
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.points,
    required this.colors,
    required this.progress,
    this.selected,
  });

  final List<({String label, double value})> points;
  final MukaiColors colors;
  final double progress;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final _ChartScale scale = _ChartScale(points: points, size: size);
    _paintGrid(canvas, scale);
    _paintBars(canvas, scale);
    _paintLabels(canvas, scale);
  }

  void _paintGrid(Canvas canvas, _ChartScale scale) {
    final Paint line = Paint()
      ..color = colors.hairline
      ..strokeWidth = 1;
    final TextPainter label = TextPainter(
      textDirection: TextDirection.ltr,
      text: const TextSpan(),
    );

    const int steps = 4;
    for (int i = 0; i <= steps; i++) {
      final double value = scale.max - (scale.max - scale.min) * (i / steps);
      final double y = scale.yFor(value);
      canvas.drawLine(
        Offset(scale.plotLeft, y),
        Offset(scale.plotLeft + scale.plotWidth, y),
        line,
      );
      _drawAxisLabel(canvas, label, value.round().toString(), y);
    }
  }

  void _drawAxisLabel(
    Canvas canvas,
    TextPainter painter,
    String text,
    double y,
  ) {
    painter.text = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 10.5,
        color: colors.textSoft,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    painter.layout();
    // Right-align the tick label inside the 30pt axis gutter.
    painter.paint(canvas, Offset(26 - painter.width, y - painter.height / 2));
  }

  void _paintBars(Canvas canvas, _ChartScale scale) {
    for (int i = 0; i < points.length; i++) {
      final ({String label, double value}) point = points[i];
      final bool isSelected = selected == i;
      final Paint bar = Paint()
        ..color = point.value < 0
            ? colors.accentColor.withValues(alpha: isSelected ? 0.95 : 0.62)
            : colors.accentColor.withValues(alpha: isSelected ? 0.72 : 0.34);

      final double target = scale.yFor(point.value * progress);
      final double zero = scale.zeroY;
      final double left = scale.centerFor(i) - scale.barWidth() / 2;
      final Rect rect = Rect.fromLTRB(
        left,
        math.min(target, zero),
        left + scale.barWidth(),
        math.max(target, zero),
      );
      final double radius = math.min(4, math.min(rect.width, rect.height) / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, radius))),
        bar,
      );
    }
  }

  void _paintLabels(Canvas canvas, _ChartScale scale) {
    for (int i = 0; i < points.length; i++) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: points[i].label,
          style: TextStyle(
            fontSize: 11,
            color: selected == i ? colors.ink : colors.textMuted,
            fontWeight: selected == i ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(scale.centerFor(i) - painter.width / 2, scale.plotHeight + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.selected != selected ||
      oldDelegate.points.length != points.length ||
      oldDelegate.colors != colors;
}

/// The value bubble that follows the selected bar.
class _Callout extends StatelessWidget {
  const _Callout({
    required this.label,
    required this.seriesLabel,
    required this.value,
  });

  final String label;
  final String seriesLabel;
  final double value;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String formatted = value < 0
        ? '-\$${value.abs().toStringAsFixed(0)}'
        : '\$${value.toStringAsFixed(0)}';
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: MukaiMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(MukaiRadii.control),
          border: Border.all(color: colors.hairline),
          boxShadow: MukaiShadows.card(colors.brightness),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: text.titleSmall),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      seriesLabel,
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 18),
            Text(
              formatted,
              style: text.titleMedium?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
