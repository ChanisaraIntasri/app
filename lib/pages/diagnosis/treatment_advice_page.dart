import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../mainpage/main_nav.dart';

const kPrimaryGreen = Color(0xFF005E33);

// ✅ แก้ API_BASE ให้เป็นของคุณ (รองรับ --dart-define=API_BASE=...)
// ตัวอย่าง: https://xxxx.ngrok-free.dev/crud/api
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api',
);

/// หน้าคำแนะนำการรักษา (พื้นหลังสีขาว)
/// แสดง:
/// 1) ผลวินิจฉัย (ชื่อโรค)
/// 2) ระดับความรุนแรง
/// 3) คำแนะนำการรักษา (พับ/ขยายได้)
class TreatmentAdvicePage extends StatefulWidget {
  final String treeId;
  final String diseaseId;
  final String diseaseName;

  // ✅ เพื่อผูก reminder ให้รู้ว่ามาจากประวัติการวินิจฉัยไหน/คำแนะนำไหน
  final int? diagnosisHistoryId;
  final int? treatmentId;

  /// คะแนนรวมจากการตอบแบบสอบถาม
  final double totalScore;

  /// ระดับความรุนแรงที่คำนวณได้ (จาก disease_risk_levels)
  final String riskLevelId;
  final String riskLevelName;

  /// ข้อความเพิ่มเติม (ถ้ามี)
  final String? note;

  /// รายการคำแนะนำ (1 รายการต่อ 1 treatment หรือแยกหัวข้อ)
  final List<String> adviceList;

  /// ใส่รูปได้ (ไม่ใส่ก็ได้)
  /// - ถ้าเป็น URL (http/https) จะใช้ Image.network
  /// - ถ้าเป็น assets/... จะใช้ Image.asset
  /// - อย่างอื่นจะพยายามใช้ Image.file
  final String? referenceImagePath; // "ภาพเปรียบเทียบ"
  final String? userImagePath;      // "ภาพของคุณ"

  const TreatmentAdvicePage({
    super.key,
    required this.treeId,
    required this.diseaseId,
    required this.diseaseName,
    this.diagnosisHistoryId,
    this.treatmentId,
    required this.totalScore,
    required this.riskLevelId,
    required this.riskLevelName,
    this.note,
    required this.adviceList,
    this.referenceImagePath,
    this.userImagePath,
  });

  @override
  State<TreatmentAdvicePage> createState() => _TreatmentAdvicePageState();
}

class _TreatmentAdvicePageState extends State<TreatmentAdvicePage> {
  bool _showAdvice = true;

  // ---------------- API Helpers (ใช้ token แบบเดียวกับหน้าอื่น ๆ) ----------------
  Uri _uri(String path, [Map<String, String>? q]) {
    final base = API_BASE.endsWith('/')
        ? API_BASE.substring(0, API_BASE.length - 1)
        : API_BASE;
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$base/$p').replace(queryParameters: q);
  }

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

  Map<String, String> _headersJson(String? token) => {
        ..._headers(token),
        'Content-Type': 'application/json; charset=utf-8',
      };

  // ---------------- Plan/Key Helpers ----------------
  String _normKey(String s) => s.trim().toLowerCase();

  String _severityToCode(String s) {
    final t = _normKey(s);
    // รองรับทั้งไทย/อังกฤษแบบที่พบบ่อย
    if (t.contains('high') || t.contains('สูง') || t.contains('รุนแรง')) return 'high';
    if (t.contains('medium') || t.contains('กลาง') || t.contains('ปานกลาง')) return 'medium';
    if (t.contains('low') || t.contains('ต่ำ') || t.contains('น้อย')) return 'low';
    return t;
  }

  String _fmtYMD(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  Future<Map<String, dynamic>?> _loadPlanOverride() async {
    // จะมีค่าเมื่อหน้า disease_questions_page เรียก _cacheTreatmentPlanOverride(...)
    const storageKey = 'treatment_plan_overrides_v1';
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final root = Map<String, dynamic>.from(decoded);
      final diseaseK = _normKey(widget.diseaseName);
      final sevK1 = _normKey(widget.riskLevelName);
      final sevK2 = _severityToCode(widget.riskLevelName);

      final k1 = '${diseaseK}__${sevK1}';
      final k2 = '${diseaseK}__${sevK2}';

      final v1 = root[k1];
      if (v1 is Map) return Map<String, dynamic>.from(v1);

      final v2 = root[k2];
      if (v2 is Map) return Map<String, dynamic>.from(v2);

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> _fetchExistingReminderKeys({
    required String token,
    required int treeId,
    required String dateFrom,
    required String dateTo,
  }) async {
    try {
      final uri = _uri(
        'care_reminders/read_care_reminders.php',
        {
          'tree_id': treeId.toString(),
          'date_from': dateFrom,
          'date_to': dateTo,
        },
      );

      final res = await http.get(uri, headers: _headers(token));
      if (res.statusCode < 200 || res.statusCode >= 300) return {};

      final decoded = jsonDecode(res.body);
      final data = (decoded is Map && decoded['data'] is List)
          ? decoded['data']
          : (decoded is List ? decoded : null);

      if (data is! List) return {};

      final out = <String>{};
      for (final it in data) {
        if (it is! Map) continue;
        final d = (it['reminder_date'] ?? '').toString();
        final n = (it['note'] ?? '').toString();
        if (d.isEmpty) continue;
        out.add('$d||$n');
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _createRemindersFromPlanIfNeeded() async {
    // ถ้าไม่พบแผน (ยังไม่เคยคำนวณ/บันทึก override) ก็ไม่ทำอะไร
    final plan = await _loadPlanOverride();
    if (plan == null) return;

    final everyDays = int.tryParse((plan['everyDays'] ?? '').toString()) ?? 0;
    final totalTimes = int.tryParse((plan['totalTimes'] ?? '').toString()) ?? 0;
    final taskName = (plan['taskName'] ?? 'พ่นยา').toString().trim();
    if (everyDays <= 0 || totalTimes <= 0) return;

    final treeId = int.tryParse(widget.treeId) ?? 0;
    if (treeId <= 0) return;

    final token = (await _readToken()) ?? '';
    if (token.trim().isEmpty) return;

    // สร้างวันนัด: วันนี้ + (everyDays * i) จำนวน totalTimes ครั้ง
    final start = DateTime.now();
    final dates = <DateTime>[];
    for (int i = 0; i < totalTimes; i++) {
      dates.add(start.add(Duration(days: everyDays * i)));
    }
    if (dates.isEmpty) return;

    final dateFrom = _fmtYMD(dates.first);
    final dateTo = _fmtYMD(dates.last);

    // กันกดซ้ำ: อ่านที่มีอยู่แล้ว แล้วสร้างเฉพาะที่ยังไม่มี
    final existingKeys = await _fetchExistingReminderKeys(
      token: token,
      treeId: treeId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    for (final d in dates) {
      final ymd = _fmtYMD(d);
      final key = '$ymd||$taskName';
      if (existingKeys.contains(key)) continue;

      try {
        final res = await http.post(
          _uri('care_reminders/create_care_reminders.php'),
          headers: _headersJson(token),
          body: jsonEncode({
            'tree_id': treeId,
            // diagnosis_history_id / treatment_id ส่งเป็น null ได้ (ตารางอนุญาต NULL)
            'diagnosis_history_id': widget.diagnosisHistoryId,
            'treatment_id': widget.treatmentId,
            'reminder_date': ymd,
            'is_done': 0,
            'note': taskName,
          }),
        );

        if (res.statusCode < 200 || res.statusCode >= 300) {
          debugPrint('create_care_reminders failed status=${res.statusCode} body=${res.body}');
        } else {
          debugPrint('create_care_reminders ok date=$ymd');
        }
      } catch (e) {
        debugPrint('create_care_reminders exception: $e');
      }
    }
  }

  bool _isHttpUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  ImageProvider? _imgProvider(String? imagePath) {
    if (imagePath == null) return null;
    final p = imagePath.trim();
    if (p.isEmpty) return null;
    if (_isHttpUrl(p)) return NetworkImage(p);
    if (p.startsWith('assets/')) return AssetImage(p);
    final f = File(p);
    if (f.existsSync()) return FileImage(f);
    return null;
  }

  Widget _imageBox({required String title, required String? imagePath}) {
    final provider = _imgProvider(imagePath);
    if (provider == null) return const SizedBox(height: 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image(image: provider, fit: BoxFit.cover),
          ),
        ),
      ],
    );
  }

  Widget _headerText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.diseaseName,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'ความรุนแรง : ${widget.riskLevelName}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        if (widget.note != null && widget.note!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(widget.note!, style: const TextStyle(fontSize: 14)),
        ],
      ],
    );
  }

  Widget _adviceToggleButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _showAdvice = !_showAdvice),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.tips_and_updates, color: kPrimaryGreen),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'คำแนะนำการรักษา',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            Icon(_showAdvice ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    );
  }

  Widget _adviceCard() {
    final merged = widget.adviceList.where((x) => x.trim().isNotEmpty).toList();
    final body = merged.isEmpty ? 'ยังไม่มีคำแนะนำในระดับความรุนแรงนี้' : merged.join('\n\n');

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 200),
      crossFadeState:
          _showAdvice ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
          boxShadow: const [
            BoxShadow(
              blurRadius: 8,
              offset: Offset(0, 2),
              color: Color(0x14000000),
            )
          ],
        ),
        child: Text(
          body,
          style: const TextStyle(fontSize: 14, height: 1.35),
        ),
      ),
      secondChild: const SizedBox(height: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // ✅ ตามที่ขอ: พื้นหลังขาว
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: const Text('คำแนะนำการรักษา'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.referenceImagePath != null || widget.userImagePath != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _imageBox(title: 'ภาพเปรียบเทียบ', imagePath: widget.referenceImagePath),
                    const SizedBox(height: 14),
                    _imageBox(title: 'ภาพของคุณ', imagePath: widget.userImagePath),
                  ],
                ),
              const SizedBox(height: 16),
              _headerText(),
              const SizedBox(height: 16),
              _adviceToggleButton(),
              _adviceCard(),
              const SizedBox(height: 18),

              // ปุ่มรับแผนการรักษา
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () async {
                    // ✅ ไปหน้า Home (ผ่าน MainNav) และล้าง stack
                    final prefs = await SharedPreferences.getInstance();

                    // ✅ บันทึกผลวินิจฉัยล่าสุดของ “ต้นนี้” (ใช้ให้หน้า Home รวมกลุ่มได้ แม้ tree record ยังไม่อัปเดต)
                    const diagKey = 'tree_last_diagnosis_v1';
                    try {
                      final rawDiag = prefs.getString(diagKey);
                      Map<String, dynamic> diagMap = {};
                      if (rawDiag != null && rawDiag.trim().isNotEmpty) {
                        final decoded = jsonDecode(rawDiag);
                        if (decoded is Map) {
                          diagMap = Map<String, dynamic>.from(decoded);
                        }
                      }

                      diagMap[widget.treeId.toString()] = {
                        'treeId': widget.treeId.toString(),
                        'diseaseId': widget.diseaseId.toString(),
                        'disease': widget.diseaseName,
                        'severity': widget.riskLevelName,
                        'riskLevelId': widget.riskLevelId.toString(),
                        'riskLevelName': widget.riskLevelName,
                        'diagnosedAt': DateTime.now().toIso8601String(),
                      };

                      await prefs.setString(diagKey, jsonEncode(diagMap));
                    } catch (_) {}

                    // ✅ สั่งให้หน้า Home รีโหลดปฏิทินทันที
                    await prefs.setInt('app_refresh_ts_v1', DateTime.now().millisecondsSinceEpoch);

                    // ✅ บันทึกวันนัดลงฐานข้อมูล care_reminders
                    // (ต้องมีแผน override จากหน้า disease_questions_page)
                    await _createRemindersFromPlanIfNeeded();

                    // พยายามอ่านชื่อผู้ใช้ที่เคยบันทึกไว้ (ถ้าไม่มีจะเป็นค่าว่าง)
                    const keys = <String>['username','userName','initialUsername','name','displayName'];
                    String initialUsername = '';
                    for (final k in keys) {
                      final v = prefs.getString(k);
                      if (v != null && v.trim().isNotEmpty) {
                        initialUsername = v.trim();
                        break;
                      }
                    }

                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => MainNav(initialUsername: initialUsername)),
                      (r) => false,
                    );
                  },
                  child: const Text(
                    'รับแผนการรักษา',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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
