import 'dart:math';
import 'package:flutter/material.dart';

const Color kPrimaryGreen = Color(0xFF005E33);

class TreatmentSuccessPage extends StatefulWidget {
  final String message;

  const TreatmentSuccessPage({
    super.key,
    this.message = 'ยินดีด้วย',
  });

  @override
  State<TreatmentSuccessPage> createState() => _TreatmentSuccessPageState();
}

class _Burst {
  final Offset center01; // 0..1
  final int dots;
  final double maxR;
  final double phase;

  _Burst({required this.center01, required this.dots, required this.maxR, required this.phase});
}

class _TreatmentSuccessPageState extends State<TreatmentSuccessPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Burst> _bursts;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);

    final rnd = Random(42);
    _bursts = List.generate(6, (_) {
      return _Burst(
        center01: Offset(0.15 + rnd.nextDouble() * 0.70, 0.15 + rnd.nextDouble() * 0.35),
        dots: 10 + rnd.nextInt(8),
        maxR: 28 + rnd.nextDouble() * 34,
        phase: rnd.nextDouble() * pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _FireworksPainter(t: _c.value, bursts: _bursts),
                          child: const SizedBox.expand(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${widget.message} 🎉',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'โรคหายแล้ว ขอบคุณที่ดูแลสวนส้มของคุณอย่างสม่ำเสมอ',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      ),
                      child: const Text('กลับหน้าหลัก', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FireworksPainter extends CustomPainter {
  final double t; // 0..1
  final List<_Burst> bursts;

  _FireworksPainter({required this.t, required this.bursts});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final double grow = 0.35 + 0.65 * t;
    final double alpha = (0.25 + 0.75 * (1 - (t - 0.5).abs() * 2)).clamp(0.0, 1.0);

    for (final b in bursts) {
      final center = Offset(b.center01.dx * size.width, b.center01.dy * size.height);

      for (int i = 0; i < b.dots; i++) {
        final a = (2 * pi * i / b.dots) + b.phase;
        final r = b.maxR * grow;
        final p = center + Offset(cos(a) * r, sin(a) * r);

        final isWhite = (i % 4 == 0);
        paint.color = (isWhite ? Colors.white : kPrimaryGreen).withOpacity(alpha);

        final dotR = isWhite ? 3.2 : 2.6;
        canvas.drawCircle(p, dotR, paint);
      }

      paint.color = kPrimaryGreen.withOpacity(alpha * 0.65);
      canvas.drawCircle(center, 3.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.bursts != bursts;
  }
}
