import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// ✅ API base URL
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue:
      'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api',
);

/// ✅ Theme constants
const Color kPrimaryGreen = Color(0xFF0B6B3A);
const Color kCardBg = Color(0xFFF6F6F6);
const Color kChemicalBlue = Color(0xFF0056b3);

class TreatmentAdvicePage extends StatefulWidget {
  final String treeId;
  final String diseaseId;
  final String riskLevelId;
  final int? diagnosisHistoryId;
  final int? treatmentId;
  final List<String> adviceList;
  final String? diseaseName;
  final String? riskLevelName;
  final int? totalScore;
  final String? note;
  final int? severity;

  const TreatmentAdvicePage({
    super.key,
    required this.treeId,
    required this.diseaseId,
    required this.riskLevelId,
    this.diagnosisHistoryId,
    this.treatmentId,
    required this.adviceList,
    this.diseaseName,
    this.riskLevelName,
    this.totalScore,
    this.note,
    this.severity,
  });

  @override
  State<TreatmentAdvicePage> createState() => _TreatmentAdvicePageState();
}

class _TreatmentAdvicePageState extends State<TreatmentAdvicePage> {
  late String _apiBaseUrl;
  bool _bootstrapping = true;
  String? _err;

  bool _loadingAdvice = false;
  String? _resolvedAdviceText;
  String? _nextChemicalLine;

  bool _accepted = false;
  int? _episodeId;
  int? _recommendedChemicalId;
  int? _recommendedMoaGroupId;

  // ✅ เก็บชื่อสารเคมีที่แนะนำ (ใช้ทำ note/สร้างงานในปฏิทิน)
  String? _recommendedChemicalName;

  // ✅ เก็บ diagnosisHistoryId แบบปรับได้ (กันกรณี widget.diagnosisHistoryId เป็น null)
  int? _diagnosisHistoryId;

  // ✅ พารามิเตอร์แผนการพ่น (อ่านจาก risk_level_moa_plan)
  int? _spraysPerProduct;
  int? _sprayIntervalDays;

  bool _savingAdviceToHistory = false;
  bool _savedAdviceToHistory = false;

  @override
  void initState() {
    super.initState();
    _diagnosisHistoryId = widget.diagnosisHistoryId;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefBase = prefs.getString('api_base_url');
      _apiBaseUrl = (prefBase != null && prefBase.trim().isNotEmpty)
          ? prefBase.trim().replaceAll(RegExp(r'/+$'), '')
          : API_BASE.replaceAll(RegExp(r'/+$'), '');
      await _loadResolvedAdviceAndNextChemical();
    } catch (e) {
      _apiBaseUrl = API_BASE.replaceAll(RegExp(r'/+$'), '');
      _err = e.toString();
    } finally {
      if (mounted) setState(() => _bootstrapping = false);
    }
  }

  // ---------------- API & Logic ----------------

  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ??
        prefs.getString('access_token') ??
        prefs.getString('auth_token');
  }

  Uri _uri(String path, [Map<String, String>? q]) {
    final base = _apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$base/$p').replace(queryParameters: q);
  }

  Map<String, String> _headersJson(String? token) => {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<void> _loadResolvedAdviceAndNextChemical() async {
    setState(() {
      _loadingAdvice = true;
      _err = null;
    });

    final template =
        widget.adviceList.where((e) => e.trim().isNotEmpty).join('\n\n').trim();
    String resolved = template;
    String? chemicalLine;

    try {
      resolved = await _resolveAdviceText(template);
    } catch (_) {}
    try {
      chemicalLine = await _fetchNextChemicalLine();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _resolvedAdviceText = resolved.trim().isEmpty ? null : resolved.trim();
      _nextChemicalLine = chemicalLine;
      _loadingAdvice = false;
    });

    if (resolved.trim().isNotEmpty) {
      var toSave = resolved.trim();
      if (chemicalLine != null && chemicalLine.trim().isNotEmpty) {
        toSave = '$toSave\n\n${chemicalLine.trim()}';
      }
      _saveResolvedAdviceToHistory(toSave);
    }
  }

  Future<String> _resolveAdviceText(String adviceText) async {
    final userId = await _readUserId();
    if (userId == null || userId <= 0) return adviceText;
    try {
      final token = await _readToken();
      final res = await http.post(
        _uri('treatment_advice_mappings/resolve_treatment_advice_text.php'),
        headers: _headersJson(token),
        body: jsonEncode({
          'user_id': userId,
          'disease_id': widget.diseaseId,
          'advice_text': adviceText
        }),
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded['data'] != null)
          return (decoded['data']['resolved_text'] ?? decoded['data']['text'])
              .toString();
      }
    } catch (_) {}
    return adviceText;
  }

  Future<String?> _fetchNextChemicalLine() async {
    try {
      final token = await _readToken();
      final userId = await _readUserId();
      final res = await http.get(
        _uri('treatment_episodes/recommend_next_chemical.php', {
          'tree_id': widget.treeId,
          'disease_id': widget.diseaseId,
          'risk_level_id': widget.riskLevelId,
          if (userId != null) 'user_id': userId.toString(),
        }),
        headers: _headersJson(token),
      );

      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      final data = decoded['data'];
      if (data == null) return null;

      _episodeId = _readInt(data['episode_id']);
      final chem = data['chemical'] ?? data['recommended_chemical'];
      final mg = data['moa_group'] ?? data['moaGroup'];

      _recommendedChemicalId =
          _readInt(chem?['chemical_id']) ?? _readInt(data['chemical_id']);
      _recommendedMoaGroupId =
          _readInt(mg?['moa_group_id']) ?? _readInt(data['moa_group_id']);

      String chemName = chem?['chemical_name'] ?? data['chemical_name'] ?? '';
      String moaCode = mg?['moa_code'] ?? data['moa_code'] ?? '';

      _recommendedChemicalName = chemName.toString().trim();
      if (chemName.isEmpty) return null;
      return 'แนะนำสารถัดไป: $chemName${moaCode.isNotEmpty ? ' (กลุ่ม $moaCode)' : ''}';
    } catch (_) {}
    return null;
  }

  int? _readInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  Future<int?> _readUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id') ??
        int.tryParse(prefs.getString('user_id') ?? '');
  }

  Future<void> _saveResolvedAdviceToHistory(String finalText) async {
    if (_savedAdviceToHistory || _savingAdviceToHistory) return;
    _savingAdviceToHistory = true;

    try {
      final token = await _readToken();

      // ✅ ใช้ id แบบ fallback (กัน null)
      int? dhId = _diagnosisHistoryId ?? widget.diagnosisHistoryId;

      // ✅ ถ้าไม่มี diagnosis_history_id เลย → สร้างใหม่ก่อน เพื่อให้ Tree History มีรายการแน่นอน
      if (dhId == null || dhId <= 0) {
        final created = await _createDiagnosisHistory(finalText);
        if (created != null && created > 0) {
          dhId = created;
          _diagnosisHistoryId = created;
        } else {
          return;
        }
      }

      await http.post(
        _uri('diagnosis_history/update_diagnosis_history.php'),
        headers: _headersJson(token),
        body: jsonEncode({
          // ส่งหลายชื่อ key กัน mismatch ฝั่ง PHP
          'diagnosis_history_id': dhId,
          'id': dhId,
          'history_id': dhId,

          // ส่งหลายชื่อ field กัน mismatch ฝั่ง PHP/DB
          'advice_text': finalText,
          'treatment_advice': finalText,
          'resolved_advice_text': finalText,
          'recommendation': finalText,
        }),
      );

      _savedAdviceToHistory = true;
    } catch (_) {
      // ignore
    } finally {
      _savingAdviceToHistory = false;
    }
  }

  
  // ---------------- Helpers: Create history & calendar reminders ----------------

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  /// ✅ สร้าง diagnosis_history ใหม่ (fallback กรณีไม่ได้ส่ง diagnosisHistoryId มา)
  Future<int?> _createDiagnosisHistory(String adviceText) async {
    try {
      final token = await _readToken();
      final userId = await _readUserId();

      final payload = <String, dynamic>{
        'tree_id': widget.treeId,
        'disease_id': widget.diseaseId,
        'risk_level_id': widget.riskLevelId,
        'advice_text': adviceText,
        // เผื่อ backend ใช้ชื่ออื่น
        'treatment_advice': adviceText,
        'resolved_advice_text': adviceText,
        if (widget.totalScore != null) 'total_score': widget.totalScore,
        if (widget.note != null) 'note': widget.note,
        if (widget.severity != null) 'severity': widget.severity,
        if (userId != null) 'user_id': userId,
        'diagnosed_at': DateTime.now().toIso8601String(),
      };

      final res = await http.post(
        _uri('diagnosis_history/create_diagnosis_history.php'),
        headers: _headersJson(token),
        body: jsonEncode(payload),
      );

      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body);
      final data = (decoded is Map) ? (decoded['data'] ?? decoded) : decoded;

      if (data is Map) {
        return _readInt(data['diagnosis_history_id']) ??
            _readInt(data['id']) ??
            _readInt(data['history_id']);
      }
    } catch (_) {}
    return null;
  }

  /// ✅ อ่านพารามิเตอร์แผนการพ่นจาก risk_level_moa_plan (sprays_per_product + interval days)

  Future<void> _loadSprayParamsFromDiseaseRiskLevelsIfNeeded() async {
    // ✅ ดึง "จำนวนครั้ง" (times) และ "ระยะห่างวัน" (days) จากตาราง disease_risk_levels (DB จริง)
    if (_spraysPerProduct != null && _sprayIntervalDays != null) return;

    try {
      final token = await _readToken();
      if (token == null) return;

      final res = await http.get(
        _uri('disease_risk_levels/read_disease_risk_levels.php', {
          'risk_level_id': widget.riskLevelId,
        }),
        headers: _headersJson(token),
      );

      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      dynamic row;

      if (decoded is Map && decoded['data'] is List && (decoded['data'] as List).isNotEmpty) {
        row = (decoded['data'] as List).first;
      } else if (decoded is Map && decoded['data'] is Map) {
        row = decoded['data'];
      } else if (decoded is List && decoded.isNotEmpty) {
        row = decoded.first;
      }

      if (row is! Map) return;
      final m = Map<String, dynamic>.from(row);

      final times = _toInt(m['times'] ?? m['spray_times'] ?? m['sprays_times'] ?? m['sprays'], 0);
      final days = _toInt(m['days'] ?? m['interval_days'] ?? m['spray_interval_days'] ?? m['spray_every_days'] ?? m['interval'], 0);
      final spraysPerProduct = _toInt(m['sprays_per_product'] ?? m['spraysPerProduct'], 0);

      if (times > 0) {
        _spraysPerProduct = times;
      } else if (spraysPerProduct > 0) {
        _spraysPerProduct = spraysPerProduct;
      }

      if (days > 0) {
        _sprayIntervalDays = days;
      }
    } catch (_) {}
  }


  Future<void> _loadSprayPlanParamsIfNeeded() async {
    if (_spraysPerProduct != null && _sprayIntervalDays != null) return;

    // 1) พยายามอ่านจาก disease_risk_levels ก่อน (days/times)
    await _loadSprayParamsFromDiseaseRiskLevelsIfNeeded();
    if (_spraysPerProduct != null && _sprayIntervalDays != null) return;

    try {
      final token = await _readToken();

      final res = await http.get(
        _uri('risk_level_moa_plan/read_risk_level_moa_plan.php', {
          'risk_level_id': widget.riskLevelId,
        }),
        headers: _headersJson(token),
      );

      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      dynamic row;

      if (decoded is Map && decoded['data'] is List && (decoded['data'] as List).isNotEmpty) {
        row = (decoded['data'] as List).first;
      } else if (decoded is Map && decoded['data'] is Map) {
        row = decoded['data'];
      } else if (decoded is List && decoded.isNotEmpty) {
        row = decoded.first;
      }

      if (row is! Map) return;
      final m = Map<String, dynamic>.from(row);

      _spraysPerProduct = _toInt(m['sprays_per_product'] ?? m['spraysPerProduct'], 0);
      _sprayIntervalDays = _toInt(
        m['spray_interval_days'] ??
            m['interval_days'] ??
            m['spray_every_days'] ??
            m['spray_interval'] ??
            m['interval'],
        0,
      );
    } catch (_) {}
  }

  /// ✅ สร้าง care_reminders หลายวัน เพื่อให้ขึ้นในปฏิทินหน้า Home
  Future<void> _createSprayReminders() async {
    final token = await _readToken();
    if (token == null) return;

    await _loadSprayPlanParamsIfNeeded();

    final sprays = (_spraysPerProduct != null && _spraysPerProduct! > 0) ? _spraysPerProduct! : 1;
    final interval = (_sprayIntervalDays != null && _sprayIntervalDays! > 0) ? _sprayIntervalDays! : 7;

    final dhId = _diagnosisHistoryId ?? widget.diagnosisHistoryId;

    final chemName = (_recommendedChemicalName ?? '').trim();
    final baseNote = chemName.isNotEmpty ? 'พ่นยา: $chemName' : 'พ่นยา';

    final start = _dateOnly(DateTime.now());

    for (int i = 0; i < sprays; i++) {
      final d = start.add(Duration(days: interval * i));
      await _createCareReminder(
        token: token,
        reminderDate: d,
        note: baseNote,
        diagnosisHistoryId: dhId,
        treatmentId: widget.treatmentId,
        chemicalId: _recommendedChemicalId,
        chemicalName: chemName.isNotEmpty ? chemName : null,
      );
    }
  }

  Future<void> _createCareReminder({
    required String token,
    required DateTime reminderDate,
    required String note,
    int? diagnosisHistoryId,
    int? treatmentId,
    int? chemicalId,
    String? chemicalName,
  }) async {
    try {
      final userId = await _readUserId();

      final payload = <String, dynamic>{
        'tree_id': widget.treeId,
        // ส่งหลายชื่อกัน mismatch
        'reminder_date': _ymd(reminderDate),
        'date': _ymd(reminderDate),
        'scheduled_date': _ymd(reminderDate),
        'note': note,
        'is_done': 0,
        if (userId != null) 'user_id': userId,
        if (diagnosisHistoryId != null) 'diagnosis_history_id': diagnosisHistoryId,
        if (treatmentId != null) 'treatment_id': treatmentId,
        if (chemicalId != null) 'chemical_id': chemicalId,
        if (chemicalName != null) 'chemical_name': chemicalName,
      };

      await http.post(
        _uri('care_reminders/create_care_reminders.php'),
        headers: _headersJson(token),
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  // ---------------- UI Components ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: const Text('คำแนะนำการรักษา',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _bootstrapping
          ? const Center(child: CircularProgressIndicator(color: kPrimaryGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ผลวินิจฉัย : ${widget.diseaseName ?? widget.diseaseId}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('ความรุนแรง : ${widget.riskLevelName ?? 'ไม่ระบุ'}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 18),

                  // 🤖 บล็อก 1: แนะนำวิธีการรักษา
                  _buildAdviceBlock(),

                  const SizedBox(height: 16),

                  // 🧪 บล็อก 2: สารเคมีที่แนะนำ (แบบกดกางออกได้)
                  if (_nextChemicalLine != null) _buildChemicalBlock(),

                  const SizedBox(height: 24),

                  _buildSubmitButton(),
                ],
              ),
            ),
    );
  }

  // แก้ไข: ใช้ Theme ทับเพื่อลบเส้นกั้น Divider ของ ExpansionTile
  Widget _buildAdviceBlock() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent), // ลบเส้นกั้นบน-ล่าง
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: const Text('🤖', style: TextStyle(fontSize: 18)),
          title: const Text('แนะนำวิธีการรักษา',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: kCardBg, borderRadius: BorderRadius.circular(14)),
                child: Text(_resolvedAdviceText ?? 'กำลังโหลด...',
                    style: const TextStyle(
                        fontSize: 15, height: 1.5, color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // แก้ไข: บล็อกสารเคมีเป็น ExpansionTile และลบเส้นกั้น
  Widget _buildChemicalBlock() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF), // สีฟ้าอ่อนพิเศษ
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent), // ลบเส้นกั้นบน-ล่าง
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: const Icon(Icons.science_outlined, color: kChemicalBlue),
          title: const Text('สารเคมีที่แนะนำ',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kChemicalBlue)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade50),
                ),
                child: Text(_nextChemicalLine!,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryGreen,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        onPressed: _accepted ? null : _onAcceptPlan,
        child: const Text('รับแผนการรักษาการพ่นยา',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ),
    );
  }

  Future<void> _onAcceptPlan() async {
    setState(() => _accepted = true);

    try {
      // ✅ เซฟคำแนะนำซ้ำอีกรอบกันหลุด (กรณีโหลดเสร็จแล้วแต่ update ไม่เข้า)
      final advice = (_resolvedAdviceText ?? '').trim();
      final chemLine = (_nextChemicalLine ?? '').trim();
      final toSave = [
        if (advice.isNotEmpty) advice,
        if (chemLine.isNotEmpty) chemLine,
      ].join('\n\n').trim();
      if (toSave.isNotEmpty) {
        await _saveResolvedAdviceToHistory(toSave);
      }

      // ✅ สร้างงานในปฏิทิน (care_reminders)
      await _createSprayReminders();
    } catch (_) {
      // ignore
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_refresh_ts_v1', DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt('home_calendar_refresh_ts', DateTime.now().millisecondsSinceEpoch);

    // ✅ บังคับให้กลับไปแท็บ Home (กันกรณีอยู่แท็บ Share แล้ว popUntil จะกลับไปแท็บเดิม)
    await prefs.setInt('pending_nav_index', 0);
    await prefs.setInt('selectedIndex', 0);
    await prefs.setBool('force_home_tab', true);

    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
