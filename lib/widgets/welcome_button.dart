import 'package:flutter/material.dart';

class WelcomeButton extends StatefulWidget {
  const WelcomeButton({
    super.key,
    required this.buttonText,
    this.page, // ส่งหน้า (optional)
    this.onPressed, // หรือ callback เอง (optional)
    this.color = Colors.transparent,
    this.textColor = Colors.white,
    this.minHeight = 56,
    this.padding = const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    this.borderRadius, // มุมโค้ง (optional)
    // ===== Bounce options (เร็วขึ้น) =====
    this.enableBounce = true,
    this.pressedScale = 0.97, // ย่อน้อย หน้าตาดูคล่อง
    this.pressDuration = const Duration(milliseconds: 50),
    this.bounceDuration = const Duration(milliseconds: 200),
    this.afterBounceDelay = const Duration(milliseconds: 80),
  }) : assert(
         page != null || onPressed != null,
         'ต้องกำหนดอย่างน้อย 1 อย่าง: page หรือ onPressed',
       );

  final String buttonText;
  final Widget? page;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  // Bounce config
  final bool enableBounce;
  final double pressedScale;
  final Duration pressDuration;
  final Duration bounceDuration;
  final Duration afterBounceDelay;

  @override
  State<WelcomeButton> createState() => _WelcomeButtonState();
}

class _WelcomeButtonState extends State<WelcomeButton> {
  double _scale = 1.0;
  late Duration _animDuration;
  late Curve _curve;
  bool _busy = false; // กันกดซ้ำระหว่างแอนิเมชัน/นำทาง

  @override
  void initState() {
    super.initState();
    _animDuration = widget.bounceDuration;
    _curve = Curves.elasticOut;
  }

  void _pressDown() {
    if (!widget.enableBounce || _busy) return;
    setState(() {
      _animDuration = widget.pressDuration;
      _curve = Curves.easeOut;
      _scale = widget.pressedScale;
    });
  }

  void _bounceBack() {
    if (!widget.enableBounce) return;
    if (!mounted) return;
    setState(() {
      _animDuration = widget.bounceDuration;
      _curve = Curves.elasticOut;
      _scale = 1.0;
    });
  }

  void _onTapDown(TapDownDetails _) => _pressDown();

  void _onTapCancel() => _bounceBack(); // ปล่อยนิ้วออกนอกปุ่ม

  Future<void> _runBounceThen(VoidCallback action) async {
    if (_busy) return;
    _busy = true;
    try {
      if (widget.enableBounce) {
        // เผื่อเคส tap เร็วมาก onTapDown ยังไม่ทัน
        _pressDown();
        await Future.delayed(widget.pressDuration);

        _bounceBack();

        // เว้นให้เห็นเด้งก่อนค่อยทำ action (นำทาง/callback)
        await Future.delayed(widget.afterBounceDelay);
      }

      if (!mounted) return;
      action();
    } finally {
      _busy = false;
    }
  }

  void _onTap() {
    final go =
        widget.onPressed ??
        () {
          Navigator.of(context).push(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 220), // เร็วขึ้น
              pageBuilder: (_, __, ___) => widget.page!,
              transitionsBuilder: (context, animation, _, child) {
                final tween = Tween<Offset>(
                  begin: const Offset(0.05, 0.0),
                  end: Offset.zero,
                ).chain(CurveTween(curve: Curves.easeOutCubic));
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: animation.drive(tween),
                    child: child,
                  ),
                );
              },
            ),
          );
        };

    _runBounceThen(go); // เด้งก่อน แล้วค่อยไป
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        widget.borderRadius ?? const BorderRadius.all(Radius.circular(16));

    return AnimatedScale(
      scale: widget.enableBounce ? _scale : 1.0,
      duration: _animDuration,
      curve: _curve,
      child: AbsorbPointer(
        // กันกดซ้ำตอนแอนิเมชัน/กำลังนำทาง
        absorbing: _busy,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTapDown: _onTapDown,
            onTapCancel: _onTapCancel,
            onTap: _onTap,
            child: Ink(
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: radius,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: widget.minHeight),
                child: Padding(
                  padding: widget.padding,
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      widget.buttonText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: widget.textColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
