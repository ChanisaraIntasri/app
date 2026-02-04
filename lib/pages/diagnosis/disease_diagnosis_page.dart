import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'orchard_management_questions_page.dart';

const kPrimaryGreen = Color(0xFF005E33);
const kPageBg = Color(0xFFFFFFFF);

const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api',
);

String _joinApi(String base, String path) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final p = path.startsWith('/') ? path : '/$path';
  return '$b$p';
}

String _s(dynamic v) => (v ?? '').toString().trim();

class DiseaseDiagnosisPage extends StatefulWidget {
  final String treeId;
  final String? treeName;

  final String diseaseId;
  final String? diseaseNameTh;
  final String? diseaseNameEn;

  final String? compareImageUrl;
  final File? userImageFile;

  // ✅ percent ความมั่นใจจากการสแกน (มาจาก Model API)
  // ค่าที่รับได้ทั้ง 0..1 หรือ 0..100
  final double? scanConfidence;

  // ✅ percent ความมั่นใจว่าเป็น “ใบส้ม” (ถ้า backend ส่งมา)
  final double? leafConfidence;

  const DiseaseDiagnosisPage({
    super.key,
    required this.treeId,
    this.treeName,
    required this.diseaseId,
    this.diseaseNameTh,
    this.diseaseNameEn,
    this.compareImageUrl,
    this.userImageFile,
    this.scanConfidence,
    this.leafConfidence,
  });

  @override
  State<DiseaseDiagnosisPage> createState() => _DiseaseDiagnosisPageState();
}

class _DiseaseDiagnosisPageState extends State<DiseaseDiagnosisPage> {
  bool loading = true;
  String error = '';

  String name = '';
  String description = '';
  String cause = '';
  String symptoms = '';

  bool _openDesc = false;
  bool _openCause = false;
  bool _openSymptoms = false;

  // ✅ ป้องกันยิงซ้ำ (กัน reload/เปิดหน้าใหม่ซ้อน)
  bool _scanImageSaveAttempted = false;

  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ??
        prefs.getString('access_token') ??
        prefs.getString('auth_token');
  }

  Map<String, String> _headers(String? token) => {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final s = _s(m[k]);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final d = decoded['data'];
      if (d is List) return d;
      final items = decoded['items'];
      if (items is List) return items;
      final records = decoded['records'];
      if (records is List) return records;
    }
    return [];
  }

  Future<Map<String, dynamic>?> _fallbackReadAllAndFind(String? token) async {
    final url = Uri.parse(_joinApi(API_BASE, '/diseases/read_diseases.php'));
    final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));
    final decoded = jsonDecode(res.body);

    final list = _extractList(decoded);
    for (final it in list) {
      if (it is Map) {
        final m = Map<String, dynamic>.from(it);
        final id = _s(m['disease_id'] ?? m['id']);
        if (id == widget.diseaseId) return m;
      }
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = '';
    });

    try {
      final token = await _readToken();

      Map<String, dynamic>? data;
      try {
        final url = Uri.parse(
          _joinApi(API_BASE, '/diseases/readone_diseases.php') +
              '?disease_id=${Uri.encodeComponent(widget.diseaseId)}',
        );
        final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));
        final decoded = jsonDecode(res.body);

        if (decoded is Map) {
          final d = decoded['data'];
          if (d is Map) data = Map<String, dynamic>.from(d);
        }
      } catch (_) {}

      data ??= await _fallbackReadAllAndFind(token);
      if (data == null) throw Exception('ไม่พบข้อมูลโรค');

      final nTh = _pick(data, ['disease_th', 'disease_name_th', 'name_th', 'disease_name', 'name']);
      final nEn = _pick(data, ['disease_en', 'disease_name_en', 'name_en']);

      final desc = _pick(data, ['description', 'disease_desc', 'desc', 'detail']);
      final ca = _pick(data, ['cause', 'reason', 'causes']);
      final sym = _pick(data, ['symptoms', 'symptom', 'signs']);

      if (!mounted) return;
      setState(() {
        name = nTh.isNotEmpty ? nTh : (widget.diseaseNameTh ?? '');
        if (name.isEmpty) name = nEn.isNotEmpty ? nEn : (widget.diseaseNameEn ?? '');
        description = desc;
        cause = ca;
        symptoms = sym;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  // ✅ บันทึกรูปหลังสแกนเสร็จทันที (อัปโหลดไป diagnosis_history)
  Future<void> _saveScanImageToDiagnosisHistory() async {
    if (_scanImageSaveAttempted) return;
    _scanImageSaveAttempted = true;

    final file = widget.userImageFile;
    if (file == null) return;
    if (!file.existsSync()) return;

    // tree_id / disease_id ต้องเป็นตัวเลข (PHP validate ด้วย ctype_digit)
    if (widget.treeId.trim().isEmpty || widget.diseaseId.trim().isEmpty) return;

    try {
      final token = await _readToken();
      if (token == null || token.isEmpty) return;

      final uri = Uri.parse(_joinApi(API_BASE, '/diagnosis_history/create_diagnosis_history.php'));

      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll(_headers(token));

      req.fields['tree_id'] = widget.treeId.toString();
      req.fields['disease_id'] = widget.diseaseId.toString();

      // field ต้องชื่อ image_file ตาม create_diagnosis_history.php
      req.files.add(await http.MultipartFile.fromPath('image_file', file.path));

      final streamed = await req.send().timeout(const Duration(seconds: 20));
      final body = await streamed.stream.bytesToString();

      // ไม่กระทบ UI: แค่พยายาม decode (กันกรณี backend เผลอส่งไม่ใช่ JSON)
      try {
        jsonDecode(body);
      } catch (_) {
        // ถ้าอยาก debug:
        // print('saveScanImage invalid_json: $body');
      }
    } catch (e) {
      // ถ้าอยาก debug:
      // print('saveScanImage error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    name = widget.diseaseNameTh ?? widget.diseaseNameEn ?? '';
    _load();

    // ✅ อัปโหลดรูปหลังสแกนทันที (ไม่รอ ไม่บล็อก UI)
    Future.microtask(_saveScanImageToDiagnosisHistory);
  }

  // ✅ แก้ไข: เพิ่มความสูงเป็น 200 และตั้งค่า clipBehavior เพื่อให้รูปเต็มกรอบ
  Widget _imageBox({required Widget child}) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E6E6)),
      ),
      clipBehavior: Clip.antiAlias, // ตัดขอบรูปภาพให้โค้งตาม Container
      child: Center(child: child),
    );
  }

  double _normalizePercent(double v) {
    if (v.isNaN || v.isInfinite) return 0.0;
    var pct = (v <= 1.0) ? (v * 100.0) : v;
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    return pct.toDouble();
  }
  Widget _confidenceCard() {
    // ✅ แสดงเฉพาะความมั่นใจในการวินิจฉัยโรค (ไม่แสดงความมั่นใจว่าเป็นใบส้ม)
    final hasScan = widget.scanConfidence != null;
    if (!hasScan) return const SizedBox.shrink();

    final scanPct = _normalizePercent(widget.scanConfidence!);

    Widget row(String label, double pct) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kPrimaryGreen),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (pct / 100.0).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Colors.black12,
                valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryGreen),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 10, bottom: 8),
      decoration: BoxDecoration(
        color: kPrimaryGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPrimaryGreen.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ผลการสแกน',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kPrimaryGreen),
          ),
          const SizedBox(height: 10),
          row('ความมั่นใจในการวินิจฉัยโรค', scanPct),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String value,
    required bool open,
    required VoidCallback onToggle,
    required IconData icon,
  }) {
    final v = value.trim().isEmpty ? '-' : value.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kPrimaryGreen.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: kPrimaryGreen, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: kPrimaryGreen,
                      ),
                    ),
                  ),
                  Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.black54),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    v,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
                  ),
                ),
                crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _goQuestions() async {
    final dn = name.trim().isNotEmpty
        ? name.trim()
        : (widget.diseaseNameTh ?? widget.diseaseNameEn ?? '-');

    await PersistentNavBarNavigator.pushNewScreen(
      context,
      screen: OrchardManagementQuestionsPage(
        treeId: widget.treeId,
        treeName: widget.treeName,
        diseaseId: widget.diseaseId,
        diseaseName: dn,
      ),
      withNavBar: false,
      pageTransitionAnimation: PageTransitionAnimation.cupertino,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dn = name.trim().isNotEmpty
        ? name.trim()
        : (widget.diseaseNameTh ?? widget.diseaseNameEn ?? '-');

    return Scaffold(
      backgroundColor: kPageBg,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: const Text('วินิจฉัยโรค'),
        actions: [
          IconButton(
            onPressed: loading ? null : _load,
            icon: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh),
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _imageBox(
                      child: (widget.compareImageUrl == null || widget.compareImageUrl!.isEmpty)
                          ? const Icon(Icons.image_outlined, size: 50, color: Colors.black38)
                          : Image.network(
                              widget.compareImageUrl!,
                              fit: BoxFit.cover, // ✅ แก้ไข: ขยายรูปให้เต็มพื้นที่กรอบ
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image_outlined, size: 50, color: Colors.black38),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _imageBox(
                      child: (widget.userImageFile == null)
                          ? const Icon(Icons.image_outlined, size: 50, color: Colors.black38)
                          : Image.file(
                              widget.userImageFile!,
                              fit: BoxFit.cover, // ✅ แก้ไข: ขยายรูปให้เต็มพื้นที่กรอบ
                              width: double.infinity,
                              height: double.infinity,
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (error.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Text(error, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                ),

              Text(
                'ชื่อโรค : $dn',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),

              // ✅ แสดงเปอร์เซ็นต์ความมั่นใจจากการสแกน (ถ้ามี)
              _confidenceCard(),

              const SizedBox(height: 16),

              _sectionCard(
                title: 'คำอธิบายโรค',
                value: description,
                open: _openDesc,
                onToggle: () => setState(() => _openDesc = !_openDesc),
                icon: Icons.description_outlined,
              ),
              _sectionCard(
                title: 'สาเหตุ',
                value: cause,
                open: _openCause,
                onToggle: () => setState(() => _openCause = !_openCause),
                icon: Icons.warning_amber_rounded,
              ),
              _sectionCard(
                title: 'อาการ',
                value: symptoms,
                open: _openSymptoms,
                onToggle: () => setState(() => _openSymptoms = !_openSymptoms),
                icon: Icons.healing_outlined,
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: loading ? null : _goQuestions,
                  child: const Text(
                    'ตอบคำถาม',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
