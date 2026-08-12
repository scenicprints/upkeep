import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// THE UPKEEP GREMLIN
//
// Bipedal, wrench in hand, no wings. He reads the panel: his eyes take the
// colour of the worst thing on it, so a red-eyed gremlin means something is
// overdue before you've read a single word.
//
// Drawn rather than an asset so he can move. Idle motion is deliberately
// slow — a breath, a wrench tilt, an occasional blink — and gets quicker
// and less patient as the panel gets worse. Poke him and he reacts.
// ═══════════════════════════════════════════════════════════════════════

enum MascotMood {
  /// Nothing tracked yet — waiting for work.
  idle,

  /// Everything on schedule. Smug.
  content,

  /// Something is ready. Watching you.
  alert,

  /// Something is past due. Not amused.
  overdue,
}

MascotMood moodFor(GaugeState worst, {required bool anyItems}) {
  if (!anyItems) return MascotMood.idle;
  return switch (worst) {
    GaugeState.healthy => MascotMood.content,
    GaugeState.ready => MascotMood.alert,
    GaugeState.overdue => MascotMood.overdue,
  };
}

class Mascot extends StatefulWidget {
  final double size;
  final MascotMood mood;

  /// Overrides the eye colour. Defaults to the mood's colour.
  final Color? accent;

  /// Fired after his own reaction plays, if the caller wants to do more.
  final VoidCallback? onTap;

  const Mascot({
    super.key,
    this.size = 132,
    this.mood = MascotMood.idle,
    this.accent,
    this.onTap,
  });

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  /// A poke: he startles, hops, and gives the wrench a spin.
  late final AnimationController _poke = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _idle.dispose();
    _poke.dispose();
    super.dispose();
  }

  Color get _eyeColor {
    if (widget.accent != null) return widget.accent!;
    return switch (widget.mood) {
      // Powered on, waiting for work. Deliberately outside the state
      // palette — green/amber/red mean something specific everywhere else.
      MascotMood.idle => const Color(0xFF8FA6B8),
      MascotMood.content => kHealthy,
      MascotMood.alert => kReady,
      MascotMood.overdue => kOverdue,
    };
  }

  void _tap() {
    if (_poke.isAnimating) return;
    HapticFeedback.lightImpact();
    _poke.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _tap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_idle, _poke]),
        builder: (BuildContext context, Widget? child) => CustomPaint(
          size: Size(widget.size, widget.size * 1.05),
          painter: _GremlinPainter(
            t: _idle.value,
            poke: _poke.value,
            eye: _eyeColor,
            mood: widget.mood,
          ),
        ),
      ),
    );
  }
}

class _GremlinPainter extends CustomPainter {
  final double t; // 0..1, loops every 6 seconds
  final double poke; // 0..1, one-shot reaction
  final Color eye;
  final MascotMood mood;

  _GremlinPainter({
    required this.t,
    required this.poke,
    required this.eye,
    required this.mood,
  });

  // Body palette — deliberately desaturated so the eyes carry the colour.
  // Light enough to hold a silhouette against kBg, dark enough to sit back.
  static const Color _shell = Color(0xFF323D49);
  static const Color _shellDark = Color(0xFF262F38);
  static const Color _edge = Color(0xFF44525E);
  static const Color _steel = Color(0xFF9BAAB8); // the wrench — must read

  /// The worse the panel, the less patient he looks.
  double get _tempo => switch (mood) {
        MascotMood.idle => 1.0,
        MascotMood.content => 1.0,
        MascotMood.alert => 1.5,
        MascotMood.overdue => 2.1,
      };

  @override
  void paint(Canvas canvas, Size size) {
    // Work in a 100 x 105 space, then scale to fit.
    final double s = size.width / 100.0;
    canvas.save();
    canvas.scale(s);

    // ── idle motion ──────────────────────────────────────────────
    final double bob = math.sin(t * math.pi * 4) * 1.6; // ~3s breath
    final double tilt =
        math.sin(t * math.pi * 4.6 * _tempo) * 0.09 * _tempo;

    // A blink roughly every 3 seconds, ~0.16s long.
    final double blinkPhase = (t * 6.0) % 3.0;
    final double openness =
        blinkPhase < 0.16 ? (1.0 - math.sin(blinkPhase / 0.16 * math.pi)) : 1.0;

    // ── the poke ─────────────────────────────────────────────────
    // A hop with a squash on take-off and landing, plus a wrench spin.
    final double airborne = poke == 0 ? 0 : math.sin(poke * math.pi);
    final double hop = -airborne * 9;
    // Stretch while he's off the ground, compress when he lands. The other
    // way round — flattening at the top of the hop — reads as a pancake.
    double squash = -airborne * 0.09;
    if (poke > 0.82) {
      squash = math.sin((poke - 0.82) / 0.18 * math.pi) * 0.12;
    }
    final double spin = poke == 0 ? 0 : poke * math.pi * 2;

    canvas.translate(0, bob + hop);
    if (squash != 0) {
      // Squash about the feet, so he compresses onto the ground.
      canvas.translate(50, 94);
      canvas.scale(1 + squash, 1 - squash);
      canvas.translate(-50, -94);
    }

    final Paint shell = Paint()..color = _shell;
    final Paint shellDark = Paint()..color = _shellDark;
    final Paint edge = Paint()
      ..color = _edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // ── legs ─────────────────────────────────────────────────────
    // Stubby and bipedal. Drawn first so the body overlaps their tops.
    for (final double dx in <double>[-13, 13]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(50 + dx - 6, 74, 12, 17),
          const Radius.circular(5),
        ),
        shellDark,
      );
      // foot
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(50 + dx - 10, 86, 20, 8),
          const Radius.circular(4),
        ),
        shell,
      );
    }

    // ── body ─────────────────────────────────────────────────────
    final RRect body = RRect.fromRectAndCorners(
      const Rect.fromLTWH(24, 26, 52, 52),
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );
    canvas.drawRRect(body, shell);
    canvas.drawRRect(body, edge);

    // ── ear cups ─────────────────────────────────────────────────
    // At the sides, not the top corners — up there they read as horns.
    for (final double dx in <double>[-23, 23]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(50 + dx - 4, 40, 8, 17),
          const Radius.circular(4),
        ),
        shellDark,
      );
    }

    // ── arms ─────────────────────────────────────────────────────
    final Paint arm = Paint()
      ..color = _shellDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(30, 62), const Offset(22, 71), arm);
    // Right arm reaches out to the wrench so he's holding it, not near it.
    canvas.drawLine(const Offset(70, 62), Offset(81 + tilt * 5, 68), arm);

    // ── face plate ───────────────────────────────────────────────
    final RRect plate = RRect.fromRectAndRadius(
      const Rect.fromLTWH(31, 36, 38, 26),
      const Radius.circular(12),
    );
    canvas.drawRRect(plate, Paint()..color = const Color(0xFF161C22));

    // ── eyes ─────────────────────────────────────────────────────
    final Paint eyePaint = Paint()..color = eye;
    final Paint glow = Paint()
      ..color = eye.withValues(alpha: 0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    const double eyeH = 9.0;
    // Startled eyes go wide for the length of the hop.
    final double startle = poke == 0 ? 1.0 : 1.0 + math.sin(poke * math.pi) * 0.35;
    final double h = math.max(1.2, eyeH * openness * startle);
    for (final double dx in <double>[-8, 8]) {
      final Rect e = Rect.fromCenter(
          center: Offset(50 + dx, 49), width: 7.5, height: h);
      final RRect re = RRect.fromRectAndRadius(e, const Radius.circular(3.4));
      canvas.drawRRect(re, glow);
      canvas.drawRRect(re, eyePaint);
    }

    // ── mouth ────────────────────────────────────────────────────
    final Paint mouth = Paint()
      ..color = const Color(0xFF5A6B79)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final Path m = Path();
    switch (mood) {
      case MascotMood.content:
        // small smirk
        m.moveTo(44, 68);
        m.quadraticBezierTo(50, 72.5, 56, 68);
      case MascotMood.alert:
        // flat, unimpressed
        m.moveTo(44, 69);
        m.lineTo(56, 69);
      case MascotMood.overdue:
        // turned down — he's been waiting
        m.moveTo(44, 71);
        m.quadraticBezierTo(50, 66.5, 56, 71);
      case MascotMood.idle:
        m.moveTo(45, 68.5);
        m.quadraticBezierTo(50, 70.5, 55, 68.5);
    }
    canvas.drawPath(m, mouth);

    // ── wrench ───────────────────────────────────────────────────
    // Drawn LAST: a tool he's holding sits in front of him. Behind the
    // body the ear cup ate half the head and it read as a spoon.
    canvas.save();
    canvas.translate(84, 74);
    canvas.rotate(-0.24 + tilt + spin);
    final Paint steel = Paint()..color = _steel;

    // Shaft.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-3.0, -26, 3.0, 12),
        const Radius.circular(2.8),
      ),
      steel,
    );
    // Open-end head: a disc with a wide V bitten out of the top. A stroked
    // arc reads as a hook and a narrow notch reads as a spoon — the bite
    // has to be obvious for this to say "wrench" at phone size.
    final Path head = Path()
      ..addOval(Rect.fromCircle(center: const Offset(0, -28), radius: 9.5));
    final Path notch = Path()
      ..moveTo(-6.4, -42)
      ..lineTo(6.4, -42)
      ..lineTo(0.0, -24.5)
      ..close();
    canvas.drawPath(
        Path.combine(PathOperation.difference, head, notch), steel);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GremlinPainter old) =>
      old.t != t || old.poke != poke || old.eye != eye || old.mood != mood;
}
