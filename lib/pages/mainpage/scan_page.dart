import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import '../diagnosis/disease_diagnosis_page.dart';
import '../diagnosis/analysis_loading_page.dart';
import '../diagnosis/disease_quick_result_page.dart';

const kPrimaryGreen = Color(0xFF005E33);

// ====== ตั้งค่า API โมเดล ======
const String kModelApiBase = String.fromEnvironment(
  'MODEL_API_BASE',
  defaultValue: 'https://north-cambridge-partners-gifts.trycloudflare.com',
);
const String kModelPredictPath = '/predict';
const bool kUseRealModelApi = true;

// ====== fallback map กรณีโมเดลส่งมาไม่มี disease_id ======
class _DiseaseMeta {
  final String id; // disease_id ใน DB
  final String th;
  final String en;
  const _DiseaseMeta(this.id, this.th, this.en);
}

const Map<String, _DiseaseMeta> kDiseaseNameMap = {
  'ใบจุดดำ': _DiseaseMeta('1', 'ใบจุดดำ', 'black_spot'),
  'ใบจุดสีน้ำตาล': _DiseaseMeta('2', 'ใบจุดสีน้ำตาล', 'brown_spot'),
  'ใบไหม้': _DiseaseMeta('3', 'ใบไหม้', 'leaf_blight'),
  'ใบเหลือง': _DiseaseMeta('4', 'ใบเหลือง', 'leaf_yellowing'),
  'ใบหงิกงอ': _DiseaseMeta('5', 'ใบหงิกงอ', 'leaf_curling'),
  'ใบปกติ': _DiseaseMeta('6', 'ใบปกติ', 'healthy'),
};

class ScanPage extends StatefulWidget {
  final String? treeId;
  final String? treeName;

  // ✅ ถ้า true: สแกนแบบบอกผลโรคอย่างเดียว (ไม่เข้ากระบวนการตอบคำถาม)
  final bool quickResultOnly;

  const ScanPage({
    super.key,
    this.treeId,
    this.treeName,
    this.quickResultOnly = false,
  });

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  CameraController? _ctrl;
  List<CameraDescription> _cams = [];
  int _camIndex = 0;

  bool _isBusy = false;
  bool _flashOn = false;

  // ✅ เก็บข้อความ error หากเปิดกล้องไม่สำเร็จ (ยังเลือกจากแกลลอรี่/ถ่ายแบบ fallback ได้)
  String? _cameraInitError;

  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 8.0;
  double _baseZoom = 1.0;

  final ImagePicker _picker = ImagePicker();

  // =========================
  // ✅ แจ้งเตือนแบบบล็อกด้านบน (แทน SnackBar ที่อยู่ล่างเกิน)
  // =========================
  String? _topNotice;
  Timer? _topNoticeTimer;

  // ✅ เก็บ tree context เผื่อหน้าอื่นเรียก ScanPage แบบไม่ได้ส่ง args มา
  String? _resolvedTreeId;
  String? _resolvedTreeName;

  // ✅ โหมดถ่าย/สแกนแบบไม่เลือกต้น (เปิดจากเมนูกล้อง): ไม่ผูกต้น, ไม่บันทึก
  late final bool _standaloneMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ ถ้าเปิดหน้า Scan โดยไม่ได้ส่ง treeId/treeName มา (เช่น กดเมนูกล้อง)
    // ให้ถือว่าเป็นการ “ถ่าย/สแกนเฉยๆ” ไม่ดึงต้นจาก prefs และไม่บันทึก
    _standaloneMode = widget.quickResultOnly ||
        (_t(widget.treeId).isEmpty && _t(widget.treeName).isEmpty);

    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _topNoticeTimer?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ป้องกันกล้องพังเวลา app ไป background
    final CameraController? controller = _ctrl;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCameraSafely();
    }
  }

  Future<void> _init() async {
    await _resolveTreeContext();
    await _initCameraSafely();
  }

  Future<void> _resolveTreeContext() async {
    // ✅ โหมดถ่ายเฉยๆ: ไม่ต้อง resolve ต้น และไม่ใช้ค่าเดิมจาก prefs
    if (_standaloneMode) {
      _resolvedTreeId = null;
      _resolvedTreeName = null;
      return;
    }

    // ใช้ค่าที่ส่งเข้ามาก่อน
    if (_t(widget.treeId).isNotEmpty) {
      _resolvedTreeId = widget.treeId;
      _resolvedTreeName = widget.treeName;
      return;
    }

    // fallback: อ่านจาก SharedPreferences หรือค่าอื่น ๆ ที่โปรเจกต์คุณเก็บไว้
    // (ถ้าในโปรเจกต์คุณเก็บ key อื่น ให้ปรับ key ตรงนี้)
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTreeId = prefs.getString('selected_tree_id');
      final lastTreeName = prefs.getString('selected_tree_name');
      if (_t(lastTreeId).isNotEmpty) {
        _resolvedTreeId = lastTreeId;
        _resolvedTreeName = lastTreeName;
      }
    } catch (_) {}
  }

  Future<void> _initCameraSafely() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        setState(() => _cameraInitError = 'ไม่พบกล้องในอุปกรณ์');
        return;
      }
      _camIndex = 0;
      await _startCamera(_cams[_camIndex]);
    } catch (e) {
      setState(() => _cameraInitError = 'เปิดกล้องไม่สำเร็จ: $e');
    }
  }

  Future<void> _startCamera(CameraDescription cam) async {
    try {
      final controller = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _ctrl = controller;
      await controller.initialize();

      // ค่า zoom
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _zoom = 1.0;
      _baseZoom = _zoom;

      // flash
      await controller.setFlashMode(FlashMode.off);
      _flashOn = false;

      setState(() => _cameraInitError = null);
    } catch (e) {
      setState(() => _cameraInitError = 'เปิดกล้องไม่สำเร็จ: $e');
    }
  }

  void _showTopNotice(String msg, {int ms = 2500}) {
    _topNoticeTimer?.cancel();
    setState(() => _topNotice = msg);
    _topNoticeTimer = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      setState(() => _topNotice = null);
    });
  }

  void _toast(String msg) => _showTopNotice(msg);

  String _t(String? s) => (s ?? '').trim();

  String _scanTitle() {
    if (_standaloneMode) return 'กำลังสแกนใบส้ม';

    final name = _t(_resolvedTreeName ?? widget.treeName);
    if (name.isEmpty) return 'กำลังสแกนต้นส้ม';

    // กันข้อความซ้ำ เช่น treeName เก็บเป็น "ต้นที่ 1" อยู่แล้ว
    if (name.startsWith('ต้นที่')) return 'กำลังสแกน$name';
    return 'กำลังสแกนต้นที่ $name';
  }

  String? _firstNonEmpty(List<String?> list) {
    for (final s in list) {
      final v = _t(s);
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  Future<void> _toggleFlash() async {
    final controller = _ctrl;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (_flashOn) {
        await controller.setFlashMode(FlashMode.off);
      } else {
        await controller.setFlashMode(FlashMode.torch);
      }
      setState(() => _flashOn = !_flashOn);
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cams.isEmpty) return;
    _camIndex = (_camIndex + 1) % _cams.length;
    await _ctrl?.dispose();
    await _startCamera(_cams[_camIndex]);
  }

  // ====== Zoom (pinch) ======
  void _onScaleStart(ScaleStartDetails d) {
    _baseZoom = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) async {
    final controller = _ctrl;
    if (controller == null || !controller.value.isInitialized) return;

    final newZoom = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
    _zoom = newZoom;
    try {
      await controller.setZoomLevel(newZoom);
    } catch (_) {}
  }

  // =============================
  // ✅ ถ่ายรูปเป็นไฟล์ (Camera)
  // =============================
  Future<File?> _takePictureToFile() async {
    final controller = _ctrl;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }
    try {
      final x = await controller.takePicture();
      return File(x.path);
    } catch (_) {
      return null;
    }
  }

  // =============================
  // ✅ fallback ถ่ายผ่าน image_picker (camera)
  // =============================
  Future<File?> _pickFromCameraFallback() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.camera);
      if (x == null) return null;
      return File(x.path);
    } catch (_) {
      return null;
    }
  }

  // =============================
  // ✅ เลือกจากแกลลอรี่
  // =============================
  Future<File?> _pickFromGallery() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery);
      if (x == null) return null;
      return File(x.path);
    } catch (_) {
      return null;
    }
  }

  // =============================
  // ✅ เรียกโมเดล API (multipart)
  // =============================
  Future<Map<String, dynamic>?> _callModelApi(File imageFile) async {
    if (!kUseRealModelApi) {
      // mock result
      await Future<void>.delayed(const Duration(seconds: 1));
      return {
        'disease_name': 'ใบจุดดำ',
        'disease_id': '1',
        'compare_image_url': null,
        'confidence': 0.87,
        'leaf_confidence': 0.95,
      };
    }

    final uri = Uri.parse('$kModelApiBase$kModelPredictPath');

    try {
      final req = http.MultipartRequest('POST', uri);
      req.files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final streamed = await req.send().timeout(const Duration(seconds: 45));
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return {
          'ok': false,
          'error': 'HTTP ${res.statusCode}',
          'detail': res.body,
        };
      }

      final Map<String, dynamic> jsonMap = jsonDecode(res.body);
      return jsonMap;
    } on TimeoutException {
      return {
        'ok': false,
        'error': 'timeout',
        'detail': 'หมดเวลารอโมเดลวิเคราะห์ กรุณาลองใหม่',
      };
    } catch (e) {
      return {
        'ok': false,
        'error': 'exception',
        'detail': e.toString(),
      };
    }
  }

  // =============================
  // ✅ แสดงหน้า AnalysisLoadingPage ระหว่างรอโมเดลวิเคราะห์
  // =============================
  static const String _analysisLoadingRouteName = '__analysis_loading__';

  Future<T?> _runWithAnalysisLoading<T>(Future<T?> Function() task) async {
    // push หน้า loading (กันกด back ด้วย WillPopScope ใน AnalysisLoadingPage)
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: _analysisLoadingRouteName),
        builder: (_) => const AnalysisLoadingPage(),
      ),
    );

    // ให้มีเวลาวาดหน้า loading ก่อนเริ่มยิง API (กันเครื่องช้า/จอค้าง)
    await Future<void>.delayed(const Duration(milliseconds: 60));

    try {
      return await task();
    } finally {
      if (mounted) {
        // pop เฉพาะถ้าหน้าบนสุดคือ loading เท่านั้น (ป้องกัน pop หน้าอื่นผิด)
        Navigator.of(context).popUntil(
          (route) => route.settings.name != _analysisLoadingRouteName,
        );
      }
    }
  }

  /// ✅ ปรับให้ตรงกับ constructor จริงของ DiseaseDiagnosisPage
  Future<void> _goToDiagnosisPage({
    required File imageFile,
    required String diseaseId,
    String? diseaseNameTh,
    String? diseaseNameEn,
    String? compareImageUrl,
    double? scanConfidence, // 0..1 หรือ 0..100
    double? leafConfidence, // 0..1 หรือ 0..100
  }) async {
    var treeId = _t(_resolvedTreeId ?? widget.treeId);
    if (treeId.isEmpty) {
      // ✅ เผื่อเปิดจาก bottom nav / route ไม่ได้ส่ง args
      await _resolveTreeContext();
      treeId = _t(_resolvedTreeId);
    }

    if (treeId.isEmpty) {
      _toast('ไม่พบ treeId ของต้นส้ม');
      return;
    }

    final treeName = _firstNonEmpty([
      _resolvedTreeName,
      _t(widget.treeName).isNotEmpty ? _t(widget.treeName) : null,
    ]);

    PersistentNavBarNavigator.pushNewScreen(
      context,
      screen: DiseaseDiagnosisPage(
        treeId: treeId,
        treeName: treeName,
        diseaseId: diseaseId,
        diseaseNameTh: diseaseNameTh,
        diseaseNameEn: diseaseNameEn,
        compareImageUrl: compareImageUrl,
        userImageFile: imageFile, // ✅ ส่งรูปผู้ใช้ตามที่หน้า diagnosis รองรับ
        scanConfidence: scanConfidence,
        leafConfidence: leafConfidence,
      ),
      withNavBar: false, // ✅ ซ่อนแถบล่างตอนอยู่หน้า Scan
      pageTransitionAnimation: PageTransitionAnimation.cupertino,
    );
  }

  Future<void> _goToQuickResultPage({
    required File imageFile,
    required String diseaseId,
    required String diseaseNameTh,
    String? diseaseNameEn,
    String? compareImageUrl,
    double? scanConfidence,
  }) async {
    PersistentNavBarNavigator.pushNewScreen(
      context,
      screen: DiseaseQuickResultPage(
        diseaseId: diseaseId,
        diseaseNameTh: diseaseNameTh,
        diseaseNameEn: diseaseNameEn,
        compareImageUrl: compareImageUrl,
        userImageFile: imageFile,
        scanConfidence: scanConfidence,
      ),
      withNavBar: false,
      pageTransitionAnimation: PageTransitionAnimation.cupertino,
    );
  }

  Future<void> _onCapturePressed() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    try {
      File? file = await _takePictureToFile();
      if (file == null) {
        // ✅ fallback: บางเครื่อง/บางเคส CameraController อาจยังไม่พร้อมหรือ permission ไม่ผ่าน
        file = await _pickFromCameraFallback();
      }
      if (file == null) {
        _toast('ไม่สามารถถ่ายภาพได้ (กรุณาอนุญาตสิทธิ์กล้อง หรือเลือกจากแกลลอรี่)');
        return;
      }

      final File imageFile = file!;

      // ✅ กันกรณีไฟล์หาย/อ่านไม่ได้
      if (!await imageFile.exists()) {
        _toast('ไม่พบไฟล์รูปภาพที่ถ่าย (ลองถ่ายใหม่อีกครั้ง)');
        return;
      }

      // ✅ ส่งโมเดล -> ไปหน้าวินิจฉัย (แสดงหน้า loading ระหว่างรอ)
      final result = await _runWithAnalysisLoading(() => _callModelApi(imageFile));

      if (result != null && result['ok'] == false) {
        // ✅ กรณี API ตอบกลับ ok:false (เช่น ไม่พบใบส้ม / ความมั่นใจต่ำ)
        final msg = (result['detail'] ??
                result['error'] ??
                result['disease_name'] ??
                result['message'] ??
                'ไม่สามารถวิเคราะห์ภาพได้ กรุณาถ่ายใหม่ให้ชัดและให้ใบอยู่ในกรอบ')
            .toString();
        _toast(msg);
        return;
      }

      String diseaseName = 'ไม่ทราบโรค';
      String? diseaseId;
      String? compareImageUrl;
      double? scanConfidence; // 0..1 หรือ 0..100
      double? leafConfidence; // 0..1 หรือ 0..100

      if (result != null) {
        final dn = result['disease_name'] ?? result['label'] ?? result['name'];
        if (dn != null) diseaseName = dn.toString();

        final did = result['disease_id'] ?? result['id'];
        if (did != null) diseaseId = did.toString();

        final cmp = result['compare_image_url'] ?? result['compareImageUrl'];
        if (cmp != null) compareImageUrl = cmp.toString();

        // ✅ percent ความมั่นใจจากโมเดล (บางทีอาจส่งมาเป็น 0..1 หรือ 0..100)
        final c = result['confidence'];
        if (c is num) {
          scanConfidence = c.toDouble();
        } else if (c != null) {
          scanConfidence = double.tryParse(c.toString());
        }

        final lc = result['leaf_confidence'] ?? result['leafConfidence'];
        if (lc is num) {
          leafConfidence = lc.toDouble();
        } else if (lc != null) {
          leafConfidence = double.tryParse(lc.toString());
        }
      }

      // ✅ map id ถ้าโมเดลไม่ส่งมา
      if (_t(diseaseId).isEmpty) {
        final meta = kDiseaseNameMap[diseaseName];
        if (meta != null) {
          diseaseId = meta.id;
        }
      }

      // ✅ ถ้ายังไม่เจอ diseaseId ให้เตือน
      if (_t(diseaseId).isEmpty) {
        _toast('ไม่พบรหัสโรคจากโมเดล');
        return;
      }

      final meta = kDiseaseNameMap[diseaseName];
      final diseaseNameTh = meta?.th ?? diseaseName;
      final diseaseNameEn = meta?.en;

      // ✅ ถ้าเปิดจากเมนูกล้อง (ไม่เลือกต้น) -> ไปหน้าแสดงผลแบบเร็ว (ไม่บันทึก)
      if (_standaloneMode) {
        await _goToQuickResultPage(
          imageFile: imageFile,
          diseaseId: diseaseId!,
          diseaseNameTh: diseaseNameTh,
          diseaseNameEn: diseaseNameEn,
          compareImageUrl: compareImageUrl,
          scanConfidence: scanConfidence,
        );
      } else {
        // ✅ ไปหน้า diagnosis (ผูกต้น + เข้ากระบวนการถาม/บันทึก)
        await _goToDiagnosisPage(
          imageFile: imageFile,
          diseaseId: diseaseId!,
          diseaseNameTh: diseaseNameTh,
          diseaseNameEn: diseaseNameEn,
          compareImageUrl: compareImageUrl,
          scanConfidence: scanConfidence,
          leafConfidence: leafConfidence,
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _onGalleryPressed() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    try {
      final file = await _pickFromGallery();
      if (file == null) return;

      if (!await file.exists()) {
        _toast('ไม่พบไฟล์รูปภาพ (ลองเลือกใหม่)');
        return;
      }

      // ✅ ส่งโมเดล -> ไปหน้าวินิจฉัย (แสดงหน้า loading ระหว่างรอ)
      final result = await _runWithAnalysisLoading(() => _callModelApi(file));

      if (result != null && result['ok'] == false) {
        final msg = (result['detail'] ??
                result['error'] ??
                result['disease_name'] ??
                result['message'] ??
                'ไม่สามารถวิเคราะห์ภาพได้ กรุณาเลือกรูปใบส้มให้ชัด')
            .toString();
        _toast(msg);
        return;
      }

      String diseaseName = 'ไม่ทราบโรค';
      String? diseaseId;
      String? compareImageUrl;
      double? scanConfidence;
      double? leafConfidence;

      if (result != null) {
        final dn = result['disease_name'] ?? result['label'] ?? result['name'];
        if (dn != null) diseaseName = dn.toString();

        final did = result['disease_id'] ?? result['id'];
        if (did != null) diseaseId = did.toString();

        final cmp = result['compare_image_url'] ?? result['compareImageUrl'];
        if (cmp != null) compareImageUrl = cmp.toString();

        final c = result['confidence'];
        if (c is num) {
          scanConfidence = c.toDouble();
        } else if (c != null) {
          scanConfidence = double.tryParse(c.toString());
        }

        final lc = result['leaf_confidence'] ?? result['leafConfidence'];
        if (lc is num) {
          leafConfidence = lc.toDouble();
        } else if (lc != null) {
          leafConfidence = double.tryParse(lc.toString());
        }
      }

      if (_t(diseaseId).isEmpty) {
        final meta = kDiseaseNameMap[diseaseName];
        if (meta != null) diseaseId = meta.id;
      }

      if (_t(diseaseId).isEmpty) {
        _toast('ไม่พบรหัสโรคจากโมเดล');
        return;
      }

      final meta = kDiseaseNameMap[diseaseName];
      final diseaseNameTh = meta?.th ?? diseaseName;
      final diseaseNameEn = meta?.en;

      if (_standaloneMode) {
        await _goToQuickResultPage(
          imageFile: file,
          diseaseId: diseaseId!,
          diseaseNameTh: diseaseNameTh,
          diseaseNameEn: diseaseNameEn,
          compareImageUrl: compareImageUrl,
          scanConfidence: scanConfidence,
        );
      } else {
        await _goToDiagnosisPage(
          imageFile: file,
          diseaseId: diseaseId!,
          diseaseNameTh: diseaseNameTh,
          diseaseNameEn: diseaseNameEn,
          compareImageUrl: compareImageUrl,
          scanConfidence: scanConfidence,
          leafConfidence: leafConfidence,
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // =============================
  // UI
  // =============================
  @override
  Widget build(BuildContext context) {
    final controller = _ctrl;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: controller == null || !controller.value.isInitialized
                ? Container(
                    color: Colors.black,
                    child: Center(
                      child: Text(
                        _cameraInitError ?? 'กำลังเปิดกล้อง...',
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : GestureDetector(
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    child: CameraPreview(controller),
                  ),
          ),

          // ✅ ปุ่มปิด
          Positioned(
            top: 44,
            left: 16,
            child: _roundIcon(
              icon: Icons.close,
              onTap: () => Navigator.pop(context),
            ),
          ),

          // ✅ ปุ่ม flash / gallery
          Positioned(
            top: 44,
            right: 16,
            child: Row(
              children: [
                _roundIcon(
                  icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                  onTap: _toggleFlash,
                ),
                const SizedBox(width: 12),
                _roundIcon(
                  icon: Icons.photo_library_outlined,
                  onTap: _onGalleryPressed,
                ),
              ],
            ),
          ),

          // ✅ ข้อความบนกลาง (กำลังสแกนต้นที่ X)
          Positioned(
            top: 105,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: kPrimaryGreen,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  _scanTitle(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),

          // ✅ กรอบใบไม้ (overlay)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LeafFramePainter(),
              ),
            ),
          ),

          // ✅ ข้อความแนะนำด้านล่าง
          Positioned(
            bottom: 140,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'นำ “ใบส้ม 1 ใบ” ให้อยู่ในกรอบใบไม้',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ),
          ),

          // ✅ ปุ่มถ่าย
          Positioned(
            bottom: 52,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _onCapturePressed,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: kPrimaryGreen,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ✅ บล็อกแจ้งเตือนด้านบน (แทน SnackBar)
          if (_topNotice != null)
            Positioned(
              top: 138,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    _topNotice!,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _roundIcon({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

// =============================
// Painter วาดกรอบใบไม้
// =============================
class _LeafFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.white.withOpacity(0.92);

    // วาดเป็นรูปทรงใบไม้แบบง่าย ๆ (Bezier)
    final path = Path();

    final cx = size.width / 2;
    final top = size.height * 0.22;
    final bottom = size.height * 0.72;
    final w = size.width * 0.32;

    path.moveTo(cx, top);
    path.cubicTo(
      cx + w,
      top + (bottom - top) * 0.25,
      cx + w * 0.85,
      top + (bottom - top) * 0.78,
      cx,
      bottom,
    );
    path.cubicTo(
      cx - w * 0.85,
      top + (bottom - top) * 0.78,
      cx - w,
      top + (bottom - top) * 0.25,
      cx,
      top,
    );

    canvas.drawPath(path, paint);

    // เส้นกลาง
    final midPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.55);

    canvas.drawLine(
      Offset(cx, top + 8),
      Offset(cx, bottom - 8),
      midPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
