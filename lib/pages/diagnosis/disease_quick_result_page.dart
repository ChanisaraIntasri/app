import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const kPrimaryGreen = Color(0xFF005E33);

// ✅ ใช้รูปแบบเดียวกับ disease_diagnosis_page.dart
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

class DiseaseQuickResultPage extends StatefulWidget {
  final String diseaseId;
  final String diseaseNameTh;
  final String? diseaseNameEn;
  final String? compareImageUrl;
  final File userImageFile;

  /// 0..1 หรือ 0..100
  final double? scanConfidence;

  const DiseaseQuickResultPage({
    super.key,
    required this.diseaseId,
    required this.diseaseNameTh,
    this.diseaseNameEn,
    this.compareImageUrl,
    required this.userImageFile,
    this.scanConfidence,
  });

  @override
  State<DiseaseQuickResultPage> createState() => _DiseaseQuickResultPageState();
}

class _DiseaseQuickResultPageState extends State<DiseaseQuickResultPage> {
  bool loading = true;
  String error = '';

  String name = '';
  String description = '';
  String cause = '';
  String symptoms = '';
  String? compareImageUrl;

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

  Future<Map<String, dynamic>?> _fallbackReadAllAndFind(String? token) async {
    try {
      final url = Uri.parse(_joinApi(API_BASE, '/diseases/read_diseases.php'));
      final res =
          await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(res.body);

      dynamic list;
      if (decoded is Map) list = decoded['data'];
      if (list is List) {
        for (final it in list) {
          if (it is Map) {
            final m = Map<String, dynamic>.from(it);
            final id = _pick(m, ['disease_id', 'id']);
            if (id == widget.diseaseId) return m;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  double _toPct(double? v) {
    if (v == null) return 0;
    if (v > 1.0) return v.clamp(0, 100).toDouble();
    return (v * 100).clamp(0, 100).toDouble();
  }

  @override
  void initState() {
    super.initState();
    compareImageUrl = widget.compareImageUrl;
    _loadDiseaseInfo();
  }

  Future<void> _loadDiseaseInfo() async {
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
        final res =
            await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));
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

      final img = _pick(data, [
        'example_image_url',
        'example_image',
        'image_url',
        'disease_image_url',
        'disease_image',
        'image',
      ]);

      if (!mounted) return;
      setState(() {
        name = nTh.isNotEmpty ? nTh : widget.diseaseNameTh;
        if (name.isEmpty) name = nEn.isNotEmpty ? nEn : (widget.diseaseNameEn ?? '');
        description = desc;
        cause = ca;
        symptoms = sym;

        if ((compareImageUrl == null || compareImageUrl!.trim().isEmpty) && img.isNotEmpty) {
          compareImageUrl = img;
        }

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
  Widget build(BuildContext context) {
    final pct = _toPct(widget.scanConfidence);

    return Scaffold(
      backgroundColor: Colors.white,
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
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadDiseaseInfo,
          ),
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : (error.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // =====================
                        // ภาพเทียบ + ภาพผู้ใช้
                        // =====================
                        Row(
                          children: [
                            Expanded(
                              child: _ImageCard(
                                child: (compareImageUrl == null || compareImageUrl!.trim().isEmpty)
                                    ? const _EmptyImage()
                                    : Image.network(
                                        compareImageUrl!,
                                        fit: BoxFit.cover, // ✅ ขยายเต็มกรอบ
                                        width: double.infinity,
                                        height: double.infinity,
                                        errorBuilder: (_, __, ___) => const _EmptyImage(),
                                        loadingBuilder: (context, child, progress) {
                                          if (progress == null) return child;
                                          return const Center(child: CircularProgressIndicator());
                                        },
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ImageCard(
                                child: Image.file(
                                  widget.userImageFile,
                                  fit: BoxFit.cover, // ✅ ขยายเต็มกรอบ
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (_, __, ___) => const _EmptyImage(),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ชื่อโรค
                        Text(
                          'ชื่อโรค : ${name.isNotEmpty ? name : widget.diseaseNameTh}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),

                        const SizedBox(height: 12),

                        // =====================
                        // ผลการสแกน + progress
                        // =====================
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                                    '${pct.toStringAsFixed(0)}%',
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
                                  value: (pct / 100.0).clamp(0, 1),
                                  minHeight: 10,
                                  backgroundColor: Colors.white,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(kPrimaryGreen),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // =====================
                        // Expansion sections
                        // =====================
                        _ExpandCard(
                          icon: Icons.description_rounded,
                          title: 'คำอธิบายโรค',
                          content: description.trim().isEmpty
                              ? 'ยังไม่มีข้อมูลคำอธิบายโรค'
                              : description.trim(),
                        ),
                        const SizedBox(height: 10),
                        _ExpandCard(
                          icon: Icons.warning_amber_rounded,
                          title: 'สาเหตุ',
                          content: cause.trim().isEmpty ? 'ยังไม่มีข้อมูลสาเหตุ' : cause.trim(),
                        ),
                        const SizedBox(height: 10),
                        _ExpandCard(
                          icon: Icons.healing_rounded,
                          title: 'อาการ',
                          content:
                              symptoms.trim().isEmpty ? 'ยังไม่มีข้อมูลอาการ' : symptoms.trim(),
                        ),

                        const SizedBox(height: 18),

                        // =====================
                        // ปุ่มล่าง: กลับไปหน้า Scan
                        // =====================
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryGreen,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text(
                              'กลับไปที่หน้า สแกน',
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
                  )),
      ),
    );
  }
}

// ✅ ปรับ ImageCard ให้สูง 200 และตัดขอบให้รูปขยายเต็มพื้นที่
class _ImageCard extends StatelessWidget {
  final Widget child;
  const _ImageCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200, // ปรับจาก 160 เป็น 200 ตามหน้า Diagnosis
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E6E6)),
      ),
      clipBehavior: Clip.antiAlias, // ตัดขอบรูปภาพให้โค้งตาม Container
      child: Center(child: child),
    );
  }
}

class _EmptyImage extends StatelessWidget {
  const _EmptyImage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.image_outlined, size: 50, color: Colors.black26),
    );
  }
}

class _ExpandCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;

  const _ExpandCard({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            style: const TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w800),
          ),
          iconColor: Colors.black54,
          collapsedIconColor: Colors.black54,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                content,
                style: const TextStyle(fontSize: 14, height: 1.45, color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}