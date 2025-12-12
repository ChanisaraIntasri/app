import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import 'confirm_capture_page.dart';
import 'disease.dart'; // ✅ 1. Import ไฟล์ disease.dart เข้ามา

// import 'diagnosis_result_page.dart'; // ไม่ได้ใช้แล้ว
// import '../../services/citrus_model_api.dart'; // ไม่ได้ใช้แล้ว (ถ้าไม่ต้องยิง AI)

const kOrange = Color(0xFFFF7A00);

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
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

      _index = _cams.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
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
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _initFuture = ctrl.initialize().then((_) async {
      await ctrl.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
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

  Future<void> _capture() async {
    final cam = _ctrl;
    if (cam == null || !cam.value.isInitialized || _busy) return;

    _busy = true;
    try {
      // 1. ถ่ายรูป
      final shot = await cam.takePicture();
      if (!mounted) return;

      // 2. ไปหน้า ConfirmCapturePage เพื่อดูรูปและกดยืนยัน/ยกเลิก
      final useIt = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ConfirmCapturePage(imagePath: shot.path),
        ),
      );

      // 3. ถ้าผู้ใช้กดยืนยัน (useIt == true)
      if (useIt == true && mounted) {
        
        // ✅ แก้ไขตรงนี้: เปลี่ยนไปหน้า DiseaseListScreen ทันที
        await Navigator.of(context).push(
          MaterialPageRoute(
            // ตรวจสอบชื่อ Class ในไฟล์ disease.dart ให้ตรงกัน (ปกติคือ DiseaseListScreen)
            builder: (_) => const DiseaseListScreen(), 
          ),
        );

        /* // --- หมายเหตุ: ถ้าต้องการส่งรูปที่ถ่ายไปด้วย ให้แก้บรรทัดข้างบนเป็น: ---
        // builder: (_) => DiseaseListScreen(capturedImage: File(shot.path)),
        // (และต้องไปแก้รับค่าที่ไฟล์ disease.dart ด้วย)
        */
      }

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

  /// ทำให้ preview กล้องเต็มจอแบบไม่บี้ภาพ
  Widget _buildCameraPreview(Size size) {
    final controller = _ctrl!;
    final value = controller.value;

    if (!value.isInitialized) {
      return const SizedBox.shrink();
    }

    final previewSize = value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }

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

  @override
  Widget build(BuildContext context) {
    if (_ctrl == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.of(context).size;
    final holeW = size.width * 0.90;
    final holeH = size.width * 0.90;
    final holeLeft = (size.width - holeW) / 2;
    final holeTop = (size.height - holeH) / 2.6;
    final holeRect = Rect.fromLTWH(holeLeft, holeTop, holeW, holeH);
    const holeRadius = 26.0;

    return Scaffold(
      body: FutureBuilder(
        future: _initFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            children: [
              Positioned.fill(
                child: _buildCameraPreview(size),
              ),

              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DimOverlayPainter(holeRect, holeRadius),
                  ),
                ),
              ),

              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CornerPainter(holeRect),
                  ),
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).maybePop(),
                        child: const Text(
                          'ยกเลิก',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                blurRadius: 4,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _toggleFlash,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            _flash
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Align(
                alignment: const Alignment(0, 0.88),
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'วิธีการสแกนภาพ',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                blurRadius: 6,
                                color: Colors.black87,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'ขั้นตอนแรก นำใบส้มที่ต้องการตรวจโรค\nมาอยู่ในเฟรมของกล้อง จากนั้นกดยืนยัน',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.35,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                blurRadius: 6,
                                color: Colors.black87,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _busy ? null : _capture,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kOrange,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'ยืนยัน',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ================= Overlay Painters =================

class _DimOverlayPainter extends CustomPainter {
  final Rect holeRect;
  final double radius;

  _DimOverlayPainter(this.holeRect, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    final hole =
        Path()..addRRect(RRect.fromRectXY(holeRect, radius, radius));
    final diff = Path.combine(
      PathOperation.difference,
      overlay,
      hole,
    );
    canvas.drawPath(
      diff,
      Paint()..color = Colors.black.withOpacity(0.45),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CornerPainter extends CustomPainter {
  final Rect holeRect;

  _CornerPainter(this.holeRect);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final cornerLen = holeRect.shortestSide * 0.22;
    final cornerRadius = cornerLen * 0.55;

    Path cornerPath(
      Offset origin, {
      bool flipX = false,
      bool flipY = false,
    }) {
      final p = Path()
        ..moveTo(0, cornerRadius)
        ..quadraticBezierTo(0, 0, cornerRadius, 0)
        ..lineTo(cornerLen, 0);
      final mx = Matrix4.identity()
        ..translate(origin.dx, origin.dy)
        ..scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0);
      return p.transform(mx.storage);
    }

    const pad = 10.0;
    final tl = Offset(holeRect.left + pad, holeRect.top + pad);
    final tr = Offset(holeRect.right - pad, holeRect.top + pad);
    final bl = Offset(holeRect.left + pad, holeRect.bottom - pad);
    final br = Offset(holeRect.right - pad, holeRect.bottom - pad);

    canvas.drawPath(cornerPath(tl), stroke);
    canvas.drawPath(cornerPath(tr, flipX: true), stroke);
    canvas.drawPath(cornerPath(bl, flipY: true), stroke);
    canvas.drawPath(cornerPath(br, flipX: true, flipY: true), stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}