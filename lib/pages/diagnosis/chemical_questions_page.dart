import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'disease_questions_page.dart';

const Duration kHttpTimeout = Duration(seconds: 15);

class ChemicalQuestionsPage extends StatefulWidget {
  final String treeId;
  final String? treeName;
  final String diseaseId;
  final String diseaseName;

  const ChemicalQuestionsPage({
    super.key,
    required this.treeId,
    this.treeName,
    required this.diseaseId,
    required this.diseaseName,
  });

  @override
  State<ChemicalQuestionsPage> createState() => _ChemicalQuestionsPageState();
}

class _ChemicalQuestionsPageState extends State<ChemicalQuestionsPage> {
  static const Color _kPrimaryGreen = Color(0xFF005E33);
  static const double _kRadius = 14;

  static const String _kDefaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api',
  );

  String? apiBase;
  String? token;

  String? sprayed; // "yes" | "no"
  int? selectedChemicalId;
  String? selectedChemicalName;

  List<Map<String, dynamic>> chemicals = [];

  final int qidSprayed = 67;
  final int qidChemical = 68;

  @override
  void initState() {
    super.initState();
    initApi();
  }

  Future<void> initApi() async {
    final prefs = await SharedPreferences.getInstance();
    apiBase = prefs.getString('api_base_url') ?? _kDefaultApiBaseUrl;
    token = prefs.getString('token') ?? prefs.getString('access_token');

    await fetchChemicals();
  }

  Map<String, String> _headers(String? token, {bool json = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json; charset=utf-8';
    if (token != null && token.trim().isNotEmpty) {
      h['Authorization'] = 'Bearer ${token.trim()}';
    }
    return h;
  }

  bool? get _sprayed => sprayed == null
      ? null
      : (sprayed == 'yes' ? true : (sprayed == 'no' ? false : null));

  int? get _selectedChemicalId => selectedChemicalId;

  Future<String?> _getToken() async {
    if (token != null && token!.trim().isNotEmpty) return token;
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token') ??
        prefs.getString('access_token') ??
        prefs.getString('auth_token');
    return token;
  }

  Uri _uri(String path) {
    final base = (apiBase ?? _kDefaultApiBaseUrl).replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$base/$p');
  }

  Map<String, String> _headersJson(String? token) => _headers(token, json: true);

  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) return data;
      final records = decoded['records'];
      if (records is List) return records;
    }
    return const [];
  }

  // ✅ ลบ whitespace / zero-width ออกเพื่อกรอง "อื่น ๆ" ให้ติดแน่นอน
  String _normalizeName(String s) {
    return s
        .replaceAll(RegExp(r'[\s\u00A0\u200B\u200C\u200D\uFEFF]+'), '')
        .trim();
  }

  bool _isOtherChoiceName(String name) {
    final n = _normalizeName(name);
    // รองรับ: "อื่น ๆ", "อื่นๆ", "อื่น", และแบบมีอักขระแทรก
    return n == 'อื่น' || n == 'อื่นๆ' || n.startsWith('อื่น');
  }

  Future<void> fetchChemicals() async {
    try {
      final base = apiBase ?? _kDefaultApiBaseUrl;
      final tok = token;

      http.Response res;

      final publicUri = Uri.parse("$base/chemicals/read_chemicals_public.php");
      final privateUri = Uri.parse("$base/chemicals/read_chemicals.php");

      try {
        res = await http.get(publicUri, headers: _headers(tok)).timeout(kHttpTimeout);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          res = await http.get(privateUri, headers: _headers(tok)).timeout(kHttpTimeout);
        }
      } catch (_) {
        res = await http.get(privateUri, headers: _headers(tok)).timeout(kHttpTimeout);
      }

      final decoded = jsonDecode(res.body);
      final list = _extractList(decoded);

      final loaded = list.map((e) {
        final m = (e as Map).map((k, v) => MapEntry(k.toString(), v));
        return {
          'chemical_id': m['chemical_id'],
          'chemical_name': m['chemical_name'] ??
              m['trade_name'] ??
              m['tradeName'] ??
              m['name'] ??
              m['chemical'] ??
              m['chemicalName'] ??
              '',
        };
      }).toList();

      // ✅ กรอง "อื่น ๆ" ออกตั้งแต่ตรงนี้
      loaded.removeWhere((c) {
        final v = c['chemical_id'];
        final id = (v is int) ? v : int.tryParse(v?.toString() ?? '');
        final name = (c['chemical_name'] ?? '').toString();

        if (id == -1) return true;
        if (_isOtherChoiceName(name)) return true;

        return false;
      });

      chemicals = loaded;
      if (mounted) setState(() {});
    } catch (_) {
      chemicals = [];
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveChemicalAnswersToApi() async {
    if (_sprayed != true) return;

    final cid = _selectedChemicalId;
    if (cid == null || cid <= 0) return;

    final tok = await _getToken();
    final url = _uri('user_used_chemicals/create_user_used_chemicals.php');
    final payload = {'chemical_id': cid, 'source': 'spray_this_time'};

    final resp = await http.post(
      url,
      headers: _headersJson(tok),
      body: jsonEncode(payload),
    );

    if (resp.statusCode >= 400) {
      throw Exception('save user_used_chemicals failed: ${resp.statusCode} ${resp.body}');
    }
  }

  void nextPage() async {
    if (sprayed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("กรุณาเลือกคำตอบว่าพ่นสารหรือไม่")),
      );
      return;
    }

    if (sprayed == "yes" && selectedChemicalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("กรุณาเลือกสารเคมี")),
      );
      return;
    }

    try {
      await _saveChemicalAnswersToApi();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("บันทึกคำตอบสารเคมีล้มเหลว: $e")),
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('last_sprayed', sprayed ?? '');
      prefs.setString('last_sprayed_at', DateTime.now().toIso8601String());

      if (sprayed == "yes") {
        if (selectedChemicalId != null) {
          prefs.setInt('last_chemical_id', selectedChemicalId!);
        } else {
          prefs.remove('last_chemical_id');
        }
        prefs.setString('last_chemical_name', (selectedChemicalName ?? '').trim());
      } else {
        prefs.remove('last_chemical_id');
        prefs.setString('last_chemical_name', '');
      }
    } catch (_) {}

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiseaseQuestionsPage(
          treeId: widget.treeId,
          diseaseId: widget.diseaseId,
          diseaseName: widget.diseaseName,
          treeName: widget.treeName,
        ),
      ),
    );
  }

  Widget _answerBlock({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_kRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? _kPrimaryGreen.withOpacity(0.10) : Colors.white,
            borderRadius: BorderRadius.circular(_kRadius),
            border: Border.all(color: _kPrimaryGreen, width: 1.6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected) const Icon(Icons.check, size: 18, color: _kPrimaryGreen),
              if (selected) const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("คำถามสารเคมี"),
        backgroundColor: _kPrimaryGreen,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final double alignY = viewport.maxHeight >= 700 ? -0.22 : -0.15;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight),
                child: Align(
                  alignment: Alignment(0, alignY),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "ครั้งนี้มีการพ่นสารเคมีหรือไม่?",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _answerBlock(
                            label: "มี",
                            selected: sprayed == "yes",
                            onTap: () => setState(() => sprayed = "yes"),
                          ),
                          const SizedBox(width: 12),
                          _answerBlock(
                            label: "ไม่มี",
                            selected: sprayed == "no",
                            onTap: () {
                              setState(() {
                                sprayed = "no";
                                selectedChemicalId = null;
                                selectedChemicalName = null;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      if (sprayed == "yes") ...[
                        const Text(
                          "สารเคมีที่ใช้ในการพ่นครั้งนี้คืออะไร?",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),

                        Theme(
                          data: Theme.of(context).copyWith(
                            canvasColor: Colors.white,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                          ),
                          child: DropdownButtonFormField<int>(
                            value: selectedChemicalId,
                            dropdownColor: Colors.white,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: "เลือกสารเคมี",
                              filled: true,
                              fillColor: Colors.white,
                            ),

                            // ✅ กัน "อื่น ๆ" ซ้ำอีกชั้นตอนทำ items
                            items: chemicals
                                .where((c) => !_isOtherChoiceName((c['chemical_name'] ?? '').toString()))
                                .map((c) {
                              final id = (c['chemical_id'] is int)
                                  ? c['chemical_id'] as int
                                  : int.tryParse(c['chemical_id'].toString()) ?? -1;
                              final name = c['chemical_name'].toString();
                              return DropdownMenuItem<int>(
                                value: id,
                                child: Text(name),
                              );
                            }).toList(),

                            onChanged: (val) {
                              setState(() {
                                selectedChemicalId = val;
                                final found = chemicals.firstWhere(
                                  (e) =>
                                      (e['chemical_id'] is int
                                              ? e['chemical_id']
                                              : int.tryParse(e['chemical_id'].toString())) ==
                                          val,
                                  orElse: () => {'chemical_name': ''},
                                );
                                selectedChemicalName = found['chemical_name'].toString();
                              });
                            },
                          ),
                        ),

                        const SizedBox(height: 22),
                      ],

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: nextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: const Text("ถัดไป"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
