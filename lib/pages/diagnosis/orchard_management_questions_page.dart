import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'chemical_questions_page.dart';

/// (คำถามจัดการสวน) — ถามครั้งเดียวต่อ user
const String kOrchardDiseaseId = '7';

const Color kPrimaryGreen = Color(0xFF005E33);
const Duration kHttpTimeout = Duration(seconds: 15);

const String kDefaultApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue:
      'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api',
);

class _Choice {
  final String id; // choice_id
  final String label; // choice_label (เอาไปโชว์เป็นตัวเลือก)
  final String advice; // choice_text
  final int scoreValue;

  const _Choice({
    required this.id,
    required this.label,
    required this.advice,
    required this.scoreValue,
  });
}

class _Question {
  final String id; // question_id
  final String text; // question_text
  final int sortOrder;
  final bool isActive;
  final List<_Choice> choices;

  const _Question({
    required this.id,
    required this.text,
    required this.sortOrder,
    required this.isActive,
    required this.choices,
  });
}

class OrchardManagementQuestionsPage extends StatefulWidget {
  final String treeId;
  final String? treeName;

  /// diseaseId/diseaseName คือ “โรคที่ตรวจพบ” (เอาไว้ส่งต่อไปหน้าถัดไป)
  final String diseaseId;
  final String diseaseName;

  final bool editMode;

  const OrchardManagementQuestionsPage({
    super.key,
    required this.treeId,
    this.treeName,
    required this.diseaseId,
    required this.diseaseName,
    this.editMode = false,
  });

  @override
  State<OrchardManagementQuestionsPage> createState() =>
      _OrchardManagementQuestionsPageState();
}

class _OrchardManagementQuestionsPageState
    extends State<OrchardManagementQuestionsPage> {
  final _scroll = ScrollController();

  bool _loading = true;
  String? _loadError;
  bool _submitting = false;

  int _currentIndex = 0;
  List<_Question> _questions = [];

  /// ✅ หน้านี้ “single-choice” เท่านั้น: question_id -> choice_id (String)
  final Map<String, String> _answers = {};

  @override
  void initState() {
    super.initState();
    _bootstrapOncePerUser();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // -----------------------------
  // Helpers
  // -----------------------------
  String? _readApiBaseUrl(SharedPreferences prefs) {
    final keys = <String>['api_base_url', 'apiBaseUrl', 'API_BASE'];
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  String? _readTokenFromPrefs(SharedPreferences prefs) {
    final keys = <String>['token', 'access_token'];
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  int? _readUserIdFromPrefs(SharedPreferences prefs) {
    final keys = <String>['user_id', 'userId', 'uid'];
    for (final k in keys) {
      final v = prefs.get(k);
      if (v is int) return v;
      if (v is String) {
        final n = int.tryParse(v.trim());
        if (n != null) return n;
      }
    }
    return null;
  }

  // -----------------------------
  // ✅ Ask once per user (Orchard Management)
  // -----------------------------
  String _orchardOnceKey(int userId) => 'orchard_mgmt_answered_user_$userId';

  bool _hasOrchardOnceFlag(SharedPreferences prefs, int userId) {
    return prefs.getBool(_orchardOnceKey(userId)) == true;
  }

  Future<void> _setOrchardOnceFlag(SharedPreferences prefs, int userId) async {
    await prefs.setBool(_orchardOnceKey(userId), true);
  }

  Future<bool> _hasOrchardAnswersInDb(
    String apiBase,
    String? token,
    int userId,
  ) async {
    final uri = _buildUri(
      apiBase,
      '/user_orchard_answers/read_user_orchard_answers.php',
      {'user_id': userId.toString()},
    );

    final json = await _getJson(uri, token);
    final list = _extractList(json);
    return list.isNotEmpty;
  }

  Future<void> _bootstrapOncePerUser() async {
    // editMode = ตั้งใจเข้ามาแก้ไข -> ต้องแสดงเสมอ
    if (widget.editMode) {
      _loadQuestionsFromDb();
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiBase = _readApiBaseUrl(prefs) ?? kDefaultApiBase;
      final token = _readTokenFromPrefs(prefs);
      final userId = _readUserIdFromPrefs(prefs);

      // ถ้าไม่รู้ user_id -> ตัดสินใจไม่ได้ ให้แสดงหน้าเหมือนเดิม
      if (userId == null) {
        _loadQuestionsFromDb();
        return;
      }

      // 1) เช็ค flag ในเครื่อง (เร็วสุด)
      if (_hasOrchardOnceFlag(prefs, userId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _goChemicalQuestions();
        });
        return;
      }

      // 2) เช็คจาก DB (รองรับกรณีเปลี่ยนเครื่อง/ล้างแอป)
      final answered = await _hasOrchardAnswersInDb(apiBase, token, userId);
      if (answered) {
        await _setOrchardOnceFlag(prefs, userId);
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _goChemicalQuestions();
        });
        return;
      }

      // ยังไม่เคยตอบ -> โหลดคำถามตามเดิม
      _loadQuestionsFromDb();
    } catch (_) {
      // ถ้าเช็คไม่ได้ (เช่น เน็ต/เซิร์ฟเวอร์) ให้แสดงหน้าเหมือนเดิม
      _loadQuestionsFromDb();
    }
  }

  Uri _buildUri(String base, String path,
      [Map<String, String>? queryParameters]) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    final normalized = (b.endsWith('/crud/api') && p.startsWith('/crud/api'))
        ? p.substring('/crud/api'.length)
        : p;
    return Uri.parse('$b$normalized').replace(queryParameters: queryParameters);
  }

  Map<String, String> _headers(String? token, {bool json = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json; charset=utf-8';
    if (token != null && token.trim().isNotEmpty) {
      h['Authorization'] = 'Bearer ${token.trim()}';
    }
    return h;
  }

  String _errText(Object e) {
    final s = e.toString();
    // กันข้อความขึ้น "Exception: ..."
    return s.replaceFirst('Exception: ', '').trim();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<dynamic> _getJson(Uri url, String? token) async {
    final res =
        await http.get(url, headers: _headers(token)).timeout(kHttpTimeout);
    final body = utf8.decode(res.bodyBytes);

    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: $body');
    }
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  List<dynamic> _extractList(dynamic json) {
    if (json == null) return <dynamic>[];
    if (json is List) return json;
    if (json is Map) {
      for (final k in ['records', 'data', 'items', 'result']) {
        final v = json[k];
        if (v is List) return v;
      }
      final v1 = json['data'];
      if (v1 is List) return v1;
      final v2 = json['records'];
      if (v2 is List) return v2;
    }
    return <dynamic>[];
  }

  String _pickString(Map<dynamic, dynamic> m, List<String> keys,
      {String fallback = ''}) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return fallback;
  }

  int _pickInt(Map<dynamic, dynamic> m, List<String> keys, {int fallback = 0}) {
    for (final k in keys) {
      final v = m[k];
      if (v is int) return v;
      if (v is String) {
        final n = int.tryParse(v.trim());
        if (n != null) return n;
      }
    }
    return fallback;
  }

  // -----------------------------
  // ✅ Load Questions from DB
  // -----------------------------
  Future<void> _loadQuestionsFromDb() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _questions = [];
      _currentIndex = 0;
      _answers.clear();
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiBase = _readApiBaseUrl(prefs) ?? kDefaultApiBase;
      final token = _readTokenFromPrefs(prefs);

      final qUri = _buildUri(
        apiBase,
        '/questions/read_questions.php',
        {'disease_id': kOrchardDiseaseId},
      );
      final qJson = await _getJson(qUri, token);
      final qList = _extractList(qJson);

      if (qList.isEmpty) {
        throw Exception(
          'ไม่พบคำถามจัดการสวนในระบบ (read_questions.php?disease_id=7 คืนค่าว่าง)',
        );
      }

      final List<_Question> built = [];

      for (final row in qList) {
        if (row is! Map) continue;
        final m = Map<dynamic, dynamic>.from(row);

        final qid = _pickString(m, ['question_id', 'id']);
        if (qid.isEmpty) continue;

        final isActive = _pickInt(m, ['is_active'], fallback: 1) == 1;
        if (!isActive) continue;

        final text = _pickString(m, ['question_text', 'text'], fallback: '');
        final sortOrder = _pickInt(m, ['sort_order', 'sortOrder'], fallback: 0);

        final choices = await _loadChoicesForQuestion(apiBase, token, qid);
        if (choices.isEmpty) continue;

        built.add(
          _Question(
            id: qid,
            text: text,
            sortOrder: sortOrder,
            isActive: isActive,
            choices: choices,
          ),
        );
      }

      if (built.isEmpty) {
        throw Exception(
          'โหลดคำถามได้ แต่ไม่มี choices ให้ตอบเลย (ตรวจ choices ตาม question_id)',
        );
      }

      built.sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        if (c != 0) return c;
        return int.tryParse(a.id)?.compareTo(int.tryParse(b.id) ?? 0) ??
            a.id.compareTo(b.id);
      });

      if (!mounted) return;
      setState(() {
        _questions = built;
        _currentIndex = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _errText(e);
      });
    }
  }

  Future<List<_Choice>> _loadChoicesForQuestion(
      String apiBase, String? token, String questionId) async {
    final uri = _buildUri(
      apiBase,
      '/choices/read_choices.php',
      {'question_id': questionId},
    );

    final json = await _getJson(uri, token);
    final list = _extractList(json);

    final out = <_Choice>[];
    for (final row in list) {
      if (row is! Map) continue;
      final m = Map<dynamic, dynamic>.from(row);

      final cid = _pickString(m, ['choice_id', 'id']);
      if (cid.isEmpty) continue;

      final label = _pickString(
        m,
        ['choice_label', 'label', 'choice_text', 'choices_text', 'text'],
        fallback: cid,
      );

      final advice = _pickString(
        m,
        ['choice_text', 'choices_text', 'advice_text', 'advice'],
        fallback: '',
      );

      final score = _pickInt(m, ['score_value', 'score'], fallback: 0);

      out.add(
        _Choice(
          id: cid,
          label: label,
          advice: advice,
          scoreValue: score,
        ),
      );
    }

    return out;
  }

  // -----------------------------
  // ✅ Submit Answers -> user_orchard_answers (single-choice)
  // -----------------------------
  Future<void> _submitAllAnswers() async {
    if (_submitting) return;

    setState(() => _submitting = true);

    try {
      // ✅ validate (ต้องตอบครบ)
      for (final q in _questions) {
        final cid = _answers[q.id];
        if (cid == null || cid.trim().isEmpty) {
          throw Exception('กรุณาตอบให้ครบทุกข้อ ก่อนบันทึก');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final apiBase = _readApiBaseUrl(prefs) ?? kDefaultApiBase;
      final token = _readTokenFromPrefs(prefs);
      final userId = _readUserIdFromPrefs(prefs);

      final url = _buildUri(
        apiBase,
        '/user_orchard_answers/create_user_orchard_answers.php',
      );

      for (final q in _questions) {
        final cid = _answers[q.id]!.trim();
        final choiceIdInt = int.tryParse(cid);

        final selected = q.choices.firstWhere(
          (c) => c.id == cid,
          orElse: () => _Choice(id: cid, label: cid, advice: '', scoreValue: 0),
        );

        final body = <String, dynamic>{
          if (userId != null) 'user_id': userId,
          'question_id': int.tryParse(q.id) ?? q.id,
          'choice_id': choiceIdInt ?? cid,
          'answer_text': selected.label,
          'numeric_value': null,
          'source': 'orchard_management',
        };

        final res = await http
            .post(
              url,
              headers: _headers(token, json: true),
              body: jsonEncode(body),
            )
            .timeout(kHttpTimeout);

        if (res.statusCode >= 300) {
          throw Exception('บันทึกไม่สำเร็จ: ${utf8.decode(res.bodyBytes)}');
        }
      }

      if (!mounted) return;

      // ✅ mark as completed (ถามครั้งเดียวต่อ user)
      if (userId != null) {
        await _setOrchardOnceFlag(prefs, userId);
      }

      if (widget.editMode) {
        Navigator.of(context).pop(true);
      } else {
        _goChemicalQuestions();
      }
    } catch (e) {
      _toast(_errText(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _goChemicalQuestions() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChemicalQuestionsPage(
          treeId: widget.treeId,
          treeName: widget.treeName,
          diseaseId: widget.diseaseId,
          diseaseName: widget.diseaseName,
        ),
      ),
    );
  }

  String _bubbleText() {
    if (widget.editMode) return 'แก้ไขคำตอบการจัดการสวน';
    return 'คำถามจัดการสวน (ถามครั้งเดียวต่อผู้ใช้)';
  }

  // -----------------------------
  // UI
  // -----------------------------
  Widget _greenOptionTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _submitting ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? kPrimaryGreen : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kPrimaryGreen, width: 2),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : kPrimaryGreen,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: kPrimaryGreen,
          elevation: 0,
          title: Text(widget.editMode ? 'จัดการสวนส้ม' : 'คำถามจัดการสวนส้ม'),
        ),
        body: const SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: kPrimaryGreen,
          elevation: 0,
          title: Text(widget.editMode ? 'จัดการสวนส้ม' : 'คำถามจัดการสวนส้ม'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'โหลดคำถามไม่สำเร็จ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(_loadError ?? ''),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _loadQuestionsFromDb,
                  child: const Text('ลองใหม่'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: kPrimaryGreen,
          elevation: 0,
          title: Text(widget.editMode ? 'จัดการสวนส้ม' : 'คำถามจัดการสวนส้ม'),
        ),
        body: const SafeArea(
          child: Center(child: Text('ไม่พบคำถามในระบบ')),
        ),
      );
    }

    if (_currentIndex < 0) _currentIndex = 0;
    if (_currentIndex >= _questions.length) _currentIndex = _questions.length - 1;

    final q = _questions[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        elevation: 0,
        title: Text(widget.editMode ? 'จัดการสวนส้ม' : 'คำถามจัดการสวนส้ม'),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.spa, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _bubbleText(),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_currentIndex + 1}/${_questions.length}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    q.text,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Column(
                    children: List.generate(q.choices.length, (i) {
                      final c = q.choices[i];
                      final cur = _answers[q.id];
                      final selected = (cur == c.id);

                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: i == q.choices.length - 1 ? 0 : 12,
                        ),
                        child: _greenOptionTile(
                          label: c.label,
                          selected: selected,
                          onTap: () async {
                            setState(() {
                              _answers[q.id] = c.id;
                            });

                            await Future.delayed(
                                const Duration(milliseconds: 250));
                            if (!mounted) return;

                            if (_currentIndex < _questions.length - 1) {
                              setState(() => _currentIndex += 1);
                              _scroll.animateTo(
                                0,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            } else {
                              await _submitAllAnswers();
                            }
                          },
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            if (_submitting)
              Container(
                color: Colors.black12,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
