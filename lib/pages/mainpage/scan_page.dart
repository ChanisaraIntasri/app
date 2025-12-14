import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

import 'confirm_capture_page.dart';
import 'disease.dart'; // ✅ Import ไฟล์ disease.dart

const kPrimaryGreen = Color(0xFF005E33);

class ScanPage extends StatefulWidget {
  // ✅ ถ้าเปิดมาจาก "ต้นส้ม" ให้ส่ง id/name มาเพื่อบันทึกผลกลับ
  final String? treeId;
  final String? treeName;

  const ScanPage({
    super.key,
    this.treeId,
    this.treeName,
  });

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  CameraController? _ctrl;
  Future<void>? _initFuture;
  List<CameraDescription> _cams = [];
  int _index = 0;

  bool _busy = false;
  bool _flash = false;

  // ✅ pinch zoom
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _zoom = 1.0;
  double _baseZoom = 1.0;

  // ✅ tap to focus UI
  Offset? _focusUiPoint; // จุดวงโฟกัสบนหน้าจอ
  Timer? _focusHideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ ให้เหมือนกล้องจริง: เต็มจอ
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusHideTimer?.cancel();
    _ctrl?.dispose();

    // ✅ คืนค่า UI ปกติเมื่อออกจากกล้อง
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (c == null) return;

    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startSelected();
    }
  }

  Future<void> _init() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) throw 'ไม่พบกล้องในอุปกรณ์';

      // default: กล้องหลัง
      _index = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_index == -1) _index = 0;

      await _startSelected();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เปิดกล้องไม่ได้: $e')),
      );
    }
  }

  Future<void> _startSelected() async {
    final cam = _cams[_index];

    final ctrl = CameraController(
      cam,
      ResolutionPreset.high, // ✅ ให้เหมือนกล้องจริงขึ้น
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _initFuture = ctrl.initialize().then((_) async {
      await ctrl.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);

      // ✅ zoom range
      try {
        _minZoom = await ctrl.getMinZoomLevel();
        _maxZoom = await ctrl.getMaxZoomLevel();
        _zoom = _minZoom;
        await ctrl.setZoomLevel(_zoom);
      } catch (_) {
        _minZoom = 1.0;
        _maxZoom = 1.0;
        _zoom = 1.0;
      }
    });

    await _ctrl?.dispose();
    _ctrl = ctrl;

    if (mounted) setState(() {});
  }

  Future<void> _toggleFlash() async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;

    _flash = !_flash;
    await c.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_cams.length < 2) return;
    _index = (_index + 1) % _cams.length;
    await _startSelected();
  }

  double _clampZoom(double z) => z.clamp(_minZoom, _maxZoom);

  Future<void> _setZoom(double z) async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;

    final next = _clampZoom(z);
    _zoom = next;
    await c.setZoomLevel(next);
    if (mounted) setState(() {});
  }

  Future<void> _onTapToFocus(TapDownDetails d, Size viewSize) async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;

    // จุด UI
    setState(() => _focusUiPoint = d.localPosition);
    _focusHideTimer?.cancel();
    _focusHideTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusUiPoint = null);
    });

    // แปลงเป็น offset 0..1 สำหรับกล้อง
    final nx = (d.localPosition.dx / viewSize.width).clamp(0.0, 1.0);
    final ny = (d.localPosition.dy / viewSize.height).clamp(0.0, 1.0);
    final p = Offset(nx, ny);

    try {
      await c.setFocusPoint(p);
      await c.setExposurePoint(p);
    } catch (_) {
      // บางอุปกรณ์อาจไม่รองรับ
    }
  }

  Future<void> _capture() async {
    final cam = _ctrl;
    if (cam == null || !cam.value.isInitialized || _busy) return;

    _busy = true;
    try {
      // 1) ถ่ายรูป
      final shot = await cam.takePicture();
      if (!mounted) return;

      // 2) ไปหน้า Confirm เพื่อดูรูปและกดยืนยัน/ยกเลิก
      final useIt = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ConfirmCapturePage(imagePath: shot.path),
        ),
      );

      if (useIt != true || !mounted) return;

      // 3) เลือกโรค และให้ disease.dart ส่งกลับด้วย Navigator.pop(context, 'ชื่อโรค')
      final String? selectedDisease = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const DiseaseListScreen()),
      );

      if (!mounted || selectedDisease == null || selectedDisease.trim().isEmpty) return;

      // ✅ ถ้าเปิดมาจากต้นส้ม -> ส่งผลกลับไปให้ SharePage บันทึกลงต้นนั้น
      if (widget.treeId != null) {
        Navigator.pop(context, {
          'disease': selectedDisease.trim(),
          'imagePath': shot.path,
          'scannedAt': DateTime.now().toIso8601String(),
        });
        return;
      }

      // ถ้าเปิดจากแท็บกล้องเฉย ๆ ก็ไม่ต้อง pop (ตามพฤติกรรมเดิม)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ได้ผลสแกน: ${selectedDisease.trim()}')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  /// preview เต็มจอแบบไม่บี้
  Widget _buildCameraPreview(Size size) {
    final controller = _ctrl!;
    final value = controller.value;

    if (!value.isInitialized) return const SizedBox.shrink();

    final previewSize = value.previewSize;
    if (previewSize == null) return CameraPreview(controller);

    final previewAspect = previewSize.height / previewSize.width;

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: size.width,
        height: size.width * previewAspect,
        child: CameraPreview(controller),
      ),
    );
  }

  // ✅ Path ใบไม้ “เหมือนจริงขึ้น” + มีก้านเล็ก ๆ
  Path _leafPathFromRect(Rect r) {
    final w = r.width;
    final h = r.height;
    final cx = r.center.dx;

    final top = Offset(cx, r.top);
    final bottomTip = Offset(cx, r.bottom - h * 0.03);

    // ใบอวบช่วงกลาง
    final left = r.left + w * 0.06;
    final right = r.right - w * 0.06;

    // คุมโค้งให้ดูเป็นใบจริง
    final c1 = Offset(left, r.top + h * 0.20);
    final c2 = Offset(r.left + w * 0.04, r.top + h * 0.62);

    final c3 = Offset(r.right - w * 0.04, r.top + h * 0.62);
    final c4 = Offset(right, r.top + h * 0.20);

    final p = Path()..moveTo(top.dx, top.dy);

    // ด้านซ้ายลง
    p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, bottomTip.dx, bottomTip.dy);

    // ด้านขวากลับขึ้น
    p.cubicTo(c3.dx, c3.dy, c4.dx, c4.dy, top.dx, top.dy);

    p.close();

    // ก้านใบ (stem) เล็ก ๆ
    final stemW = w * 0.08;
    final stemH = h * 0.12;
    final stemRect = Rect.fromCenter(
      center: Offset(cx, r.bottom + stemH * 0.18),
      width: stemW,
      height: stemH,
    );
    final stem = Path()
      ..addRRect(
        RRect.fromRectXY(stemRect, stemW * 0.6, stemW * 0.6),
      );

    // รวมใบ + ก้าน
    return Path.combine(PathOperation.union, p, stem);
  }

  @override
  Widget build(BuildContext context) {
    if (_ctrl == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.of(context).size;

    // ✅ กรอบใบไม้ (เหมาะกับ “ใบเดียว”)
    final leafW = size.width * 0.70;
    final leafH = size.width * 0.95;
    final left = (size.width - leafW) / 2;
    final top = (size.height - leafH) / 2.2;
    final leafRect = Rect.fromLTWH(left, top, leafW, leafH);
    final leafPath = _leafPathFromRect(leafRect);

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder(
        future: _initFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          return LayoutBuilder(
            builder: (context, cons) {
              final viewSize = Size(cons.maxWidth, cons.maxHeight);

              return Stack(
                children: [
                  // ✅ กล้อง + gesture เหมือนกล้องจริง (แตะโฟกัส + pinch zoom)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _onTapToFocus(d, viewSize),
                      onScaleStart: (_) => _baseZoom = _zoom,
                      onScaleUpdate: (d) {
                        // pinch zoom
                        if (_maxZoom <= _minZoom) return;
                        final next = _baseZoom * d.scale;
                        _setZoom(next);
                      },
                      child: _buildCameraPreview(size),
                    ),
                  ),

                  // ✅ ดิมรอบนอก + เว้นช่องใบไม้
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _DimLeafOverlayPainter(leafPath),
                      ),
                    ),
                  ),

                  // ✅ เส้นขอบใบไม้ + เส้นกลางใบ
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _LeafOutlinePainter(leafPath),
                      ),
                    ),
                  ),

                  // ✅ วงโฟกัส
                  if (_focusUiPoint != null)
                    Positioned(
                      left: _focusUiPoint!.dx - 28,
                      top: _focusUiPoint!.dy - 28,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                  // ✅ Top bar เหมือนกล้องจริง
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _TopIconButton(
                            icon: Icons.close_rounded,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          Row(
                            children: [
                              _TopIconButton(
                                icon: _flash ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                                onTap: _toggleFlash,
                              ),
                              const SizedBox(width: 10),
                              _TopIconButton(
                                icon: Icons.cameraswitch_rounded,
                                onTap: _switchCamera,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ✅ Bottom controls เหมือนกล้องจริง
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.only(
                        left: 18,
                        right: 18,
                        top: 14,
                        bottom: MediaQuery.of(context).padding.bottom + 18,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0xAA000000),
                            Color(0xE6000000),
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ข้อความสั้น ๆ (ไม่บังเหมือนเดิม)
                          const Text(
                            'นำ “ใบส้ม 1 ใบ” ให้อยู่ในกรอบใบไม้',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // ซูมแสดง (เล็ก ๆ)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  '${_zoom.toStringAsFixed(1)}x',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),

                              // ✅ ปุ่มชัตเตอร์วงกลมแบบกล้องจริง
                              GestureDetector(
                                onTap: _busy ? null : _capture,
                                child: Container(
                                  width: 78,
                                  height: 78,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 5),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _busy ? Colors.white38 : kPrimaryGreen,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // ช่องว่างให้สมดุล
                              const SizedBox(width: 48),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ================= Overlay Painters =================

class _DimLeafOverlayPainter extends CustomPainter {
  final Path leafPath;
  _DimLeafOverlayPainter(this.leafPath);

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);

    final diff = Path.combine(
      PathOperation.difference,
      overlay,
      leafPath,
    );

    canvas.drawPath(
      diff,
      Paint()..color = Colors.black.withOpacity(0.45),
    );
  }

  @override
  bool shouldRepaint(covariant _DimLeafOverlayPainter oldDelegate) {
    return oldDelegate.leafPath != leafPath;
  }
}

class _LeafOutlinePainter extends CustomPainter {
  final Path leafPath;
  _LeafOutlinePainter(this.leafPath);

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(leafPath, outline);

    // เส้นกลางใบ (midrib)
    final b = leafPath.getBounds();
    final cx = b.center.dx;

    final midrib = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    final top = Offset(cx, b.top + b.height * 0.08);
    final bottom = Offset(cx, b.bottom - b.height * 0.08);

    final midPath = Path()
      ..moveTo(top.dx, top.dy)
      ..quadraticBezierTo(
        cx + b.width * 0.03,
        b.center.dy,
        bottom.dx,
        bottom.dy,
      );

    canvas.drawPath(midPath, midrib);

    // เส้นแขนงเล็ก ๆ (ให้ดูเป็นใบไม้จริงขึ้น)
    final vein = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    for (int i = 1; i <= 4; i++) {
      final t = i / 5.0;
      final y = math.max(top.dy + (bottom.dy - top.dy) * t, top.dy + 8);
      final len = b.width * (0.22 + i * 0.02);

      // ซ้าย
      final p1 = Path()
        ..moveTo(cx, y)
        ..quadraticBezierTo(cx - len * 0.35, y - 8, cx - len, y - 2);
      canvas.drawPath(p1, vein);

      // ขวา
      final p2 = Path()
        ..moveTo(cx, y)
        ..quadraticBezierTo(cx + len * 0.35, y - 8, cx + len, y - 2);
      canvas.drawPath(p2, vein);
    }
  }

  @override
  bool shouldRepaint(covariant _LeafOutlinePainter oldDelegate) {
    return oldDelegate.leafPath != leafPath;
  }
}

// ================= UI Widgets =================

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
