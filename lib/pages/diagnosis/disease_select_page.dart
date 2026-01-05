import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/pages/diagnosis/disease_diagnosis_page.dart';

const kPrimaryGreen = Color(0xFF005E33);
const kPageBg = Color(0xFFFFFFFF);

const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue:
      'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api',
);

String _joinUrl(String a, String b) {
  if (a.endsWith('/')) a = a.substring(0, a.length - 1);
  if (b.startsWith('/')) b = b.substring(1);
  return '$a/$b';
}

String _s(dynamic v) => (v ?? '').toString().trim();

int _toInt(dynamic v, [int def = 0]) => int.tryParse(_s(v)) ?? def;

class DiseaseSelectPage extends StatefulWidget {
  const DiseaseSelectPage({
    super.key,
    this.fetchFromApi = true,
    this.treeId,
    this.navigateToDiagnosis = true,
  });

  final bool fetchFromApi;

  /// treeId ของต้นส้ม (ถ้ามี) เพื่อไปหน้าวินิจฉัย
  final int? treeId;

  /// ถ้า true: กดโรคแล้วไปหน้า DiseaseDiagnosisPage
  final bool navigateToDiagnosis;

  @override
  State<DiseaseSelectPage> createState() => _DiseaseSelectPageState();
}

class _DiseaseSelectPageState extends State<DiseaseSelectPage> {
  bool loading = false;
  String error = '';
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ??
        prefs.getString('access_token') ??
        prefs.getString('auth_token');
  }

  Map<String, String> _headers(String? token) {
    final h = <String, String>{'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  List _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) return data;
      final rows = decoded['rows'];
      if (rows is List) return rows;
      final items = decoded['items'];
      if (items is List) return items;
    }
    return [];
  }

  // ✅ FIX: รองรับชื่อไทย/อังกฤษหลายรูปแบบ ตามที่ API มักส่งมา
  String _nameThOf(Map<String, dynamic> m) {
    return _s(
      m['disease_name_th'] ??
          m['name_th'] ??
          m['disease_th'] ?? // <<< สำคัญ (ของคุณมีโอกาสใช้ชื่อนี้)
          m['thai_name'] ??
          m['disease_name'] ?? // บางระบบใช้ disease_name เป็นไทย
          m['name'] ??
          m['title_th'],
    );
  }

  String _nameEnOf(Map<String, dynamic> m) {
    return _s(
      m['disease_name_en'] ??
          m['name_en'] ??
          m['disease_en'] ?? // <<< สำคัญ
          m['english_name'] ??
          m['disease_code'] ?? // <<< สำคัญ (เช่น canker, melanose)
          m['code'] ??
          m['slug'] ??
          m['disease_name'], // บางระบบใช้ disease_name เป็นอังกฤษ
    );
  }

  String _titleNameOf(Map<String, dynamic> m) {
    final th = _nameThOf(m);
    if (th.isNotEmpty) return th;
    final en = _nameEnOf(m);
    if (en.isNotEmpty) return en;
    return 'ไม่ทราบชื่อโรค';
  }

  Future<void> _load() async {
    if (!widget.fetchFromApi) return;

    setState(() {
      loading = true;
      error = '';
    });

    try {
      final token = await _getToken();
      final url = Uri.parse(_joinUrl(API_BASE, 'diseases/read_diseases.php'));

      final res = await http
          .get(url, headers: _headers(token))
          .timeout(const Duration(seconds: 12));

      final decoded = jsonDecode(res.body);

      if (decoded is Map && decoded['ok'] == false) {
        throw Exception(decoded['message'] ?? decoded['error'] ?? 'โหลดข้อมูลไม่สำเร็จ');
      }

      final list = _extractList(decoded);
      final mapped = list
          .where((e) => e is Map)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() => items = mapped);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPageBg,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: const Text('เลือกโรค'),
        // ✅ ไม่มีปุ่มรีโหลดแล้ว
      ),
      body: Column(
        children: [
          // ✅ ไม่มีช่องค้นหาแล้ว

          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                error,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const Center(child: Text('ไม่พบข้อมูลโรค'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final m = items[i];

                          final diseaseId = _toInt(m['disease_id'] ?? m['id']);
                          final idStr = _s(m['disease_id'] ?? m['id']);
                          final title = _titleNameOf(m);
                          final en = _nameEnOf(m);

                          // กัน subtitle ซ้ำกับ title
                          final subtitle =
                              (en.isNotEmpty && en != title) ? en : '';

                          return InkWell(
                            onTap: () {
                              if (widget.navigateToDiagnosis) {
                                final treeId = widget.treeId ?? 0;

                                if (treeId <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ไม่พบ treeId ของต้นส้ม')),
                                  );
                                  return;
                                }

                                // ✅ ไม่ส่ง diseaseName แล้ว
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DiseaseDiagnosisPage(
                                      treeId: treeId.toString(),
                                      diseaseId: diseaseId.toString(),
                                    ),
                                  ),
                                );
                              } else {
                                Navigator.pop(context, {
                                  'disease_id': diseaseId,
                                  'disease_name': title,
                                });
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFE6E6E6)),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x14000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF3EE),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(Icons.local_florist, color: kPrimaryGreen),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        if (subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            subtitle,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.black54,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Text(
                                          'ID: $idStr',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black38,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, size: 26, color: Colors.black54),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
