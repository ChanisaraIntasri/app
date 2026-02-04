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
import 'confirm_capture_page.dart';

const kPrimaryGreen = Color(0xFF005E33);

// ====== ตั้งค่า API โมเดล ======
const String kModelApiBase = String.fromEnvironment(
  'MODEL_API_BASE',
  defaultValue: 'https://named-volvo-biggest-adapters.trycloudflare.com',
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
  String? _topNoticeMsg;
  Timer? _topNoticeTimer;

  // =========================
  // ✅ Tree context (กันกรณีไม่ได้ส่ง treeId มาจากหน้าก่อนหน้า)
  // =========================
  String? _resolvedTreeId;
  String? _resolvedTreeName;

  String _t(dynamic v) => (v ?? '').toString().trim();

  String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  Future<void> _saveTreeContext(String treeId, String? treeName) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ✅ เก็บหลายคีย์ เผื่อไฟล์อื่นอ่านคนละชื่อ
      await prefs.setString('selected_tree_id', treeId);
      await prefs.setString('treeId', treeId);
      await prefs.setString('tree_id', treeId);
      await prefs.setString('current_tree_id', treeId);
      await prefs.setString('last_tree_id', treeId);

      final tn = (treeName ?? '').trim();
      if (tn.isNotEmpty) {
        await prefs.setString('selected_tree_name', tn);
        await prefs.setString('treeName', tn);
        await prefs.setString('tree_name', tn);
        await prefs.setString('current_tree_name', tn);
        await prefs.setString('last_tree_name', tn);
      }
    } catch (e) {
      _cameraInitError = 'เปิดกล้องไม่สำเร็จ: ${e.toString()}';
      // แจ้งหลังเฟรมแรก (กัน context ยังไม่พร้อม)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cameraInitError != null) _toast(_cameraInitError!);
      });
    }
  }

  Future<void> _resolveTreeContext() async {
    // 1) จาก widget
    final wId = _t(widget.treeId);
    final wName = _t(widget.treeName);
    if (wId.isNotEmpty) {
      _resolvedTreeId = wId;
      _resolvedTreeName = wName.isNotEmpty ? wName : _resolvedTreeName;
      await _saveTreeContext(_resolvedTreeId!, _resolvedTreeName);
      if (mounted) setState(() {});
      return;
    }

    // 2) จาก route arguments (รองรับทั้ง Map และ String)
    String? aId;
    String? aName;
    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Map) {
      aId = _t(args['treeId'] ?? args['tree_id'] ?? args['id']);
      aName = _t(args['treeName'] ?? args['tree_name'] ?? args['name']);
      if (aId.isEmpty) aId = null;
      if (aName.isEmpty) aName = null;
    } else if (args != null) {
      final s = _t(args);
      if (s.isNotEmpty) aId = s;
    }

    // 3) จาก SharedPreferences (กรณี ScanPage ถูกเปิดจาก bottom nav ที่ไม่ได้ส่ง args)
    String? pId;
    String? pName;
    try {
      final prefs = await SharedPreferences.getInstance();

      const idKeys = [
        'selected_tree_id',
        'treeId',
        'tree_id',
        'current_tree_id',
        'active_tree_id',
        'last_tree_id',
      ];
      for (final k in idKeys) {
        final v = _t(prefs.getString(k));
        if (v.isNotEmpty) {
          pId = v;
          break;
        }
      }

      const nameKeys = [
        'selected_tree_name',
        'treeName',
        'tree_name',
        'current_tree_name',
        'active_tree_name',
        'last_tree_name',
      ];
      for (final k in nameKeys) {
        final v = _t(prefs.getString(k));
        if (v.isNotEmpty) {
          pName = v;
          break;
        }
      }
    } catch (_) {
      // ignore
    }

    final bestId = _firstNonEmpty([aId, pId]);
    final bestName = _firstNonEmpty([aName, pName]);

    if (bestId != null) {
      _resolvedTreeId = bestId;
      _resolvedTreeName = bestName;
      await _saveTreeContext(bestId, bestName);
      if (mounted) setState(() {});
    }
  }

  void _bootstrapTreeContext() {
    // ถ้ามีค่าอยู่แล้ว ให้จำไว้ทันที
    final wId = _t(widget.treeId);
    final wName = _t(widget.treeName);
    if (wId.isNotEmpty) {
      _resolvedTreeId = wId;
      _resolvedTreeName = wName.isNotEmpty ? wName : null;
      _saveTreeContext(wId, _resolvedTreeName);
    }

    // ต้องรอหลังเฟรมแรกเพื่อให้ ModalRoute.arguments พร้อม
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveTreeContext();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapTreeContext();
    _initCam();
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
    final controller = _ctrl;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCam();
    }
  }

  Future<void> _initCam() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) return;

      _camIndex = 0;
      await _startController(_cams[_camIndex]);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _startController(CameraDescription desc) async {
    final old = _ctrl;
    if (old != null) {
      await old.dispose();
    }

    final controller = CameraController(
      desc,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _ctrl = controller;
    try {
      await controller.initialize();
    } catch (e) {
      _cameraInitError = 'เปิดกล้องไม่สำเร็จ: ${e.toString()}';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cameraInitError != null) _toast(_cameraInitError!);
      });
      return;
    }

    try {
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _zoom = _minZoom;
    } catch (_) {
      _minZoom = 1.0;
      _maxZoom = 8.0;
      _zoom = 1.0;
    }

    if (mounted) setState(() {});
  }

  Future<void> _toggleFlash() async {
    final c = _ctrl;
    if (c == null) return;
    try {
      _flashOn = !_flashOn;
      await c.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cams.isEmpty) return;
    _camIndex = (_camIndex + 1) % _cams.length;
    await _startController(_cams[_camIndex]);
  }

  Future<void> _setZoom(double z) async {
    final c = _ctrl;
    if (c == null) return;
    final next = z.clamp(_minZoom, _maxZoom);
    _zoom = next;
    try {
      await c.setZoomLevel(next);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _onScaleStart(ScaleStartDetails d) {
    _baseZoom = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.scale == 1.0) return;
    final next = _baseZoom * d.scale;
    _setZoom(next);
  }

  Future<File?> _takePictureToFile() async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return null;
    try {
      final xfile = await c.takePicture();
      return File(xfile.path);
    } catch (_) {
      return null;
    }
  }

  Future<File?> _pickFromGallery() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery);
      if (x == null) return null;
      return File(x.path);
    } catch (_) {
      return null;
    }
  }


Future<File?> _pickFromCameraFallback() async {
  try {
    // ใช้ image_picker เป็น fallback เผื่อ CameraController initialize ไม่สำเร็จ
    // + ลดขนาดไฟล์ด้วย imageQuality/maxWidth เพื่อกันปัญหาไฟล์ใหญ่เกินฝั่ง API
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 88,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (x == null) return null;
    return File(x.path);
  } catch (_) {
    return null;
  }
}
  // =========================
  // ✅ FIX: กล้องไม่ยืด/ไม่เพี้ยนสัดส่วน
  // =========================
  Widget _buildCameraPreview(Size size) {
    final controller = _ctrl;
    if (controller == null) return const SizedBox.shrink();

    final value = controller.value;
    if (!value.isInitialized) return const SizedBox.shrink();

    final ps = value.previewSize;
    if (ps == null) return Center(child: CameraPreview(controller));

    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    // ✅ บนมือถือส่วนใหญ่ previewSize จะกลับแกนในโหมด Portrait
    final previewW = isPortrait ? ps.height : ps.width;
    final previewH = isPortrait ? ps.width : ps.height;

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: previewW,
          height: previewH,
          child: CameraPreview(controller),
        ),
      ),
    );
  }


Future<Map<String, dynamic>?> _callModelApi(File imgFile) async {
  if (!kUseRealModelApi) {
    return {
      "ok": true,
      "disease_name": "ใบจุดดำ",
      "confidence": 0.91,
      "disease_id": 1,
    };
  }

  final uri = Uri.parse("$kModelApiBase$kModelPredictPath");

  try {
    final req = http.MultipartRequest('POST', uri);
    req.files.add(await http.MultipartFile.fromPath('file', imgFile.path));

    final res = await req.send();
    final body = await res.stream.bytesToString();

    // ✅ ถ้า HTTP ไม่สำเร็จ ให้คืน error เป็น Map เพื่อให้ caller แสดงข้อความได้
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'Model API error (${res.statusCode})';
      try {
        final decodedErr = json.decode(body);
        if (decodedErr is Map && decodedErr['detail'] != null) {
          msg = decodedErr['detail'].toString();
        }
      } catch (_) {
        // ignore
      }
      return {"ok": false, "status_code": res.statusCode, "error": msg};
    }

    final decoded = json.decode(body);

    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  } catch (e) {
    return {"ok": false, "error": e.toString()};
  }
}

  void _toast(String msg) {
    if (!mounted) return;

    // ซ่อน SnackBar เก่า (เผื่อมีหลงมา)
    try {
      ScaffoldMessenger.of(context).clearSnackBars();
    } catch (_) {
      // ignore
    }

    setState(() => _topNoticeMsg = msg);
    _topNoticeTimer?.cancel();
    _topNoticeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _topNoticeMsg = null);
    });
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

      // ✅ ยืนยันรูป (แสดงเฉพาะส่วนในกรอบใบไม้)
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ConfirmCapturePage(imagePath: imageFile.path),
          fullscreenDialog: true,
        ),
      );

      if (ok != true) return;

      // ✅ ส่งโมเดล -> ไปหน้าวินิจฉัย
      final result = await _callModelApi(imageFile);

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

        // ✅ percent ความมั่นใจว่าเป็น “ใบส้ม” (ถ้า backend ส่งมา)
        final lc = result['leaf_confidence'];
        if (lc is num) {
          leafConfidence = lc.toDouble();
        } else if (lc != null) {
          leafConfidence = double.tryParse(lc.toString());
        }
      }

      // ✅ ถ้าโมเดลไม่ส่ง disease_id มา ใช้ map ชื่อโรค -> id
      if (diseaseId == null || diseaseId.trim().isEmpty) {
        final meta = kDiseaseNameMap[diseaseName];
        if (meta != null) diseaseId = meta.id;
      }

      if (diseaseId == null || diseaseId.trim().isEmpty) {
        _toast('โมเดลไม่ส่ง disease_id และหา id จากชื่อโรคไม่ได้');
        return;
      }

      // ✅ ส่งชื่อโรคไปเป็น diseaseNameTh (ไม่ทำให้ constructor พัง)
      await _goToDiagnosisPage(
        imageFile: imageFile,
        diseaseId: diseaseId,
        diseaseNameTh: diseaseName,
        compareImageUrl: compareImageUrl,
        scanConfidence: scanConfidence,
        leafConfidence: leafConfidence,
      );
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

      final result = await _callModelApi(file);

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

        // ✅ percent ความมั่นใจว่าเป็น “ใบส้ม” (ถ้า backend ส่งมา)
        final lc = result['leaf_confidence'];
        if (lc is num) {
          leafConfidence = lc.toDouble();
        } else if (lc != null) {
          leafConfidence = double.tryParse(lc.toString());
        }
      }

      if (diseaseId == null || diseaseId.trim().isEmpty) {
        final meta = kDiseaseNameMap[diseaseName];
        if (meta != null) diseaseId = meta.id;
      }

      if (diseaseId == null || diseaseId.trim().isEmpty) {
        _toast('โมเดลไม่ส่ง disease_id และหา id จากชื่อโรคไม่ได้');
        return;
      }

      await _goToDiagnosisPage(
        imageFile: file,
        diseaseId: diseaseId,
        diseaseNameTh: diseaseName,
        compareImageUrl: compareImageUrl,
        scanConfidence: scanConfidence,
        leafConfidence: leafConfidence,
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ====== overlay ใบไม้ ======
  Path _leafPathFromRect(Rect r) {
    final cx = r.center.dx;
    final top = r.top;
    final bottom = r.bottom;
    final w = r.width;
    final h = r.height;

    final p = Path();

    p.moveTo(cx, top);
    p.cubicTo(
      cx - w * 0.55,
      top + h * 0.10,
      cx - w * 0.55,
      top + h * 0.65,
      cx,
      bottom,
    );
    p.cubicTo(
      cx + w * 0.55,
      top + h * 0.65,
      cx + w * 0.55,
      top + h * 0.10,
      cx,
      top,
    );
    p.close();
    return p;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final mq = MediaQuery.of(context);

    // ✅ คำนวณพื้นที่ที่ SafeArea ใช้งานจริง (พิกัดใน SafeArea เริ่มที่ 0..safeH)
    final safeH = size.height - mq.padding.top - mq.padding.bottom;

    // ✅ กันพื้นที่ด้านบน/ล่างสำหรับปุ่มและข้อความ (ไม่เปลี่ยน UI เดิม)
    const reservedTop = 70.0;   // แถบปุ่มปิด + ไอคอนด้านบน
    const reservedBottom = 210.0; // ข้อความ + ปุ่มถ่าย + ระยะหายใจ

    final availableH = (safeH - reservedTop - reservedBottom).clamp(220.0, safeH);

    // สัดส่วนเดิมของกรอบใบไม้ (0.70 : 0.95)
    const leafRatio = 0.70 / 0.95;

    // สูงสุดอิงความกว้างหน้าจอเหมือนเดิม แต่ไม่ให้ล้ำพื้นที่ด้านล่าง
    // ✅ ลดขนาดกรอบใบไม้ลง (ใบส้มโดยทั่วไปไม่ใหญ่มาก)
    final targetLeafH = size.width * 0.78;
    final leafH = targetLeafH.clamp(220.0, availableH);

    // กว้างตามสัดส่วน และ clamp ไม่ให้กว้าง/แคบเกินไป
    final leafW = (leafH * leafRatio).clamp(size.width * 0.55, size.width * 0.78);

    final left = (size.width - leafW) / 2;
    final top = reservedTop + (availableH - leafH) / 2;

    final leafRect = Rect.fromLTWH(left, top, leafW, leafH);
    final leafPath = _leafPathFromRect(leafRect);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildCameraPreview(size)),


// ✅ หากกล้องยังไม่พร้อม ให้แสดงตัวโหลด (ยังสามารถกดแกลลอรี่/ปุ่มถ่ายแบบ fallback ได้)
if (_ctrl == null || _ctrl?.value.isInitialized != true)
  Positioned.fill(
    child: IgnorePointer(
      child: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    ),
  ),

            // mask รอบนอกใบไม้
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _LeafMaskPainter(leafPath)),
              ),
            ),

            // ขอบใบไม้ + เส้นกลาง
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _LeafStrokePainter(leafPath)),
              ),
            ),

            // ✅ ขยับข้อความขึ้นด้านบนเล็กน้อย (ไม่ให้ชิดปุ่มถ่ายภาพ)
            Positioned(
              bottom: 150,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'นำ “ใบส้ม 1 ใบ” ให้อยู่ในกรอบใบไม้',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

            // X
            Positioned(
              top: 12,
              left: 12,
              child: _RoundIconButton(
                icon: Icons.close,
                onTap: () => Navigator.pop(context),
              ),
            ),

            // flash + gallery
            Positioned(
              top: 12,
              right: 12,
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                    onTap: _toggleFlash,
                  ),
                  const SizedBox(width: 10),
                  _RoundIconButton(
                    icon: Icons.image_outlined,
                    onTap: _onGalleryPressed,
                  ),
                ],
              ),
            ),

            // ✅ แจ้งเตือนแบบบล็อกด้านบน-กลางหน้าจอ (พื้นหลังสีขาว)
            if (_topNoticeMsg != null)
              Positioned(
                top: 70,
                left: 0,
                right: 0,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _topNoticeMsg = null),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 14,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Text(
                            _topNoticeMsg!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            if (_cams.length > 1)
              Positioned(
                right: 14,
                bottom: 170,
                child: _RoundIconButton(
                  icon: Icons.cameraswitch,
                  onTap: _switchCamera,
                ),
              ),

            Positioned(
              left: 14,
              bottom: 142,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_zoom.toStringAsFixed(1)}x',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),

            // ปุ่มถ่าย
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Center(
                child: GestureDetector(
                  onTap: _onCapturePressed,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Center(
                      child: Container(
                        width: 64,
                        height: 64,
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

            if (_isBusy)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LeafMaskPainter extends CustomPainter {
  final Path leafPath;
  _LeafMaskPainter(this.leafPath);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final mask = Path.combine(PathOperation.difference, full, leafPath);

    final paint = Paint()
      ..color = Colors.black.withOpacity(0.55)
      ..style = PaintingStyle.fill;

    canvas.drawPath(mask, paint);
  }

  @override
  bool shouldRepaint(covariant _LeafMaskPainter oldDelegate) {
    return oldDelegate.leafPath != leafPath;
  }
}

class _LeafStrokePainter extends CustomPainter {
  final Path leafPath;
  _LeafStrokePainter(this.leafPath);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawPath(leafPath, stroke);
  }

  @override
  bool shouldRepaint(covariant _LeafStrokePainter oldDelegate) {
    return oldDelegate.leafPath != leafPath;
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Center(
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}