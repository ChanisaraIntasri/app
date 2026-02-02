import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/citrus_tree_record.dart';

const kPrimaryGreen = Color(0xFF005E33);
const kBg = Color.fromARGB(255, 255, 255, 255);
const kCardBg = Color(0xFFEDEDED);

// ✅ ใช้เหมือนไฟล์อื่น: ให้ส่งตอน run/build ด้วย --dart-define=API_BASE=...
// ตัวอย่าง: flutter run --dart-define=API_BASE=https://xxxx.ngrok-free.dev/crud/api
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api',
);

String _joinApi(String base, String path) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final p = path.startsWith('/') ? path : '/$path';
  return '$b$p';
}

// ✅ เดา backend origin จาก API_BASE (…/crud/api -> …/crud)
String _backendOriginFromApiBase(String apiBase) {
  var b = apiBase.endsWith('/') ? apiBase.substring(0, apiBase.length - 1) : apiBase;
  if (b.endsWith('/api')) b = b.substring(0, b.length - 4);
  return b;
}

String _s(dynamic v) => (v ?? '').toString().trim();
int _toInt(dynamic v, [int def = 0]) => int.tryParse(_s(v)) ?? def;

DateTime? _toDate(dynamic v) {
  final s = _s(v);
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

DateTime? _parseDateOnly(dynamic v) {
  final s = _s(v);
  if (s.isEmpty) return null;
  final dt = DateTime.tryParse(s);
  if (dt == null) return null;
  return DateTime(dt.year, dt.month, dt.day);
}

String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

String _pickText(Map<String, dynamic> m, List<String> keys, {String fallback = ''}) {
  for (final k in keys) {
    final val = _s(m[k]);
    if (val.isNotEmpty) return val;
  }
  return fallback;
}

bool _isSuccess(dynamic decoded) {
  if (decoded is List) return true;
  if (decoded is Map) {
    final ok = decoded['ok'];
    final success = decoded['success'];
    final status = decoded['status'];

    if (ok is bool) return ok;
    if (success is bool) return success;
    if (status is bool) return status;

    return true;
  }
  return false;
}

String _extractErr(dynamic decoded) {
  if (decoded is Map) {
    final err = decoded['error'];
    final msg = decoded['message'];
    final detail = decoded['detail'];

    final sErr = _s(err);
    final sMsg = _s(msg);
    final sDetail = _s(detail);

    final hasFlag = decoded.containsKey('ok') ||
        decoded.containsKey('success') ||
        decoded.containsKey('status');
    if (hasFlag && !_isSuccess(decoded)) {
      if (sMsg.isNotEmpty) return sMsg;
      if (sErr.isNotEmpty) return sErr;
      if (sDetail.isNotEmpty) return sDetail;
      return 'request_failed';
    }

    if (sErr.isNotEmpty && sErr != '0') return sErr;
    if (sMsg.isNotEmpty && sMsg.toLowerCase().contains('error')) return sMsg;
  }
  return '';
}

String _severityFromLevelCode(String codeOrText) {
  final raw = codeOrText.trim();
  final lower = raw.toLowerCase();
  if (raw.isEmpty || lower == 'unknown' || lower == 'null' || raw == '-') return '-';

  if (lower == 'low' || lower == 'mild' || raw == 'น้อย') return 'น้อย';
  if (lower == 'medium' || lower == 'moderate' || raw == 'ปานกลาง') return 'ปานกลาง';
  if (lower == 'high' || lower == 'severe' || raw == 'มาก') return 'มาก';

  return raw;
}

class DiagnosisHistoryItem {
  final int id;
  final int treeId;
  final int diseaseId;
  final int? riskLevelId;
  final int totalScore;
  final String imageUrl;
  final DateTime? diagnosedAt;


  // ✅ สถานะการรักษาจากปฏิทิน (care_reminders)
  final int reminderTotal;
  final int reminderDone;
  final int reminderPending;
  final DateTime? reminderFirstDate;
  final DateTime? reminderLastDate;
  // 'none' | 'ongoing' | 'done'
  final String treatmentStatus;

  // ✅ ถ้ามีการบันทึกคำแนะนำที่ resolve แล้วลงใน diagnosis_history ให้ดึงมาใช้ก่อน
  final String adviceText;

  final String diseaseTh;
  final String diseaseEn;
  final String treeName;
  final String levelCode;

  DiagnosisHistoryItem({
    required this.id,
    required this.treeId,
    required this.diseaseId,
    required this.riskLevelId,
    required this.totalScore,
    required this.imageUrl,
    required this.diagnosedAt,
    required this.adviceText,
    required this.diseaseTh,
    required this.diseaseEn,
    required this.treeName,
    required this.levelCode,
    required this.reminderTotal,
    required this.reminderDone,
    required this.reminderPending,
    this.reminderFirstDate,
    this.reminderLastDate,
    required this.treatmentStatus,
  });

  factory DiagnosisHistoryItem.fromMap(Map<String, dynamic> m) {
    final diseaseTh = _pickText(m, [
      'disease_th',
      'disease_name_th',
      'disease_th_name',
      'disease_thai',
      'disease_thai_name',
      'name_th',
      'thai_name',
      'diseaseNameTh',
    ]);

    final diseaseEn = _pickText(m, [
      'disease_en',
      'disease_name_en',
      'disease_name',
      'disease_en_name',
      'name_en',
      'english_name',
      'diseaseNameEn',
    ]);

    final treeName = _pickText(m, [
      'tree_name',
      'orange_tree_name',
      'name',
    ]);

    final levelCode = _pickText(m, [
      'level_code',
      'risk_level_code',
      'risk_level_name',
      'risk_level',
      'severity',
    ]);

    final diagnosedAt = _toDate(m['diagnosed_at'] ?? m['created_at'] ?? m['createdAt']);

    final adviceText = _pickText(m, [
      'advice_text',
      'advice',
      'treatment_advice',
      'treatment_text',
      'recommendation',
      'resolved_advice_text',
      'adviceText',
    ]);

    return DiagnosisHistoryItem(
      id: _toInt(m['diagnosis_history_id'] ?? m['id'] ?? m['history_id']),
      treeId: _toInt(m['tree_id'] ?? m['treeId'] ?? m['orange_tree_id'] ?? m['orangeTreeId']),
      diseaseId: _toInt(m['disease_id'] ?? m['diseaseId'] ?? m['disease_ids'] ?? m['diseaseID']),
      riskLevelId: (() {
        final rid = _s(m['risk_level_id'] ??
            m['riskLevelId'] ??
            m['level_id'] ??
            m['risk_levelID'] ??
            m['risk_level']);
        final n = int.tryParse(rid);
        return (n == null || n <= 0) ? null : n;
      })(),
      totalScore: _toInt(m['total_score'] ?? m['score'] ?? m['totalScore']),
      imageUrl: _pickText(m, ['image_url', 'image', 'image_path', 'imagePath']),
      diagnosedAt: diagnosedAt,
      adviceText: adviceText,
      diseaseTh: diseaseTh,
      diseaseEn: diseaseEn,
      treeName: treeName,
      levelCode: levelCode,
      reminderTotal: _toInt(m['reminder_total'] ?? m['reminderTotal']),
      reminderDone: _toInt(m['reminder_done'] ?? m['reminderDone']),
      reminderPending: _toInt(m['reminder_pending'] ?? m['reminderPending']),
      reminderFirstDate: _toDate(m['reminder_first_date'] ?? m['reminderFirstDate'] ?? m['first_date']),
      reminderLastDate: _toDate(m['reminder_last_date'] ?? m['reminderLastDate'] ?? m['last_date']),
      treatmentStatus: _pickText(m, ['treatment_status', 'treatmentStatus']).isNotEmpty
          ? _pickText(m, ['treatment_status', 'treatmentStatus'])
          : 'none',
    );
  }

  String get diseaseLabel {
    if (diseaseEn.isNotEmpty && diseaseTh.isNotEmpty) return '$diseaseEn ($diseaseTh)';
    if (diseaseTh.isNotEmpty) return diseaseTh;
    if (diseaseEn.isNotEmpty) return diseaseEn;
    return '-';
  }

  String get severityLabel => _severityFromLevelCode(levelCode);
}

enum _TreeHistoryView { list, detail }

class TreeHistoryPage extends StatefulWidget {
  final CitrusTreeRecord record;

  const TreeHistoryPage({super.key, required this.record});

  @override
  State<TreeHistoryPage> createState() => _TreeHistoryPageState();
}

class _TreeHistoryPageState extends State<TreeHistoryPage> {
  late CitrusTreeRecord _record;

  // ✅ เข้าแล้วแสดง “รายการประวัติการสแกน” ก่อน
  _TreeHistoryView _view = _TreeHistoryView.list;
  DiagnosisHistoryItem? _selected;

  bool _loading = false;
  String _error = '';

  // ✅ ใช้ API base จาก prefs (เหมือนหน้าอื่น ๆ) เพื่อไม่ให้ประวัติรายต้น
  // หลุดไปคนละโดเมนตอนเปลี่ยน ngrok/host
  String _apiBaseUrl = API_BASE;
  String get _backendOrigin => _backendOriginFromApiBase(_apiBaseUrl);
  bool _bootstrapping = true;

  // ✅ tree_id ที่ resolve จาก server (กัน not_owner เมื่อ record ไม่มี id จริง)
  int _resolvedTreeId = 0;
  bool _retriedAfterResolve = false;

  List<DiagnosisHistoryItem> _hist = [];

  bool _loadingDiseaseInfo = false;
  String _description = '-';
  String _causes = '-';
  String _symptom = '-';

  bool _loadingAdvice = false;
  String _adviceText = '-';
  final Map<int, String> _adviceCache = {};

  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefBase = (prefs.getString('api_base_url') ?? '').trim();
      if (prefBase.isNotEmpty) {
        _apiBaseUrl = prefBase;
      }
    } catch (_) {
      // ignore
    }

    if (!mounted) return;
    setState(() {
      _bootstrapping = false;
    });

    await _loadAll();
  }

  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ??
        prefs.getString('access_token') ??
        prefs.getString('auth_token');
  }

  String _bearerValue(String token) {
  final t = token.trim();
  if (t.toLowerCase().startsWith('bearer ')) return t;
  return 'Bearer $t';
}

Map<String, String> _headers(String? token) => {
      'Accept': 'application/json',
      if (token != null && token.trim().isNotEmpty) 'Authorization': _bearerValue(token),
    };

  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic>) {
      if (decoded['data'] is List) return decoded['data'];
      if (decoded['records'] is List) return decoded['records'];
      if (decoded['items'] is List) return decoded['items'];
      if (decoded['result'] is List) return decoded['result'];
    }
    return [];
  }

  // ✅ หา tree_id ให้เจอ + fallback จากชื่อ "ต้นที่ 5"
  int _getTreeIdFromRecord() {
    final dyn = _record as dynamic;

    int _tryParse(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      return int.tryParse(v.toString().trim()) ?? 0;
    }

    final getters = <dynamic Function()>[
      () => dyn.treeId,
      () => dyn.tree_id,
      () => dyn.treeID,
      () => dyn.orange_tree_id,
      () => dyn.orangeTreeId,
      () => dyn.id,
      () => dyn.treeNo,
      () => dyn.tree_no,
      () => dyn.treeNumber,
      () => dyn.tree_number,
      () => dyn.number,
      () => dyn.index,
    ];

    for (final g in getters) {
      try {
        final id = _tryParse(g());
        if (id > 0) return id;
      } catch (_) {}
    }

    try {
      final m = dyn.toMap();
      if (m is Map) {
        final keys = [
          'tree_id',
          'treeId',
          'treeID',
          'orange_tree_id',
          'orangeTreeId',
          'id',
          'tree_no',
          'treeNo',
          'tree_number',
          'treeNumber',
          'number',
          'index',
        ];
        for (final k in keys) {
          final id = _tryParse(m[k]);
          if (id > 0) return id;
        }
      }
    } catch (_) {}

    // fallback: "ต้นที่ 5" -> 5
    try {
      final name = (dyn.name ?? dyn.treeName ?? '').toString();
      final match = RegExp(r'\d+').firstMatch(name);
      final id = match == null ? 0 : int.tryParse(match.group(0) ?? '') ?? 0;
      if (id > 0) return id;
    } catch (_) {}

    return 0;
  }
String _getRecordName() {
  final dyn = _record as dynamic;
  try {
    final n = (dyn.name ?? dyn.treeName ?? dyn.tree_name ?? '').toString().trim();
    return n;
  } catch (_) {
    return '';
  }
}

int? _getRecordTreeNo() {
  final dyn = _record as dynamic;
  int _tryParse(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString().trim()) ?? 0;
  }

  // 1) จาก field ที่เป็นลำดับต้น (ถ้ามี)
  final getters = <dynamic Function()>[
    () => dyn.treeNo,
    () => dyn.tree_no,
    () => dyn.treeNumber,
    () => dyn.tree_number,
    () => dyn.number,
    () => dyn.index,
  ];
  for (final g in getters) {
    try {
      final no = _tryParse(g());
      if (no > 0) return no;
    } catch (_) {}
  }

  // 2) จากชื่อ "ต้นที่ N"
  final name = _getRecordName();
  final m = RegExp(r'ต้น\s*ที่\s*(\d+)').firstMatch(name);
  if (m != null) {
    final no = int.tryParse(m.group(1) ?? '');
    if (no != null && no > 0) return no;
  }
  return null;
}

bool _looksLikeAutoTreeLabel(String name) {
  final s = name.trim();
  if (s.isEmpty) return false;
  if (RegExp(r'^ต้น\s*ที่\s*\d+$').hasMatch(s)) return true;
  if (RegExp(r'^(ต้น\s*)?\d+$').hasMatch(s)) return true; // ชื่อเป็นตัวเลขล้วน ๆ
  return false;
}

Future<int> _resolveTreeIdFromServer() async {
  final token = await _readToken();

  // ✅ ดึงรายการต้นส้มของผู้ใช้จาก server แล้ว map เป็น tree_id จริง
  final url = Uri.parse(_joinApi(_apiBaseUrl, '/orange_trees/read_orange_trees.php'));
  final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));

  dynamic decoded;
  try {
    decoded = jsonDecode(res.body);
  } catch (_) {
    return 0;
  }

  final err = _extractErr(decoded);
  if (err.isNotEmpty && !_isSuccess(decoded)) {
    // ถ้า token มีปัญหา ให้ปล่อยให้ error เดิมแสดง
    return 0;
  }

  final list = _extractList(decoded);
  final trees = list
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  if (trees.isEmpty) return 0;

  int _treeIdOf(Map<String, dynamic> m) =>
      _toInt(m['tree_id'] ?? m['id'] ?? m['orange_tree_id'] ?? m['treeId'] ?? m['treeID']);

  String _treeNameOf(Map<String, dynamic> m) =>
      _pickText(m, ['tree_name', 'name', 'orange_tree_name', 'treeName']);

  // 1) ถ้าชื่อเป็นชื่อจริง (ไม่ใช่ "ต้นที่ N") ให้ match ตามชื่อก่อน
  final recordName = _getRecordName();
  if (recordName.isNotEmpty && !_looksLikeAutoTreeLabel(recordName)) {
    for (final t in trees) {
      final tn = _treeNameOf(t).trim();
      if (tn.isNotEmpty && tn == recordName) {
        final id = _treeIdOf(t);
        if (id > 0) return id;
      }
    }
  }

  // 2) ถ้าเป็น "ต้นที่ N" ให้ map ตามลำดับใน list (เรียง tree_id)
  final no = _getRecordTreeNo();
  final sorted = [...trees]..sort((a, b) => _treeIdOf(a).compareTo(_treeIdOf(b)));
  if (no != null && no > 0 && no <= sorted.length) {
    final id = _treeIdOf(sorted[no - 1]);
    if (id > 0) return id;
  }

  // 3) ถ้า record มี id แล้ว และพบใน list ของผู้ใช้ ให้ใช้ id นั้น
  final hinted = _getTreeIdFromRecord();
  if (hinted > 0) {
    for (final t in trees) {
      if (_treeIdOf(t) == hinted) return hinted;
    }
  }

  // 4) fallback สุดท้าย: ใช้ต้นแรก
  final firstId = _treeIdOf(sorted.first);
  return firstId > 0 ? firstId : 0;
}


  bool _isHttpUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  ImageProvider<Object>? _imgProvider(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.trim().isEmpty) return null;
    final p = pathOrUrl.trim();

    if (_isHttpUrl(p)) return NetworkImage(p);

    if (!p.contains('://')) {
      final normalized = p.startsWith('/') ? p.substring(1) : p;
      return NetworkImage('$_backendOrigin/$normalized');
    }

    final f = File(p);
    if (f.existsSync()) return FileImage(f);
    return null;
  }

  Future<void> _loadAll() async {
    await _loadDiagnosisHistory();

    if (!mounted) return;
    if (_hist.isNotEmpty) _selected ??= _hist.first;

    if (_view == _TreeHistoryView.detail && _selected != null) {
      await _loadDiseaseInfoByDiseaseId(_selected!.diseaseId);
      await _loadAdviceByRiskLevelId(_selected!.riskLevelId);
    } else {
      if (_hist.isEmpty && mounted) {
        setState(() {
          _description = '-';
          _causes = '-';
          _symptom = '-';
          _adviceText = '-';
        });
      }
    }
  }

  void _openDetail(DiagnosisHistoryItem it) {
    setState(() {
      _selected = it;
      _view = _TreeHistoryView.detail;

      _description = '-';
      _causes = '-';
      _symptom = '-';
      _loadingAdvice = false;
      // ✅ ถ้ามีคำแนะนำที่บันทึกไว้กับประวัติแล้ว ให้โชว์อันนี้ก่อน
      final savedAdvice = it.adviceText.trim();
      _adviceText = savedAdvice.isNotEmpty ? savedAdvice : '-';
    });

    _loadDiseaseInfoByDiseaseId(it.diseaseId);
    // ถ้ายังไม่มีคำแนะนำที่บันทึกไว้ ค่อยไปดึง template จาก treatments ตาม risk_level_id
    if (it.adviceText.trim().isEmpty) {
      _loadAdviceByRiskLevelId(it.riskLevelId);
    }
  }

  void _backToList() {
    setState(() => _view = _TreeHistoryView.list);
  }

  Future<void> _loadDiagnosisHistory() async {
    setState(() {
      _loading = true;
      _error = '';
      _hist = [];
    });

    try {
      final hintedId = _getTreeIdFromRecord();
      final treeId = _resolvedTreeId > 0 ? _resolvedTreeId : hintedId;
      if (treeId <= 0) throw Exception('ไม่พบ tree_id');

      final token = await _readToken();
      final url = Uri.parse(_joinApi(_apiBaseUrl, '/diagnosis_history/read_diagnosis_history.php'))
          .replace(queryParameters: {
        'tree_id': treeId.toString(),
        // ✅ เผื่อ backend ใช้ชื่อคีย์นี้
        'orange_tree_id': treeId.toString(),
        if (_getRecordTreeNo() != null) 'tree_no': _getRecordTreeNo()!.toString(),
        'summary': '1', // ✅ สรุปโรคล่าสุดต่อโรค (ต่อ 1 ต้น)

        'limit': '100',
      });

      final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));

      dynamic decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        throw Exception('Response ไม่ใช่ JSON (HTTP ${res.statusCode})');
      }

      if (res.statusCode == 401) {
        throw Exception('token หมดอายุ/ไม่ถูกต้อง (HTTP 401) กรุณาเข้าสู่ระบบใหม่');
      }

      final err = _extractErr(decoded);
      if (err.isNotEmpty && !_isSuccess(decoded)) throw Exception(err);
      if (!_isSuccess(decoded) && err.isNotEmpty) throw Exception(err);

      final list = _extractList(decoded);
      final items = list
          .whereType<Map>()
          .map((e) => DiagnosisHistoryItem.fromMap(Map<String, dynamic>.from(e)))
          .where((x) => x.id > 0)
          .toList();

      items.sort((a, b) {
        final ad = a.diagnosedAt;
        final bd = b.diagnosedAt;
        if (ad != null && bd != null) return bd.compareTo(ad);
        return b.id.compareTo(a.id);
      });

      if (!mounted) return;
      setState(() {
        _hist = items;
        _loading = false;
      });
} catch (e) {
  // ✅ ถ้า backend ตอบ not_owner มักเกิดจาก record ไม่มี tree_id จริง (ได้แค่ "ต้นที่ 1")
  // ให้ไป resolve tree_id จาก server แล้ว retry 1 ครั้ง
  final msg = e.toString();
  if (!_retriedAfterResolve && msg.contains('not_owner')) {
    _retriedAfterResolve = true;
    try {
      final resolved = await _resolveTreeIdFromServer();
      if (resolved > 0 && resolved != _resolvedTreeId) {
        _resolvedTreeId = resolved;
        await _loadDiagnosisHistory();
        return;
      }
    } catch (_) {
      // ignore แล้วค่อยแสดง error เดิม
    }
  }

  if (!mounted) return;
  setState(() {
    _error = 'โหลดประวัติไม่สำเร็จ: $e';
    _loading = false;
  });
}
  }

  Future<void> _loadDiseaseInfoByDiseaseId(int diseaseId) async {
    if (diseaseId <= 0) return;
    setState(() => _loadingDiseaseInfo = true);

    try {
      final token = await _readToken();
      final url = Uri.parse(_joinApi(_apiBaseUrl, '/diseases/read_diseases.php'));

      final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));

      final decoded = jsonDecode(res.body);
      final err = _extractErr(decoded);
      if (err.isNotEmpty && !_isSuccess(decoded)) throw Exception(err);

      final data = (decoded is Map) ? decoded['data'] : null;
      if (data is! List) throw Exception('invalid_diseases_data');

      Map<String, dynamic>? found;
      for (final item in data) {
        if (item is! Map) continue;
        final did = _toInt(item['disease_id'] ?? item['id']);
        if (did == diseaseId) {
          found = Map<String, dynamic>.from(item);
          break;
        }
      }

      if (!mounted) return;

      if (found != null) {
        setState(() {
          final desc = _pickText(found!, [
            'description',
            'disease_desc',
            'desc',
            'detail',
            'disease_description',
          ]);
          final causes = _pickText(found!, ['causes', 'cause', 'disease_causes', 'disease_cause']);
          final sym = _pickText(found!, [
            'symptom',
            'symptoms',
            'disease_symptom',
            'disease_symptoms',
            'signs',
            'disease_signs',
          ]);
          _description = desc.isEmpty ? '-' : desc;
          _causes = causes.isEmpty ? '-' : causes;
          _symptom = sym.isEmpty ? '-' : sym;
        });
      } else {
        setState(() {
          _description = '-';
          _causes = '-';
          _symptom = '-';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _description = '-';
        _causes = '-';
        _symptom = '-';
      });
    } finally {
      if (mounted) setState(() => _loadingDiseaseInfo = false);
    }
  }

  Future<void> _loadAdviceByRiskLevelId(int? riskLevelId) async {
    if (riskLevelId == null || riskLevelId <= 0) {
      setState(() => _adviceText = '-');
      return;
    }

    if (_adviceCache.containsKey(riskLevelId)) {
      setState(() => _adviceText = _adviceCache[riskLevelId] ?? '-');
      return;
    }

    setState(() => _loadingAdvice = true);

    try {
      final token = await _readToken();

      final url = Uri.parse(_joinApi(_apiBaseUrl, '/treatments/read_treatments.php'))
          .replace(queryParameters: {'risk_level_id': riskLevelId.toString()});

      final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));

      final decoded = jsonDecode(res.body);
      final err = _extractErr(decoded);
      if (err.isNotEmpty && !_isSuccess(decoded)) throw Exception(err);

      final list = _extractList(decoded);
      String text = '-';
      if (list.isNotEmpty && list.first is Map) {
        text = _s((list.first as Map)['advice_text'] ??
            (list.first as Map)['advice'] ??
            (list.first as Map)['treatment'] ??
            (list.first as Map)['treatment_text']);
      }
      if (text.isEmpty) text = '-';

      _adviceCache[riskLevelId] = text;

      if (!mounted) return;
      setState(() {
        _adviceText = text;
        _loadingAdvice = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adviceText = '-';
        _loadingAdvice = false;
      });
    }
  }

  // ✅ การ์ดรายการประวัติการสแกน (เหมือนภาพ)
  
  Widget _statusText(DiagnosisHistoryItem it) {
    final total = it.reminderTotal;

    // ✅ ถ้ายังไม่มีแผนในปฏิทิน (ไม่มี reminder)
    if (total <= 0) {
      return const Padding(
        padding: EdgeInsets.only(right: 2),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            'ยังไม่รับแผน',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black38,
            ),
          ),
        ),
      );
    }

    // ✅ ทำครบตามแผน (reminderDone >= reminderTotal) → “รักษาเสร็จแล้ว”
    // ✅ ถ้ายังไม่ครบ → “รักษายังไม่เสร็จ”
    final done = (it.treatmentStatus == 'done') || (it.reminderDone >= total);

    final Color fg = done ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C);

    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          done ? 'รักษาเสร็จแล้ว' : 'รักษายังไม่เสร็จ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
      ),
    );
  }


Widget _historyCard(DiagnosisHistoryItem it) {
    final date = it.diagnosedAt != null ? _fmtDate(it.diagnosedAt!) : '-';

    return InkWell(
      onTap: () => _openDetail(it),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2EC),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.spa, color: kPrimaryGreen, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    it.diseaseLabel,
                    // ✅ ใช้ TextTheme ของระบบ เพื่อให้ฟอน/สไตล์เหมือนส่วนอื่นของแอป
                    style: (Theme.of(context).textTheme.titleMedium ?? const TextStyle())
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  // ✅ แสดงวันที่วินิจฉัยใต้ชื่อโรค
                  Text(
                    'วันที่วินิจฉัย: $date',
                    style: (Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 13))
                        .copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
            _statusText(it),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleName = (() {
      try {
        return (_record as dynamic).name as String;
      } catch (_) {
        return 'ต้นส้ม';
      }
    })();

    return WillPopScope(
      onWillPop: () async {
        if (_view == _TreeHistoryView.detail) {
          _backToList();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kPrimaryGreen,
          foregroundColor: Colors.white,
          title: Text('ประวัติต้นส้ม: $titleName'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_view == _TreeHistoryView.detail) {
                _backToList();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _bootstrapping
            ? const Center(child: CircularProgressIndicator())
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error, textAlign: TextAlign.center),
                        ),
                      )
                    : (_view == _TreeHistoryView.list ? _buildListView() : _buildDetailView()),
      ),
    );
  }

  // ✅ หน้าแรก: แสดงรายการประวัติการสแกนก่อน
  Widget _buildListView() {
    if (_hist.isEmpty) {
      return const Center(child: Text('ยังไม่มีประวัติการสแกน'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        const Text('ประวัติการสแกน', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        ..._hist.map(_historyCard),
      ],
    );
  }

  // ✅ หน้ารายละเอียด: ลบ "ประวัติการสแกน" ออกจากหน้ารายละเอียดแล้ว
  Widget _buildDetailView() {
    final selected = _selected ?? (_hist.isNotEmpty ? _hist.first : null);
    if (selected == null) {
      return const Center(child: Text('ยังไม่มีประวัติในฐานข้อมูล'));
    }

    final showDisease = selected.diseaseLabel;
    final showDate = selected.diagnosedAt != null ? _fmtDate(selected.diagnosedAt!) : '-';
    final showSeverity = selected.severityLabel;

    final img = selected.imageUrl.trim().isNotEmpty
        ? _imgProvider(selected.imageUrl)
        : (_record.lastScanImagePath != null ? _imgProvider(_record.lastScanImagePath) : null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        // รูปล่าสุด/ของรายการที่เลือก
        if (img != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image(
                image: img,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: kCardBg,
                  alignment: Alignment.center,
                  child: const Text('ไม่สามารถแสดงรูปได้'),
                ),
              ),
            ),
          )
        else
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: kCardBg,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: const Text('ยังไม่มีรูปการสแกน'),
          ),

        const SizedBox(height: 14),

        // ข้อมูลโรค + รายละเอียด (เดิม)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ชื่อโรค', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('โรค: $showDisease'),

              const SizedBox(height: 10),
              Text('คำอธิบายโรค: $_description'),
              const SizedBox(height: 6),
              Text('สาเหตุ: $_causes'),
              const SizedBox(height: 6),
              Text('อาการ: $_symptom'),

              const SizedBox(height: 10),
              Text('วันที่วินิจฉัย: $showDate'),
              const SizedBox(height: 4),
              Text('ระดับความรุนแรง: $showSeverity'),

              if (_loadingDiseaseInfo) ...[
                const SizedBox(height: 10),
                const Text(
                  'กำลังโหลดข้อมูลโรคจากฐานข้อมูล...',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // คำแนะนำการรักษา (เดิม)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('คำแนะนำการรักษา', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (_loadingAdvice)
                const Text('กำลังโหลดคำแนะนำ...', style: TextStyle(color: Colors.black54))
              else
                Text(_adviceText.trim().isEmpty ? '-' : _adviceText),
            ],
          ),
        ),

        const SizedBox(height: 10),
      ],
    );
  }
}
