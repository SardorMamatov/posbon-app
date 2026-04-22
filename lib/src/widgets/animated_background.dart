import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class AnimatedAuroraBackground extends StatefulWidget {
  const AnimatedAuroraBackground({
    required this.child,
    this.intensity = 1.0,
    super.key,
  });

  final Widget child;
  final double intensity;

  @override
  State<AnimatedAuroraBackground> createState() => _AnimatedAuroraBackgroundState();
}

class _AnimatedAuroraBackgroundState extends State<AnimatedAuroraBackground>
    with TickerProviderStateMixin {
  late final AnimationController _slow;
  late final AnimationController _fast;

  @override
  void initState() {
    super.initState();
    _slow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _fast = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _slow.dispose();
    _fast.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppColors.background),
          AnimatedBuilder(
            animation: Listenable.merge([_slow, _fast]),
            builder: (context, _) {
              return CustomPaint(
                painter: _AuroraPainter(
                  slow: _slow.value,
                  fast: _fast.value,
                  intensity: widget.intensity,
                ),
                size: Size.infinite,
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.slow,
    required this.fast,
    required this.intensity,
  });

  final double slow;
  final double fast;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    void drawOrb({
      required Offset center,
      required double radius,
      required Color color,
      double blur = 120,
    }) {
      final paint = Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      canvas.drawCircle(center, radius, paint);
    }

    final a1 = slow * 2 * math.pi;
    final a2 = fast * 2 * math.pi;

    drawOrb(
      center: Offset(
        w * (0.25 + 0.12 * math.cos(a1)),
        h * (0.22 + 0.08 * math.sin(a1)),
      ),
      radius: w * 0.45,
      color: AppColors.accent.withValues(alpha: 0.12 * intensity),
      blur: 140,
    );
    drawOrb(
      center: Offset(
        w * (0.78 + 0.10 * math.sin(a2)),
        h * (0.28 + 0.05 * math.cos(a2)),
      ),
      radius: w * 0.38,
      color: const Color(0xFF3FB59A).withValues(alpha: 0.10 * intensity),
      blur: 130,
    );
    drawOrb(
      center: Offset(
        w * (0.50 + 0.22 * math.sin(a1 * 0.7)),
        h * (0.80 + 0.05 * math.cos(a2 * 0.6)),
      ),
      radius: w * 0.55,
      color: const Color(0xFF0E3C34).withValues(alpha: 0.40 * intensity),
      blur: 160,
    );

    for (var i = 0; i < 18; i++) {
      final seed = i * 12.9898;
      final x = ((math.sin(seed) + 1) / 2) * w;
      final baseY = ((math.cos(seed * 1.7) + 1) / 2) * h;
      final t = (slow + i * 0.055) % 1.0;
      final y = (baseY + (t - 0.5) * h * 0.6) % h;
      final opacity = (0.10 + 0.25 * math.sin((fast + i * 0.3) * math.pi * 2))
          .clamp(0.0, 0.35);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: opacity * intensity);
      canvas.drawCircle(Offset(x, y), 1.1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.slow != slow || oldDelegate.fast != fast;
}

class RotatingShield extends StatefulWidget {
  const RotatingShield({
    required this.child,
    this.duration = const Duration(seconds: 8),
    super.key,
  });

  final Widget child;
  final Duration duration;

  @override
  State<RotatingShield> createState() => _RotatingShieldState();
}

class _RotatingShieldState extends State<RotatingShield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class PulseRings extends StatefulWidget {
  const PulseRings({
    required this.size,
    required this.color,
    this.ringCount = 3,
    super.key,
  });

  final double size;
  final Color color;
  final int ringCount;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _PulsePainter(
              progress: _controller.value,
              color: widget.color,
              ringCount: widget.ringCount,
            ),
          );
        },
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.progress,
    required this.color,
    required this.ringCount,
  });

  final double progress;
  final Color color;
  final int ringCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (var i = 0; i < ringCount; i++) {
      final offset = (progress + i / ringCount) % 1.0;
      final radius = maxRadius * offset;
      final opacity = (1 - offset) * 0.55;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class RadarSweep extends StatefulWidget {
  const RadarSweep({
    required this.size,
    required this.color,
    super.key,
  });

  final double size;
  final Color color;

  @override
  State<RadarSweep> createState() => _RadarSweepState();
}

class _RadarSweepState extends State<RadarSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _RadarPainter(
              progress: _controller.value,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * (i / 3), ringPaint);
    }

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.55),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.75, 1.0, 1.0],
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, sweepPaint);

    final beamPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final angle = progress * 2 * math.pi - math.pi / 2;
    canvas.drawLine(
      center,
      Offset(center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle)),
      beamPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
