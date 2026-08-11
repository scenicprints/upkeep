import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// THE GAUGE
//
// A machined dial that fills as an item consumes its interval. The arc
// sweeps up from zero when it appears — that sweep is most of why the
// cluster feels alive rather than like a list with circles on it.
//
// Overdue arcs go past a full turn, so the ring is drawn capped at 1.0
// with a thin overrun mark rather than lapping itself confusingly.
// ═══════════════════════════════════════════════════════════════════════

class Gauge extends StatefulWidget {
  final double progress; // 0..1+, may exceed 1 when overdue
  final GaugeState state;
  final double size;
  final double stroke;

  /// Big centre readout ("92") plus a caption. Omitted on the small rows.
  final String? centreLabel;
  final String? centreCaption;

  /// Stagger so a list of gauges sweeps in like a needle bank, not all at
  /// once.
  final Duration delay;

  const Gauge({
    super.key,
    required this.progress,
    required this.state,
    this.size = 106,
    this.stroke = 9,
    this.centreLabel,
    this.centreCaption,
    this.delay = Duration.zero,
  });

  @override
  State<Gauge> createState() => _GaugeState();
}

class _GaugeState extends State<Gauge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(Gauge old) {
    super.didUpdateWidget(old);
    // A new reading should visibly move the needle, not teleport it.
    if (old.progress != widget.progress) {
      _c
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = gaugeColor(widget.state);
    return AnimatedBuilder(
      animation: _a,
      builder: (BuildContext context, Widget? child) {
        final double p = widget.progress * _a.value;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                size: Size.square(widget.size),
                painter: _GaugePainter(
                  progress: p,
                  color: color,
                  stroke: widget.stroke,
                ),
              ),
              if (widget.centreLabel != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.centreLabel!,
                      style: mono(
                        size: widget.size * 0.28,
                        color: color,
                        weight: FontWeight.w500,
                      ),
                    ),
                    if (widget.centreCaption != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.centreCaption!,
                          style: eyebrow(
                            size: widget.size * 0.095,
                            color: _captionColor(widget.state),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Color _captionColor(GaugeState s) => switch (s) {
        GaugeState.healthy => const Color(0xFF2E7F5B),
        GaugeState.ready => kReadyDim,
        GaugeState.overdue => const Color(0xFF9E3535),
      };
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double stroke;

  _GaugePainter({
    required this.progress,
    required this.color,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final double radius = (size.width - stroke) / 2;
    final Rect box = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = kTrack
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    final double filled = progress.clamp(0.0, 1.0);
    if (filled > 0) {
      canvas.drawArc(
        box,
        -math.pi / 2,
        math.pi * 2 * filled,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Overdue: a second, inset arc showing how far past the interval it is,
    // capped at another full turn. Lapping the main ring would read as a
    // lower number than reality.
    if (progress > 1.0) {
      final double over = (progress - 1.0).clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius - stroke * 0.95),
        -math.pi / 2,
        math.pi * 2 * over,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.42
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.color != color || old.stroke != stroke;
}
