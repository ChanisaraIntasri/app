import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/citrus_tree_record.dart';

const kPrimaryGreen = Color(0xFF005E33);
const kBg = Color.fromARGB(255, 255, 255, 255);
// ปรับสีพื้นหลัง Card ให้อ่อนลง (เทาอ่อน)
final kCardBg = Colors.grey.shade50;

// ✅ ใช้เหมือนไฟล์อื่น: ให้ส่งตอน run/build ด้วย --dart-define=API_BASE=...
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api',
);

String _joinApi(String base, String path) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final p = path.startsWith('/') ? path : '/$path';
  return '$b$p';
}

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

  final int reminderTotal;
  final int reminderDone;
  final int reminderPending;
  final DateTime? reminderFirstDate;
  final DateTime? reminderLastDate;
  final String treatmentStatus;

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
      'disease_th', 'disease_name_th', 'disease_th_name', 'disease_thai',
      'disease_thai_name', 'name_th', 'thai_name', 'diseaseNameTh',
    ]);

    final diseaseEn = _pickText(m, [
      'disease_en', 'disease_name_en', 'disease_name', 'disease_en_name',
      'name_en', 'english_name', 'diseaseNameEn',
    ]);

    final treeName = _pickText(m, ['tree_name', 'orange_tree_name', 'name']);

    final levelCode = _pickText(m, ['level_code', 'risk_level_code', 'risk_level_name', 'risk_level', 'severity']);

    final diagnosedAt = _toDate(m['diagnosed_at'] ?? m['created_at'] ?? m['createdAt']);

    final adviceText = _pickText(m, [
      'advice_text', 'advice', 'treatment_advice', 'treatment_text',
      'recommendation', 'resolved_advice_text', 'adviceText',
    ]);

    return DiagnosisHistoryItem(
      id: _toInt(m['diagnosis_history_id'] ?? m['id'] ?? m['history_id']),
      treeId: _toInt(m['tree_id'] ?? m['treeId'] ?? m['orange_tree_id'] ?? m['orangeTreeId']),
      diseaseId: _toInt(m['disease_id'] ?? m['diseaseId'] ?? m['disease_ids'] ?? m['diseaseID']),
      riskLevelId: (() {
        final rid = _s(m['risk_level_id'] ?? m['riskLevelId'] ?? m['level_id'] ?? m['risk_levelID'] ?? m['risk_level']);
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

  _TreeHistoryView _view = _TreeHistoryView.list;
  DiagnosisHistoryItem? _selected;

  bool _loading = false;
  String _error = '';

  String _apiBaseUrl = API_BASE;
  String get _backendOrigin => _backendOriginFromApiBase(_apiBaseUrl);
  bool _bootstrapping = true;

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
    } catch (_) {}

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

  int _getTreeIdFromRecord() {
    final dyn = _record as dynamic;
    int _tryParse(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      return int.tryParse(v.toString().trim()) ?? 0;
    }
    final getters = <dynamic Function()>[
      () => dyn.treeId, () => dyn.tree_id, () => dyn.treeID,
      () => dyn.orange_tree_id, () => dyn.orangeTreeId, () => dyn.id,
      () => dyn.treeNo, () => dyn.tree_no, () => dyn.treeNumber,
      () => dyn.tree_number, () => dyn.number, () => dyn.index,
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
        final keys = ['tree_id', 'treeId', 'id', 'orange_tree_id'];
        for (final k in keys) {
          final id = _tryParse(m[k]);
          if (id > 0) return id;
        }
      }
    } catch (_) {}
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
      return (dyn.name ?? dyn.treeName ?? dyn.tree_name ?? '').toString().trim();
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
    final getters = <dynamic Function()>[
      () => dyn.treeNo, () => dyn.tree_no, () => dyn.treeNumber,
    ];
    for (final g in getters) {
      try {
        final no = _tryParse(g());
        if (no > 0) return no;
      } catch (_) {}
    }
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
    if (RegExp(r'^(ต้น\s*)?\d+$').hasMatch(s)) return true;
    return false;
  }

  Future<int> _resolveTreeIdFromServer() async {
    final token = await _readToken();
    final url = Uri.parse(_joinApi(_apiBaseUrl, '/orange_trees/read_orange_trees.php'));
    final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));
    dynamic decoded;
    try { decoded = jsonDecode(res.body); } catch (_) { return 0; }
    
    final err = _extractErr(decoded);
    if (err.isNotEmpty && !_isSuccess(decoded)) return 0;

    final list = _extractList(decoded);
    final trees = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    if (trees.isEmpty) return 0;

    int _treeIdOf(Map<String, dynamic> m) => _toInt(m['tree_id'] ?? m['id'] ?? m['orange_tree_id']);
    String _treeNameOf(Map<String, dynamic> m) => _pickText(m, ['tree_name', 'name']);

    final recordName = _getRecordName();
    if (recordName.isNotEmpty && !_looksLikeAutoTreeLabel(recordName)) {
      for (final t in trees) {
        if (_treeNameOf(t).trim() == recordName) {
           final id = _treeIdOf(t);
           if (id > 0) return id;
        }
      }
    }

    final no = _getRecordTreeNo();
    final sorted = [...trees]..sort((a, b) => _treeIdOf(a).compareTo(_treeIdOf(b)));
    if (no != null && no > 0 && no <= sorted.length) {
      final id = _treeIdOf(sorted[no - 1]);
      if (id > 0) return id;
    }

    final hinted = _getTreeIdFromRecord();
    if (hinted > 0) {
      for (final t in trees) {
        if (_treeIdOf(t) == hinted) return hinted;
      }
    }
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
          _description = '-'; _causes = '-'; _symptom = '-'; _adviceText = '-';
        });
      }
    }
  }

  void _openDetail(DiagnosisHistoryItem it) {
    setState(() {
      _selected = it;
      _view = _TreeHistoryView.detail;
      _description = '-'; _causes = '-'; _symptom = '-'; _loadingAdvice = false;
      final savedAdvice = it.adviceText.trim();
      _adviceText = savedAdvice.isNotEmpty ? savedAdvice : '-';
    });
    _loadDiseaseInfoByDiseaseId(it.diseaseId);
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
        'orange_tree_id': treeId.toString(),
        if (_getRecordTreeNo() != null) 'tree_no': _getRecordTreeNo()!.toString(),
        'summary': '1',
        'limit': '100',
      });

      final res = await http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 12));
      dynamic decoded;
      try { decoded = jsonDecode(res.body); } catch (_) { throw Exception('Response Error'); }
      if (res.statusCode == 401) throw Exception('Token expired');

      final err = _extractErr(decoded);
      if (err.isNotEmpty && !_isSuccess(decoded)) throw Exception(err);

      final list = _extractList(decoded);
      final items = list.whereType<Map>()
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
        } catch (_) {}
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
      final data = (decoded is Map) ? decoded['data'] : null;
      if (data is! List) return;

      Map<String, dynamic>? found;
      for (final item in data) {
        if (item is! Map) continue;
        if (_toInt(item['disease_id'] ?? item['id']) == diseaseId) {
          found = Map<String, dynamic>.from(item);
          break;
        }
      }
      if (!mounted) return;
      if (found != null) {
        setState(() {
          _description = _pickText(found!, ['description', 'detail', 'disease_desc'], fallback: '-');
          _causes = _pickText(found!, ['causes', 'cause', 'disease_causes'], fallback: '-');
          _symptom = _pickText(found!, ['symptom', 'symptoms', 'disease_symptom'], fallback: '-');
        });
      }
    } catch (_) {
      // ignore
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
      final list = _extractList(decoded);
      String text = '-';
      if (list.isNotEmpty && list.first is Map) {
        text = _s((list.first as Map)['advice_text'] ?? (list.first as Map)['treatment']);
      }
      if (text.isEmpty) text = '-';
      _adviceCache[riskLevelId] = text;
      if (!mounted) return;
      setState(() {
        _adviceText = text;
        _loadingAdvice = false;
      });
    } catch (_) {
      if (mounted) setState(() => _adviceText = '-');
    } finally {
      if (mounted) setState(() => _loadingAdvice = false);
    }
  }

  Widget _statusText(DiagnosisHistoryItem it) {
    final total = it.reminderTotal;
    if (total <= 0) {
      return const Padding(
        padding: EdgeInsets.only(right: 2),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text('ยังไม่รับแผน',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black38)),
        ),
      );
    }
    final done = (it.treatmentStatus == 'done') || (it.reminderDone >= total);
    final Color fg = done ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(done ? 'รักษาเสร็จแล้ว' : 'รักษายังไม่เสร็จ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
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
              width: 54, height: 54,
              decoration: BoxDecoration(color: const Color(0xFFEAF2EC), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.spa, color: kPrimaryGreen, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.diseaseLabel, style: (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('วันที่วินิจฉัย: $date', style: (Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 13)).copyWith(color: Colors.black54)),
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
                    ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error, textAlign: TextAlign.center)))
                    : (_view == _TreeHistoryView.list ? _buildListView() : _buildDetailView()),
      ),
    );
  }

  Widget _buildListView() {
    if (_hist.isEmpty) return const Center(child: Text('ยังไม่มีประวัติการสแกน'));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        const Text('ประวัติการสแกน', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ..._hist.map(_historyCard),
      ],
    );
  }

  // ==========================================
  // ✅ Widget เสริมสำหรับสร้าง Block แบบ Expandable (กดขยาย/ยุบได้)
  // ==========================================
  Widget _buildExpandableBlock({
    required String title,
    required IconData icon,
    required List<Widget> children, // รับเป็น List<Widget> เพื่อใส่เนื้อหาข้างใน
    Color? headerColor,
    bool initiallyExpanded = false, // ค่าเริ่มต้นว่าจะให้ขยายอยู่แล้วหรือไม่
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      // ตัด Padding ออกเพื่อให้ ExpansionTile จัดการเอง
      decoration: BoxDecoration(
        color: kCardBg, // ใช้สีเทาอ่อนตาม Theme
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Theme(
        // ซ่อนเส้นขีดกั้น (Divider) ของ ExpansionTile
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (headerColor ?? kPrimaryGreen).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: headerColor ?? kPrimaryGreen, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          children: children,
        ),
      ),
    );
  }

  // ==========================================
  // ✅ ส่วนแสดงผล Detail View ที่ปรับปรุงใหม่ (ใช้ Expandable Block)
  // ==========================================
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      children: [
        // --- ส่วนรูปภาพ (แก้ไขใหม่: ให้เหมือน Page 11 คือ 16:9 และ BoxFit.cover) ---
        if (img != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 16 / 9, // ✅ ใช้สัดส่วนมาตรฐาน
              child: Image(
                image: img,
                fit: BoxFit.cover, // ✅ เต็มพื้นที่กรอบอย่างสวยงาม (เหมือน Page 11)
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey[200],
                  alignment: Alignment.center,
                  child: const Text('ไม่สามารถแสดงรูปได้'),
                ),
              ),
            ),
          )
        else
          Container(
            height: 150,
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(18)),
            alignment: Alignment.center,
            child: const Text('ยังไม่มีรูปการสแกน'),
          ),

        const SizedBox(height: 20),

        // --- ชื่อโรค (หัวข้อใหญ่) ---
        Text(
          'ชื่อโรค : $showDisease',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // =========================================================
        // 1. บล็อกรายละเอียดของโรค (รวมผลสแกน + คำอธิบาย + สาเหตุ + อาการ)
        // =========================================================
        _buildExpandableBlock(
          title: 'รายละเอียดของโรค',
          icon: Icons.analytics_outlined,
          initiallyExpanded: false, // ✅ ยุบไว้
          children: [
             Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ส่วนผลการวินิจฉัยย่อย
                _buildInfoRow('วันที่วินิจฉัย', showDate),
                const SizedBox(height: 8),
                _buildInfoRow('ระดับความรุนแรง', showSeverity, 
                  valueColor: showSeverity.contains('มาก') ? Colors.red : Colors.orange),
                
                const Divider(height: 24),

                // ส่วนรายละเอียดเนื้อหา (คำอธิบาย, สาเหตุ, อาการ)
                const Text('คำอธิบายโรค:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_description, style: const TextStyle(color: Colors.black87, height: 1.4)),
                
                const SizedBox(height: 12),
                const Text('สาเหตุ:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_causes, style: const TextStyle(color: Colors.black87, height: 1.4)),

                const SizedBox(height: 12),
                const Text('อาการ:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_symptom, style: const TextStyle(color: Colors.black87, height: 1.4)),
              ],
            ),
          ],
        ),

        // =========================================================
        // 2. บล็อกคำแนะนำการรักษา
        // =========================================================
        _buildExpandableBlock(
          title: 'คำแนะนำการรักษา',
          icon: Icons.medical_services_outlined,
          initiallyExpanded: false, // ✅ ยุบไว้
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _loadingAdvice
                  ? const Text('กำลังโหลดคำแนะนำ...', style: TextStyle(color: Colors.black54))
                  : Text(
                      _adviceText.trim().isEmpty ? '-' : _adviceText,
                      style: const TextStyle(height: 1.5, fontSize: 14),
                    ),
            ),
          ],
        ),

        // =========================================================
        // 3. บล็อกประวัติการใช้ยา
        // =========================================================
        _buildExpandableBlock(
          title: 'ประวัติการใช้ยา',
          icon: Icons.medication_liquid_outlined,
          headerColor: Colors.teal,
          initiallyExpanded: false, // ✅ ยุบไว้
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                     'รายการยาที่แนะนำหรือเคยบันทึกไว้:',
                     style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black54),
                   ),
                   SizedBox(height: 8),
                   // ใส่ Placeholder ไว้
                   Text(
                     '- ยังไม่มีข้อมูลการบันทึกยาเฉพาะเจาะจง',
                     style: TextStyle(color: Colors.black87),
                   ),
                   SizedBox(height: 4),
                   Text(
                     'หมายเหตุ: โปรดอ้างอิงจากคำแนะนำการรักษาด้านบนเป็นหลัก',
                     style: TextStyle(color: Colors.grey, fontSize: 12),
                   ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor ?? Colors.black87)),
      ],
    );
  }
}