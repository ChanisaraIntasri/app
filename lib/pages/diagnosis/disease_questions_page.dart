import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'treatment_advice_page.dart';
const kPrimaryGreen = Color(0xFF005E33);
const kPageBg = Color.fromARGB(255, 255, 255, 255);
const kCardBg = Colors.white;

const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api',
);

String _joinApi(String base, String path) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final p = path.startsWith('/') ? path : '/$path';
  return '$b$p';
}

String _s(dynamic v) => v == null ? '' : v.toString().trim();

double _toDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  return double.tryParse(s) ?? fallback;
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  return int.tryParse(s) ?? fallback;
}

String _normKey(String s) => s.trim().toLowerCase();

String _severityToCode(String s) {
  final t = _normKey(s);
  // รองรับทั้งไทย/อังกฤษแบบที่พบบ่อย
  if (t.contains('high') || t.contains('สูง') || t.contains('รุนแรง')) return 'high';
  if (t.contains('medium') || t.contains('กลาง') || t.contains('ปานกลาง')) return 'medium';
  if (t.contains('low') || t.contains('ต่ำ') || t.contains('น้อย')) return 'low';
  return t;
}

Future<void> _cacheTreatmentPlanOverride({
  required String diseaseName,
  required String severityName,
  required int everyDays,
  required int totalTimes,
  String taskName = 'พ่นยา',
}) async {
  if (everyDays <= 0 || totalTimes <= 0) return;

  final prefs = await SharedPreferences.getInstance();
  const storageKey = 'treatment_plan_overrides_v1';

  Map<String, dynamic> root = {};
  final raw = prefs.getString(storageKey);
  if (raw != null && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        root = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
  }

  final diseaseK = _normKey(diseaseName);
  final sevK1 = _normKey(severityName);
  final sevK2 = _severityToCode(severityName);

  // เก็บหลายคีย์กันพลาด (กรณี severity ใน Share เป็นไทย/อังกฤษไม่ตรงกัน)
  final keys = <String>{
    '${diseaseK}__${sevK1}',
    '${diseaseK}__${sevK2}',
  };

  final payload = {
    'everyDays': everyDays,
    'totalTimes': totalTimes,
    'taskName': taskName,
    'savedAt': DateTime.now().toIso8601String(),
  };

  for (final k in keys) {
    root[k] = payload;
  }

  await prefs.setString(storageKey, jsonEncode(root));
}


class _Choice {
  final String id;
  final String label;
  final double score;

  const _Choice({required this.id, required this.label, required this.score});

  factory _Choice.fromJson(Map<String, dynamic> m) {
    return _Choice(
      id: _s(m['choice_id'] ?? m['id'] ?? m['choiceId']),
      label: _s(m['choice_label'] ?? m['label'] ?? m['choice_text'] ?? m['text']),
      score: _toDouble(m['score_value'] ?? m['score'] ?? m['value'] ?? 0, 0),
    );
  }
}

class _DiseaseQuestion {
  final String diseaseQuestionId; // pivot id
  final String questionId;
  final String questionText;
  final String type;

  _DiseaseQuestion({
    required this.diseaseQuestionId,
    required this.questionId,
    required this.questionText,
    required this.type,
  });

  factory _DiseaseQuestion.fromJson(Map<String, dynamic> m) {
    final dqid = _s(m['disease_question_id'] ?? m['dq_id'] ?? m['id']);
    final qid = _s(m['question_id'] ?? m['qid'] ?? m['questionId']);
    final qt = _s(m['question_text'] ?? m['text'] ?? m['question']);
    final t = _s(m['question_type'] ?? m['type']);
    return _DiseaseQuestion(
      diseaseQuestionId: dqid,
      questionId: qid,
      questionText: qt,
      type: t.isEmpty ? 'yes_no' : t,
    );
  }
}

class DiseaseQuestionsPage extends StatefulWidget {
  final String treeId;
  // (optional) ใช้แสดงชื่อ “ต้นส้ม” ที่กำลังทำแบบสอบถาม
  final String? treeName;
  final String diseaseId;
  final String diseaseName;

  const DiseaseQuestionsPage({
    super.key,
    required this.treeId,
    this.treeName,
    required this.diseaseId,
    required this.diseaseName,
  });

  @override
  State<DiseaseQuestionsPage> createState() => _DiseaseQuestionsPageState();
}

class _DiseaseQuestionsPageState extends State<DiseaseQuestionsPage> {
  final _scroll = ScrollController();

  bool loading = true;
  bool _submitting = false;
  String error = '';

  int _currentIndex = 0;

  List<_DiseaseQuestion> questions = [];
  Map<String, List<_Choice>> choicesByDiseaseQuestionId = {};

  /// answers:
  /// - yes_no / numeric / single: store selected choice_id as String
  /// - multi: store Set<String> of choice_id
  Map<String, dynamic> answers = {};

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

  Map<String, String> _jsonHeaders(String? token) => {
        ..._headers(token),
        'Content-Type': 'application/json; charset=utf-8',
      };

  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is Map) {
      if (decoded['data'] is List) return decoded['data'] as List;
      if (decoded['records'] is List) return decoded['records'] as List;
      if (decoded['items'] is List) return decoded['items'] as List;
      if (decoded['results'] is List) return decoded['results'] as List;
    }
    if (decoded is List) return decoded;
    return [];
  }

  String _extractErr(dynamic decoded) {
    if (decoded is Map) {
      if (decoded['ok'] == false) return _s(decoded['message'] ?? decoded['error']);
      final e = _s(decoded['error'] ?? decoded['message']);
      if (e.isNotEmpty && decoded['ok'] != true) return e;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      loading = true;
      error = '';
      _currentIndex = 0;
      answers = {};
      questions = [];
      choicesByDiseaseQuestionId = {};
    });

    try {
      final token = await _readToken();

      // 1) load disease_questions (pivot) -> questions
      final q = await _fetchDiseaseQuestions(token);
      questions = q;

      // 2) load choices for each disease_question_id
      final map = <String, List<_Choice>>{};
      for (final dq in questions) {
        map[dq.diseaseQuestionId] = await _fetchChoices(token, dq.diseaseQuestionId, dq.type);
      }
      choicesByDiseaseQuestionId = map;

      setState(() {
        loading = false;
        error = '';
      });
    } catch (e) {
      setState(() {
        loading = false;
        error = 'โหลดคำถามไม่สำเร็จ: $e';
      });
    }
  }

  Future<List<_DiseaseQuestion>> _fetchDiseaseQuestions(String? token) async {
    final did = Uri.encodeComponent(widget.diseaseId);
    final paths = <String>[
      '/disease_questions/read_disease_questions.php?disease_id=$did',
      '/disease_questions/search_disease_questions.php?disease_id=$did',
      '/disease_questions/read_disease_questions.php',
      '/disease_questions/search_disease_questions.php',
    ];

    for (final p in paths) {
      try {
        final url = Uri.parse(_joinApi(API_BASE, p));
        final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;

        final decoded = jsonDecode(res.body);
        final errMsg = _extractErr(decoded);
        if (errMsg.isNotEmpty) continue;

        final list = _extractList(decoded)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        // filter by disease_id if needed
        final filtered = list.where((x) {
          final d = _s(x['disease_id'] ?? x['diseaseId']);
          return d.isEmpty || d == widget.diseaseId;
        }).toList();

        final src = filtered.isNotEmpty ? filtered : list;
        return src.map((m) => _DiseaseQuestion.fromJson(m)).toList();
      } catch (_) {}
    }

    return [];
  }

  Future<List<_Choice>> _fetchChoices(String? token, String diseaseQuestionId, String qType) async {
    final dq = Uri.encodeComponent(diseaseQuestionId);
    final paths = <String>[
      '/choices/read_choices.php?disease_question_id=$dq',
      '/choices/search_choices.php?disease_question_id=$dq',
      '/choices/read_choices.php',
      '/choices/search_choices.php',
    ];

    for (final p in paths) {
      try {
        final url = Uri.parse(_joinApi(API_BASE, p));
        final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;

        final decoded = jsonDecode(res.body);
        final errMsg = _extractErr(decoded);
        if (errMsg.isNotEmpty) continue;

        final list = _extractList(decoded)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        // filter by disease_question_id if needed
        final filtered = list.where((x) {
          final id = _s(x['disease_question_id'] ?? x['dq_id'] ?? x['diseaseQuestionId']);
          return id.isEmpty || id == diseaseQuestionId;
        }).toList();

        final src = filtered.isNotEmpty ? filtered : list;

        // ✅ ไม่กำหนด fallback ในแอป: ให้ดึงจากฐานข้อมูล/ API เท่านั้น
        return src.map((m) => _Choice.fromJson(m)).where((c) => c.id.isNotEmpty).toList();
      } catch (_) {}
    }

    return [];
  }

  bool _isAnswered(_DiseaseQuestion q) {
    final v = answers[q.diseaseQuestionId];
    if (q.type == 'multi') {
      return v is Set<String> && v.isNotEmpty;
    }
    return v != null && _s(v).isNotEmpty;
  }

  bool _validate() {
    for (final q in questions) {
      if (!_isAnswered(q)) return false;
    }
    return true;
  }

  void _goNext() {
    final q = questions[_currentIndex];
    if (!_isAnswered(q)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาตอบคำถามก่อนกดถัดไป')),
      );
      return;
    }

    if (_currentIndex < questions.length - 1) {
      setState(() => _currentIndex += 1);
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _goBack() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex -= 1);
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  double _calcTotalScore() {
    double total = 0;

    for (final q in questions) {
      final v = answers[q.diseaseQuestionId];
      final choices = choicesByDiseaseQuestionId[q.diseaseQuestionId] ?? const [];

      if (choices.isNotEmpty) {
        if (q.type == 'multi') {
          if (v is Set<String>) {
            for (final id in v) {
              final c = choices.where((x) => x.id == id).toList();
              if (c.isNotEmpty) total += c.first.score;
            }
          }
        } else {
          final id = v?.toString();
          if (id != null && id.isNotEmpty) {
            final c = choices.where((x) => x.id == id).toList();
            if (c.isNotEmpty) total += c.first.score;
          }
        }
      }

      // ✅ fallback: ถ้าเป็น numeric แต่ไม่มี choices ให้ใช้ค่าที่กรอกเป็นคะแนน
      if (choices.isEmpty && q.type == 'numeric') {
        final num = double.tryParse(_s(v));
        if (num != null) total += num;
      }
    }

    return total;
  }

  Future<List<Map<String, dynamic>>> _fetchRiskLevels(String? token) async {
    final params = '?disease_id=${Uri.encodeComponent(widget.diseaseId)}';
    final paths = <String>[
      '/disease_risk_levels/read_disease_risk_levels.php$params',
      '/disease_risk_levels/search_disease_risk_levels.php$params',
      '/disease_risk_levels/read_disease_risk_levels.php',
      '/disease_risk_levels/search_disease_risk_levels.php',
    ];

    for (final p in paths) {
      try {
        final url = Uri.parse(_joinApi(API_BASE, p));
        final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;

        final decoded = jsonDecode(res.body);
        final errMsg = _extractErr(decoded);
        if (errMsg.isNotEmpty) continue;

        final list = _extractList(decoded)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        final filtered = list.where((x) {
          final did = _s(x['disease_id'] ?? x['diseaseId']);
          return did.isEmpty || did == widget.diseaseId;
        }).toList();

        if (filtered.isNotEmpty) return filtered;
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }
    return [];
  }

  Map<String, dynamic> _pickRiskLevel(double total, List<Map<String, dynamic>> levels) {
    if (levels.isEmpty) {
      return {'id': '', 'name': 'ไม่พบระดับความรุนแรง', 'days': 0, 'times': 0, 'code': ''};
    }

    double minOf(Map<String, dynamic> m) => _toDouble(
          m['min_score'] ?? m['min'] ?? m['min_value'] ?? m['score_min'] ?? 0,
          0,
        );

    double maxOf(Map<String, dynamic> m) {
      final raw = m['max_score'] ?? m['max'] ?? m['max_value'] ?? m['score_max'];
      if (raw == null) return -1; // -1 = ไม่ได้กำหนด max
      return _toDouble(raw, -1);
    }

    int daysOf(Map<String, dynamic> m) => _toInt(
          m['days'] ?? m['every_days'] ?? m['interval_days'] ?? m['treatment_every_days'] ?? 0,
          0,
        );

    int timesOf(Map<String, dynamic> m) => _toInt(
          m['times'] ?? m['total_times'] ?? m['count'] ?? m['treatment_total_times'] ?? 0,
          0,
        );

    String idOf(Map<String, dynamic> m) => _s(m['risk_level_id'] ?? m['level_id'] ?? m['id']);

    String codeOf(Map<String, dynamic> m) =>
        _s(m['level_code'] ?? m['code'] ?? m['severity_code'] ?? '');

    String nameOf(Map<String, dynamic> m) {
      final n = _s(m['risk_level_name'] ??
          m['level_name'] ??
          m['name'] ??
          m['title'] ??
          m['severity_name'] ??
          m['level_code']); // ✅ รองรับกรณี API ส่งมาเป็น level_code
      final fallback = _s(m['risk_level'] ?? m['severity'] ?? m['level'] ?? m['level_code']);
      return n.isNotEmpty ? n : (fallback.isNotEmpty ? fallback : 'ระดับความรุนแรง');
    }

    final list = levels.toList()..sort((a, b) => minOf(a).compareTo(minOf(b)));

    // 1) ถ้ามี max_score → match ช่วงคะแนน
    for (final r in list) {
      final mn = minOf(r);
      final mx = maxOf(r);
      if (mx >= 0) {
        if (total >= mn && total <= mx) {
          return {
            'id': idOf(r),
            'name': nameOf(r),
            'days': daysOf(r),
            'times': timesOf(r),
            'code': codeOf(r),
          };
        }
      }
    }

    // 2) ถ้าไม่มี max_score → เลือกตัวที่ min_score <= total ที่ “มากที่สุด”
    Map<String, dynamic>? best;
    for (final r in list) {
      final mn = minOf(r);
      if (total >= mn) best = r;
    }
    best ??= list.first;

    return {
      'id': idOf(best),
      'name': nameOf(best),
      'days': daysOf(best),
      'times': timesOf(best),
      'code': codeOf(best),
    };
  }

  Future<List<String>> _fetchAdvice(String? token, String riskLevelId) async {
    final did = Uri.encodeComponent(widget.diseaseId);
    final rid = Uri.encodeComponent(riskLevelId);

    final paths = <String>[
      '/treatments/read_treatments.php?disease_id=$did&risk_level_id=$rid',
      '/treatments/search_treatments.php?disease_id=$did&risk_level_id=$rid',
      '/treatments/read_treatments.php?disease_id=$did',
      '/treatments/search_treatments.php?disease_id=$did',
      '/treatments/read_treatments.php',
      '/treatments/search_treatments.php',
    ];

    List<Map<String, dynamic>> list = [];
    for (final p in paths) {
      try {
        final url = Uri.parse(_joinApi(API_BASE, p));
        final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;

        final decoded = jsonDecode(res.body);
        final errMsg = _extractErr(decoded);
        if (errMsg.isNotEmpty) continue;

        list = _extractList(decoded)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        if (list.isNotEmpty) break;
      } catch (_) {}
    }

    final filtered = list.where((x) {
      final did2 = _s(x['disease_id'] ?? x['diseaseId']);
      final rid2 = _s(x['risk_level_id'] ?? x['level_id'] ?? x['riskLevelId']);
      final didOk = did2.isEmpty || did2 == widget.diseaseId;
      final ridOk = riskLevelId.isEmpty || rid2.isEmpty || rid2 == riskLevelId;
      return didOk && ridOk;
    }).toList();

    final src = filtered.isNotEmpty ? filtered : list;

    final out = <String>[];
    for (final m in src) {
      final advice = _s(m['advice_text'] ??
          m['advice'] ??
          m['treatment'] ??
          m['description'] ??
          m['detail']);
      if (advice.isNotEmpty) out.add(advice);
    }
    return out;
  }


  /// ✅ ดึง treatment_id (เพื่อบันทึกลง care_reminders)
  /// - คืนค่า id แรกที่ match (disease_id + risk_level_id)
  Future<int?> _fetchTreatmentId(String? token, String riskLevelId) async {
    final did = Uri.encodeComponent(widget.diseaseId);
    final rid = Uri.encodeComponent(riskLevelId);

    final paths = <String>[
      '/treatments/read_treatments.php?disease_id=$did&risk_level_id=$rid',
      '/treatments/search_treatments.php?disease_id=$did&risk_level_id=$rid',
      '/treatments/read_treatments.php?disease_id=$did',
      '/treatments/search_treatments.php?disease_id=$did',
      '/treatments/read_treatments.php',
      '/treatments/search_treatments.php',
    ];

    List<Map<String, dynamic>> list = [];
    for (final p in paths) {
      try {
        final url = Uri.parse(_joinApi(API_BASE, p));
        final res = await http
            .get(url, headers: _headers(token))
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;

        final decoded = jsonDecode(res.body);
        final errMsg = _extractErr(decoded);
        if (errMsg.isNotEmpty) continue;

        list = _extractList(decoded)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        if (list.isNotEmpty) break;
      } catch (_) {}
    }

    // filter ให้ตรงโรค + ระดับ (ถ้ามี)
    final filtered = list.where((x) {
      final did2 = _s(x['disease_id'] ?? x['diseaseId']);
      final rid2 = _s(x['risk_level_id'] ?? x['level_id'] ?? x['riskLevelId']);
      final didOk = did2.isEmpty || did2 == widget.diseaseId;
      final ridOk = riskLevelId.isEmpty || rid2.isEmpty || rid2 == riskLevelId;
      return didOk && ridOk;
    }).toList();

    final src = filtered.isNotEmpty ? filtered : list;
    for (final m in src) {
      final raw = m['treatment_id'] ?? m['treatmentId'] ?? m['id'];
      final id = int.tryParse(raw?.toString() ?? '');
      if (id != null) return id;
    }
    return null;
  }

  Future<Map<String, dynamic>> _createDiagnosisHistory(
    String? token, {
    required int treeId,
    required int diseaseId,
    String? riskLevelId,
    required int totalScore,
    String? imageUrl,
  }) async {
    final url = Uri.parse(
      _joinApi(API_BASE, '/diagnosis_history/create_diagnosis_history.php'),
    );

    final body = <String, dynamic>{
      'tree_id': treeId,
      'disease_id': diseaseId,
      'total_score': totalScore,
    };

    final rid = (riskLevelId ?? '').trim();
    if (rid.isNotEmpty && rid != '-' && rid != '0') {
      body['risk_level_id'] = rid;
    }

    final img = (imageUrl ?? '').trim();
    if (img.isNotEmpty) body['image_url'] = img;

    final res = await http
        .post(url, headers: _jsonHeaders(token), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));

    final status = res.statusCode;

    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }

    if (decoded is Map) {
      final m = Map<String, dynamic>.from(decoded);
      m['_http_status'] = status;
      return m;
    }

    return {
      'ok': false,
      'error': 'INVALID_RESPONSE',
      'message': 'invalid_json',
      '_http_status': status,
      'raw': res.body,
    };
  }

  Future<void> _submit() async {
    if (_submitting) return;

    if (!_validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังตอบไม่ครบทุกข้อ')),
      );
      return;
    }

    final total = _calcTotalScore();
    final totalInt = total.round();

    setState(() => _submitting = true);

    try {
      int? diagnosisHistoryId;
      final token = await _readToken();
      final tkn = (token ?? '').trim();

      final levels = await _fetchRiskLevels(tkn.isEmpty ? null : tkn);
      final picked = _pickRiskLevel(total, levels);

      final riskLevelId = _s(picked['id']);
      final riskLevelCode = _s(picked['code']);
      final riskLevelName =
          (_s(picked['name']).isNotEmpty ? _s(picked['name']) : riskLevelCode);

      final planEveryDays = _toInt(picked['days']);
      final planTotalTimes = _toInt(picked['times']);

      // ✅ แคชแผนการรักษาไว้ให้หน้า Home ใช้ (เก็บทั้ง "ชื่อระดับ" และ "code")
      await _cacheTreatmentPlanOverride(
        diseaseName: widget.diseaseName,
        severityName: riskLevelName,
        everyDays: planEveryDays,
        totalTimes: planTotalTimes,
        taskName: 'พ่นยา',
      );

      if (riskLevelCode.isNotEmpty &&
          _normKey(riskLevelCode) != _normKey(riskLevelName)) {
        await _cacheTreatmentPlanOverride(
          diseaseName: widget.diseaseName,
          severityName: riskLevelCode,
          everyDays: planEveryDays,
          totalTimes: planTotalTimes,
          taskName: 'พ่นยา',
        );
      }

// ✅ POST บันทึก diagnosis_history
      String saveNote = '';
      final treeIdInt = int.tryParse(widget.treeId) ?? 0;
      final diseaseIdInt = int.tryParse(widget.diseaseId) ?? 0;

      if (tkn.isEmpty) {
        saveNote = '⚠️ ไม่พบ token จึงบันทึกประวัติไม่ได้ (ลองล็อกอินใหม่)';
      } else if (treeIdInt <= 0 || diseaseIdInt <= 0) {
        saveNote = '⚠️ tree_id/disease_id ไม่ถูกต้อง จึงบันทึกประวัติไม่ได้';
      } else {
        final r = await _createDiagnosisHistory(
          tkn,
          treeId: treeIdInt,
          diseaseId: diseaseIdInt,
          riskLevelId: riskLevelId,
          totalScore: totalInt,
        );

        final ok = r['ok'] == true;
        if (ok) {
          int? newId;
          final data = r['data'];
          if (data is Map) {
            final rawId =
                data['diagnosis_history_id'] ?? data['id'] ?? data['history_id'];
            newId = int.tryParse((rawId ?? '').toString());
          }
          saveNote = newId != null
              ? '✅ บันทึกประวัติการวินิจฉัยแล้ว (#$newId)'
              : '✅ บันทึกประวัติการวินิจฉัยแล้ว';
        } else {
          final msg = (r['message'] ?? r['error'] ?? 'create_failed').toString();
          final httpStatus = (r['_http_status'] ?? '').toString();
          saveNote = '⚠️ บันทึกประวัติไม่สำเร็จ ($httpStatus): $msg';
        }

        debugPrint(
          "create_diagnosis_history status=${r['_http_status']} ok=${r['ok']} message=${r['message']}",
        );

        // ✅ ดึง diagnosis_history_id จาก response (ถ้ามี)
        try {
          final data = r['data'];
          if (data is Map) {
            diagnosisHistoryId = int.tryParse(
              '${data['diagnosis_history_id'] ?? data['id'] ?? data['insert_id'] ?? ''}',
            );
          }
          diagnosisHistoryId ??= int.tryParse(
            '${r['diagnosis_history_id'] ?? r['id'] ?? r['insert_id'] ?? ''}',
          );
        } catch (_) {}

      }

      final adviceList = await _fetchAdvice(tkn.isEmpty ? null : tkn, riskLevelId);

      // ✅ หา treatment_id ที่ match (ถ้ามี)
      final int? treatmentId = await _fetchTreatmentId(
        tkn.isEmpty ? null : tkn,
        riskLevelId,
      );

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TreatmentAdvicePage(
            treeId: widget.treeId,
            diseaseId: widget.diseaseId,
            diseaseName: widget.diseaseName,
            diagnosisHistoryId: diagnosisHistoryId,
            treatmentId: treatmentId,
            totalScore: total,
            riskLevelId: riskLevelId.isEmpty ? '-' : riskLevelId,
            riskLevelName:
                riskLevelName.isEmpty ? 'ไม่พบระดับความรุนแรง' : riskLevelName,
            adviceList: adviceList.isEmpty
                ? const ['ยังไม่มีคำแนะนำในระดับความรุนแรงนี้']
                : adviceList,
            note: saveNote,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดตอนสร้างคำแนะนำ/บันทึกประวัติ: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// ✅ Header แบบในภาพ (โทนเขียว) + progress
Widget _header() {
  final total = questions.length;
  final current = total == 0 ? 0 : (_currentIndex + 1);
  final value = total == 0 ? 0.0 : current / total;
  final percent = (value * 100).clamp(0, 100).toStringAsFixed(0);

  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          kPrimaryGreen,
          kPrimaryGreen.withOpacity(0.92),
        ],
      ),
),
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // เผื่อให้ title อยู่กึ่งกลาง (ซ้ายว่างเท่า IconButton)
              const SizedBox(width: 40),
              const Expanded(
                child: Center(
                  child: Text(
                    'อาการของต้นส้ม',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$percent % completed',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

void _onBackPressed() {
  if (_currentIndex > 0) {
    _goBack();
  } else {
    Navigator.of(context).maybePop();
  }
}

Widget _topControlsRow() {
  return Row(
    children: [
      // ปุ่มย้อนกลับแบบวงกลม
      InkWell(
        onTap: _onBackPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.arrow_back, color: Colors.black87),
        ),
      ),
      
    ],
  );
}

Widget _selectedBubble() {
  final text = (widget.treeName != null && widget.treeName!.trim().isNotEmpty)
      ? '${widget.diseaseName} • ${widget.treeName}'
      : widget.diseaseName;

  return Align(
    alignment: Alignment.centerRight,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: kPrimaryGreen,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

Widget _questionCard(_DiseaseQuestion q, {required int index, required int total}) {
  final dqid = q.diseaseQuestionId;
  final choices = choicesByDiseaseQuestionId[dqid] ?? const [];
  final type = q.type;

  // ซ่อนปุ่มถัดไป/ยืนยัน เมื่อเป็น single-choice (เหมือนในภาพ) → แตะแล้วไปข้อถัดไปอัตโนมัติ
  final autoAdvance = choices.isNotEmpty && type != 'multi';

  // ✅ multi-choice: เติมข้อความกำกับให้เหมือนในตัวอย่าง (ถ้ายังไม่มี)
  // NOTE: ห้ามขึ้นบรรทัดใหม่ใน single-quote โดยตรง → ใช้ \n แทน
  final displayText = (type == 'multi' && !q.questionText.contains('ตอบได้มากกว่า'))
      ? '${q.questionText}\n(ตอบได้มากกว่า 1 ข้อ)'
      : q.questionText;

  return Container(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
    decoration: BoxDecoration(
      color: kCardBg,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          displayText,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.black.withOpacity(0.72),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 18),
        _questionInput(q, choices, autoAdvance: autoAdvance),
      ],
    ),
  );
}

Future<void> _pickSingleChoiceAndMaybeNext(String dqid, String choiceId) async {
  setState(() => answers[dqid] = choiceId);

  // หน่วงนิดให้ UI เห็นการกด
  await Future.delayed(const Duration(milliseconds: 120));
  if (!mounted) return;

  final isLast = _currentIndex >= questions.length - 1;
  if (isLast) {
    await _submit();
  } else {
    _goNext();
  }
}

  Widget _questionInput(_DiseaseQuestion q, List<_Choice> choices, {required bool autoAdvance}) {
    final dqid = q.diseaseQuestionId;
    final type = q.type;

    // ✅ ไม่ hardcode choice (ดึงจากฐานข้อมูลเท่านั้น)
    if (choices.isEmpty) {
      if (type == 'numeric') {
        final current = _s(answers[dqid]);
        return TextFormField(
          initialValue: current,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'กรอกตัวเลข',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kPrimaryGreen, width: 2),
            ),
          ),
          onChanged: (v) => setState(() => answers[dqid] = v),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) {
            if (_s(answers[dqid]).isEmpty) return;
            final isLast = _currentIndex >= questions.length - 1;
            if (isLast) {
              _submit();
            } else {
              _goNext();
            }
          },
        );
      }

      return const Text(
        'ยังไม่มีตัวเลือกคำตอบจากฐานข้อมูลสำหรับคำถามนี้\n'
        '(โปรดเพิ่ม choices และคะแนนในระบบแอดมินก่อน)',
        textAlign: TextAlign.center,
      );
    }

    if (type == 'multi') {
      final selected = (answers[dqid] is Set<String>)
          ? (answers[dqid] as Set<String>)
          : <String>{};

      // ✅ แสดงตัวเลือกแบบกรอบยาว + checkbox เหมือนในภาพ (ตอบได้มากกว่า 1 ข้อ)
      return Column(
        children: choices.map((c) {
          final checked = selected.contains(c.id);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                final next = Set<String>.from(selected);
                if (checked) {
                  next.remove(c.id);
                } else {
                  next.add(c.id);
                }
                setState(() => answers[dqid] = next);
              },
              child: Container(
                width: double.infinity,
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kPrimaryGreen, width: 2),
                  color: checked ? kPrimaryGreen.withOpacity(0.06) : Colors.transparent,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: kPrimaryGreen, width: 2),
                        color: checked ? kPrimaryGreen : Colors.transparent,
                      ),
                      child: checked
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        c.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kPrimaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      );
    }

    // ✅ single choice

    // ✅ single choice → ปุ่มแบบในภาพ
    final selectedId = _s(answers[dqid]);

    return Column(
      children: choices.map((c) {
        final isSelected = selectedId == c.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: kPrimaryGreen,
                backgroundColor: isSelected ? kPrimaryGreen.withOpacity(0.08) : Colors.transparent,
                side: const BorderSide(color: kPrimaryGreen, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              onPressed: () {
                if (autoAdvance) {
                  _pickSingleChoiceAndMaybeNext(dqid, c.id);
                } else {
                  setState(() => answers[dqid] = c.id);
                }
              },
              child: Text(
                c.label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _navButtons() {
    if (questions.isEmpty) return const SizedBox.shrink();

    final q = questions[_currentIndex.clamp(0, questions.length - 1)];

    // ✅ แสดงปุ่ม "ต่อไป" เฉพาะคำถามที่ตอบได้หลายข้อ (multi) เท่านั้น
    if (q.type != 'multi') {
      return const SizedBox(height: 14);
    }

    final canNext = _isAnswered(q);
    final isLast = _currentIndex >= questions.length - 1;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (_submitting || !canNext)
                ? null
                : (isLast ? _submit : _goNext),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE5E5E5),
              disabledForegroundColor: const Color(0xFF9E9E9E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: Text(
              isLast ? 'ยืนยัน' : 'ต่อไป',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuestions = questions.isNotEmpty;
    final total = questions.length;

    return Scaffold(
      backgroundColor: kPageBg,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(error, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen),
                                onPressed: _loadAll,
                                child: const Text('ลองใหม่'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : !hasQuestions
                        ? const Center(child: Text('โรคนี้ยังไม่มีคำถาม'))
                        : SafeArea(
                            top: false,
                            child: Column(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: _scroll,
                                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        _topControlsRow(),
                                        const SizedBox(height: 10),
                                        _selectedBubble(),
                                        const SizedBox(height: 14),
                                        _questionCard(
                                          questions[_currentIndex.clamp(0, total - 1)],
                                          index: _currentIndex.clamp(0, total - 1),
                                          total: total,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _navButtons(),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
