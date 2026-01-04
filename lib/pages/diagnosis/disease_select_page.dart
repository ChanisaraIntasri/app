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

String _s(dynamic v) => (v ?? '').toString().trim();
int _toInt(dynamic v, [int def = 0]) => int.tryParse(_s(v)) ?? def;

String _joinApi(String base, String path) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final p = path.startsWith('/') ? path : '/$path';
  return '$b$p';
}

class DiseaseSelectPage extends StatefulWidget {
  const DiseaseSelectPage({
    super.key,
    this.fetchFromApi = true,
    this.treeId,
    this.navigateToDiagnosis = true,
  });

  final bool fetchFromApi;

  /// ✅ treeId ของต้นส้ม (ถ้ามี) เพื่อไปหน้าวินิจฉัยได้ทันที
  final int? treeId;

  /// ✅ ถ้า true: กดเลือกรายการโรคแล้วไปหน้า DiseaseDiagnosisPage
  /// ถ้า false: จะ pop ส่งค่ากลับให้ caller (โหมดเดิม)
  final bool navigateToDiagnosis;

  /// ✅ ใช้แบบ modal เพื่อรับค่ากลับ (โหมดเดิม)
  static Future<Map<String, dynamic>?> pick(
    BuildContext context, {
    bool fetchFromApi = true,
  }) async {
    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => DiseaseSelectPage(
          fetchFromApi: fetchFromApi,
          navigateToDiagnosis: false,
        ),
      ),
    );
    return result;
  }

  @override
  State<DiseaseSelectPage> createState() => _DiseaseSelectPageState();
}

class _DiseaseSelectPageState extends State<DiseaseSelectPage> {
  bool loading = true;
  String error = '';
  String q = '';

  List<Map<String, dynamic>> items = [];

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

  String _nameThOf(Map<String, dynamic> m) {
    return _s(m['disease_name_th'] ?? m['name_th'] ?? m['disease_th']);
  }

  String _nameEnOf(Map<String, dynamic> m) {
    return _s(m['disease_name_en'] ?? m['name_en'] ?? m['disease_en'] ?? m['disease_name']);
  }

  String _titleNameOf(Map<String, dynamic> m) {
    final th = _nameThOf(m);
    if (th.isNotEmpty) return th;
    final en = _nameEnOf(m);
    if (en.isNotEmpty) return en;
    return '-';
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = '';
    });

    try {
      if (!widget.fetchFromApi) {
        setState(() {
          items = [];
          loading = false;
        });
        return;
      }

      final token = await _readToken();
      final url = Uri.parse(_joinApi(API_BASE, '/diseases/read_diseases.php'));

      final res = await http
          .get(url, headers: _headers(token))
          .timeout(const Duration(seconds: 12));

      final decoded = jsonDecode(res.body);

      if (decoded is Map && decoded['ok'] == false) {
        throw Exception(decoded['message'] ?? decoded['error'] ?? 'โหลดข้อมูลไม่สำเร็จ');
      }

      final list = _extractList(decoded);
      final mapped = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

      if (!mounted) return;
      setState(() {
        items = mapped;
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
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = items.where((m) {
      if (q.trim().isEmpty) return true;
      final id = _s(m['disease_id'] ?? m['id']);
      final nameTh = _nameThOf(m);
      final nameEn = _nameEnOf(m);
      final t = q.toLowerCase();
      return id.toLowerCase().contains(t) ||
          nameTh.toLowerCase().contains(t) ||
          nameEn.toLowerCase().contains(t);
    }).toList();

    return Scaffold(
      backgroundColor: kPageBg,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: const Text('เลือกโรค'),
        actions: [
          IconButton(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'ค้นหา (ชื่อโรค/รหัส)',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                error,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(child: Text('ไม่พบข้อมูลโรค'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final m = filtered[i];
                          final idStr = _s(m['disease_id'] ?? m['id']);
                          final diseaseId = _toInt(m['disease_id'] ?? m['id']);
                          final title = _titleNameOf(m);
                          final en = _nameEnOf(m);

                          return InkWell(
                            onTap: () {
                              // ✅ ถ้าอยากให้ไปหน้าวินิจฉัยทันที
                              if (widget.navigateToDiagnosis) {
                                int treeId = widget.treeId ?? 0;

                                // fallback: ถ้ามี args ส่งมา
                                final args = ModalRoute.of(context)?.settings.arguments;
                                if (treeId <= 0 && args is Map) {
                                  treeId = _toInt(args['treeId'] ?? args['tree_id'] ?? args['id']);
                                }

                                // ไม่มี treeId → ส่งค่ากลับแบบเดิม
                                if (treeId <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ไม่พบ treeId ของต้นส้ม — ส่งค่ากลับให้หน้าก่อนหน้า')),
                                  );
                                  Navigator.pop<Map<String, dynamic>>(context, {
                                    'disease_id': diseaseId.toString(),
                                    'disease_name': title,
                                    'raw': m,
                                  });
                                  return;
                                }

                                // ✅ สำคัญ: DiseaseDiagnosisPage รับ String
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DiseaseDiagnosisPage(
                                      treeId: treeId.toString(),
                                      diseaseId: diseaseId.toString(),
                                    ),
                                  ),
                                );
                                return;
                              }

                              // ✅ โหมดเดิม: pop ส่งค่ากลับ
                              Navigator.pop<Map<String, dynamic>>(context, {
                                'disease_id': diseaseId.toString(),
                                'disease_name': title,
                                'raw': m,
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE5E5E5)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: kPrimaryGreen.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.local_florist, color: kPrimaryGreen),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(fontWeight: FontWeight.w900),
                                        ),
                                        const SizedBox(height: 2),
                                        if (en.isNotEmpty)
                                          Text(
                                            en,
                                            style: TextStyle(color: Colors.grey[600]),
                                          ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'ID: $idStr',
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right),
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
