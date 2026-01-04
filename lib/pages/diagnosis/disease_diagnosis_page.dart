import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'disease_questions_page.dart';

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
  final String treeId; // ✅ required
  final String? treeName;

  final String diseaseId; // ✅ required
  final String? diseaseNameTh;
  final String? diseaseNameEn;

  final String? compareImageUrl;
  final File? userImageFile;

  const DiseaseDiagnosisPage({
    super.key,
    required this.treeId,
    this.treeName,
    required this.diseaseId,
    this.diseaseNameTh,
    this.diseaseNameEn,
    this.compareImageUrl,
    this.userImageFile,
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

      // ลอง readone ก่อน (ถ้ามี endpoint นี้)
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

  @override
  void initState() {
    super.initState();
    name = widget.diseaseNameTh ?? widget.diseaseNameEn ?? '';
    _load();
  }

  Widget _imageBox({required Widget child}) {
    return Container(
      height: 155,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E6E6)),
      ),
      child: Center(child: child),
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

    // ✅ เปิดหน้า Questions แบบ "เต็มจอ" เพื่อซ่อนแถบเมนูด้านล่าง (Persistent Bottom Nav)
    await PersistentNavBarNavigator.pushNewScreen(
      context,
      screen: DiseaseQuestionsPage(
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
                          ? const Icon(Icons.image_outlined, size: 44, color: Colors.black38)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.network(
                                widget.compareImageUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 44, color: Colors.black38),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _imageBox(
                      child: (widget.userImageFile == null)
                          ? const Icon(Icons.image_outlined, size: 44, color: Colors.black38)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.file(widget.userImageFile!, fit: BoxFit.cover),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

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
              const SizedBox(height: 12),

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

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
