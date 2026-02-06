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

// แปลง path รูปจาก DB ให้เป็น URL ที่เปิดได้จริง (รองรับทั้ง full URL และ path แบบ relative)
String _resolvePublicUrl(String raw) {
  final p = raw.toString().trim();
  if (p.isEmpty) return '';
  if (p.startsWith('http://') || p.startsWith('https://')) return p;

  try {
    final apiUri = Uri.parse(API_BASE);
    final origin = '${apiUri.scheme}://${apiUri.authority}';

    // ถ้าเป็น path แบบ /crud/uploads/... ให้ต่อกับ origin ได้เลย
    if (p.startsWith('/')) return origin + p;

    // ถ้าเป็น crud/uploads/... ให้ต่อกับ origin เช่นกัน
    if (p.startsWith('crud/')) return '$origin/$p';

    // โดยทั่วไปจะเป็น uploads/... => ให้ต่อกับ base public (/crud)
    final publicBase = API_BASE.replaceAll(RegExp(r'/api/?$'), '');
    return _joinApi(publicBase, '/$p');
  } catch (_) {
    return p;
  }
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

  final double? scanConfidence;
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

  // รูปตัวอย่างของโรค (ดึงจาก DB) ใช้เป็นค่า fallback ถ้าไม่ได้ส่ง compareImageUrl มา
  String _diseaseImageUrl = '';

  bool _openDesc = false;
  bool _openCause = false;
  bool _openSymptoms = false;

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

      // ถ้า readone ไม่ได้ส่งรูปมา แต่ read_diseases มีรูป (เช่น join ตาราง disease_images)
      // ให้ดึงจาก read_diseases มาเติมเพิ่ม เพื่อให้หน้าวินิจฉัยมีรูปตัวอย่างของโรคเสมอ
      final imgFromReadOne = _pick(data, [
        'image_url',
        'disease_image_url',
        'example_image_url',
        'example_image',
        'example_image_path',
        'img_url',
        'image',
      ]);
      if (imgFromReadOne.isEmpty) {
        final more = await _fallbackReadAllAndFind(token);
        if (more != null) {
          data = {...data, ...more};
        }
      }

      final nTh = _pick(data, ['disease_th', 'disease_name_th', 'name_th', 'disease_name', 'name']);
      final nEn = _pick(data, ['disease_en', 'disease_name_en', 'name_en']);

      final desc = _pick(data, ['description', 'disease_desc', 'desc', 'detail']);
      final ca = _pick(data, ['cause', 'reason', 'causes']);
      final sym = _pick(data, ['symptoms', 'symptom', 'signs']);

      // รองรับหลายชื่อคอลัมน์ที่อาจใช้เก็บรูป
      final imgRaw = _pick(data, [
        'image_url',
        'disease_image_url',
        'example_image_url',
        'example_image',
        'example_image_path',
        'img_url',
        'image',
      ]);
      final imgUrl = _resolvePublicUrl(imgRaw);

      if (!mounted) return;
      setState(() {
        name = nTh.isNotEmpty ? nTh : (widget.diseaseNameTh ?? '');
        if (name.isEmpty) name = nEn.isNotEmpty ? nEn : (widget.diseaseNameEn ?? '');
        description = desc;
        cause = ca;
        symptoms = sym;
        if (imgUrl.isNotEmpty) _diseaseImageUrl = imgUrl;
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

  Future<void> _saveScanImageToDiagnosisHistory() async {
    if (_scanImageSaveAttempted) return;
    _scanImageSaveAttempted = true;

    final file = widget.userImageFile;
    if (file == null) return;
    if (!file.existsSync()) return;

    if (widget.treeId.trim().isEmpty || widget.diseaseId.trim().isEmpty) return;

    try {
      final token = await _readToken();
      if (token == null || token.isEmpty) return;

      final uri = Uri.parse(_joinApi(API_BASE, '/diagnosis_history/create_diagnosis_history.php'));
      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll(_headers(token));
      req.fields['tree_id'] = widget.treeId.toString();
      req.fields['disease_id'] = widget.diseaseId.toString();
      req.files.add(await http.MultipartFile.fromPath('image_file', file.path));

      await req.send().timeout(const Duration(seconds: 20));
    } catch (e) {}
  }

  @override
  void initState() {
    super.initState();
    name = widget.diseaseNameTh ?? widget.diseaseNameEn ?? '';
    _load();
    Future.microtask(_saveScanImageToDiagnosisHistory);
  }

  Widget _imageBox({required Widget child}) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E6E6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(child: child),
    );
  }

  double _normalizePercent(double v) {
    if (v.isNaN || v.isInfinite) return 0.0;
    var pct = (v <= 1.0) ? (v * 100.0) : v;
    return pct.clamp(0, 100).toDouble();
  }

  Widget _confidenceCard() {
    final hasScan = widget.scanConfidence != null;
    if (!hasScan) return const SizedBox.shrink();

    final scanPct = _normalizePercent(widget.scanConfidence!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      margin: const EdgeInsets.only(top: 12, bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB9D6C3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ผลการสแกน',
            style: TextStyle(
              color: kPrimaryGreen,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'ความมั่นใจในการวินิจฉัยโรค',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${scanPct.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: kPrimaryGreen,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (scanPct / 100.0).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryGreen),
            ),
          ),
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
    final v = value.trim().isEmpty ? 'ยังไม่มีข้อมูล$title' : value.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E6E6)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          onExpansionChanged: (val) => onToggle(),
          initiallyExpanded: open,
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3EE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kPrimaryGreen, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: kPrimaryGreen,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          iconColor: Colors.black54,
          collapsedIconColor: Colors.black54,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                v,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
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

    final leftUrl = (widget.compareImageUrl != null && widget.compareImageUrl!.trim().isNotEmpty)
        ? widget.compareImageUrl!.trim()
        : _diseaseImageUrl.trim();

    return Scaffold(
      backgroundColor: kPageBg,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'วินิจฉัยโรค',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          )
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _imageBox(
                            child: (leftUrl.isEmpty)
                                ? const Icon(Icons.image_outlined, size: 50, color: Colors.black26)
                                : Image.network(
                                    leftUrl,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image_outlined, size: 50, color: Colors.black26),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _imageBox(
                            child: (widget.userImageFile == null)
                                ? const Icon(Icons.image_outlined, size: 50, color: Colors.black26)
                                : Image.file(
                                    widget.userImageFile!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

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
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),

                    _confidenceCard(),

                    _sectionCard(
                      title: 'คำอธิบายโรค',
                      value: description,
                      open: _openDesc,
                      onToggle: () => setState(() => _openDesc = !_openDesc),
                      icon: Icons.description_rounded,
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
                      icon: Icons.healing_rounded,
                    ),

                    const SizedBox(height: 18),

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
                          'ตอบคำถามเพื่อรับคำเเนะนำ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
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
