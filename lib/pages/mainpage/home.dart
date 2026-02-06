import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

// Import หน้า Setting
import 'setting.dart';

// ✅ ใช้ปฏิทินเลือกวันเริ่มพ่นยา (ตามไฟล์ของคุณ)
import '../diagnosis/select_start_spray_date_page.dart';

// ยัง keep ไว้ตามโปรเจกต์เดิม (ไม่เปลี่ยน UI)
import 'package:flutter_application_1/models/citrus_tree_record.dart';

const kBg = Color.fromARGB(255, 255, 255, 255);
const kPrimaryGreen = Color(0xFF005E33);
const kCardBg = Color(0xFFEDEDED);

/// ปรับตามโปรเจกต์ของคุณได้ (หรือใช้ --dart-define=API_BASE=...)
/// ตัวอย่าง: https://xxxx.ngrok-free.dev/crud/api
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

int _toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// หน้าหลัก (Home)
class HomePage extends StatefulWidget {
  final List<CitrusTreeRecord> trees;
  final ValueChanged<List<CitrusTreeRecord>>? onTreesUpdated;

  // ✅ เพิ่มตัวแปร username เพื่อส่งต่อให้หน้า Setting
  final String username;

  const HomePage({
    super.key,
    this.trees = const [],
    this.onTreesUpdated,
    // ✅ รับ username เข้ามา (ค่า default คือว่างไว้ก่อนเผื่อเรียกใช้ที่อื่น)
    this.username = 'farmer_somchai',
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _TreeLite {
  final String id;
  final String name;
  const _TreeLite({required this.id, required this.name});
}

class _ReminderRow {
  final int reminderId;
  final String treeId;
  final DateTime reminderDate;
  final int isDone; // 0/1
  final String note;
  final int? diagnosisHistoryId;
  final int? treatmentId;

  const _ReminderRow({
    required this.reminderId,
    required this.treeId,
    required this.reminderDate,
    required this.isDone,
    required this.note,
    required this.diagnosisHistoryId,
    required this.treatmentId,
  });

  String get dateKey =>
      '${reminderDate.year.toString().padLeft(4, '0')}-${reminderDate.month.toString().padLeft(2, '0')}-${reminderDate.day.toString().padLeft(2, '0')}';

  _ReminderRow copyWith({int? isDone}) => _ReminderRow(
        reminderId: reminderId,
        treeId: treeId,
        reminderDate: reminderDate,
        isDone: isDone ?? this.isDone,
        note: note,
        diagnosisHistoryId: diagnosisHistoryId,
        treatmentId: treatmentId,
      );
}

// ==========================
// ✅ สำหรับ “ติดตามผลหลังครบแผน”
// ==========================
class _FollowupCandidate {
  final int diagnosisHistoryId;
  final String treeId;
  final DateTime lastPlanDate;
  final String lastNote;

  /// จำนวนวันหลังแผนสิ้นสุดก่อนถามติดตามผล (fallback = 5)
  final int evaluationAfterDays;

  _FollowupCandidate({
    required this.diagnosisHistoryId,
    required this.treeId,
    required this.lastPlanDate,
    required this.lastNote,
    int? evaluationAfterDays,
  }) : evaluationAfterDays =
            (evaluationAfterDays != null && evaluationAfterDays > 0) ? evaluationAfterDays : 5;

  String get lastKey => _ymd(lastPlanDate);
}

// ✅ ผลลัพธ์จากกล่องติดตามผล (Dialog)
class _FollowupDialogResult {
  final bool cured;
  final DateTime? nextStartDate;

  const _FollowupDialogResult._({required this.cured, this.nextStartDate});

  const _FollowupDialogResult.cured() : this._(cured: true);
  const _FollowupDialogResult.notCured(DateTime d)
      : this._(cured: false, nextStartDate: d);
}

class _HomePageState extends State<HomePage> {
  // ------------ state ------------
  List<_TreeLite> _trees = [];
  Map<String, int> _treeNoById = {};

  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  bool _loadingReminders = false;
  String _lastRefreshStamp = '';
  String _apiBaseUrl = API_BASE;
  Map<String, dynamic> _lastDiagnosisByTreeId = {};
  final List<_ReminderRow> _reminders = [];
  final Map<String, List<_ReminderRow>> _remindersByDay = {};
  Timer? _watcher;

  // ✅ กันเด้งถามซ้อน
  bool _followupPrompting = false;

  // ✅ ตั้งค่า “หลังจบแผนกี่วันให้ถาม”
  static const int _kFollowupDaysAfterPlan = 5;

  int _weeksInMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final daysInMonth = last.day;

    const startWeekday = DateTime.monday; // 1
    int offset = first.weekday - startWeekday;
    offset = (offset % 7 + 7) % 7;

    final totalCells = offset + daysInMonth;
    return (totalCells / 7).ceil();
  }

  void _ensureTreeNoIndex() {
    if (_trees.isNotEmpty) {
      _treeNoById = {
        for (int i = 0; i < _trees.length; i++) _trees[i].id.toString(): i + 1,
      };
      return;
    }
    final ids = <String>{};
    for (final r in _reminders) {
      final id = r.treeId.toString().trim();
      if (id.isNotEmpty) ids.add(id);
    }
    final sorted = ids.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a);
        final bi = int.tryParse(b);
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.compareTo(b);
      });
    _treeNoById = {
      for (int i = 0; i < sorted.length; i++) sorted[i]: i + 1,
    };
  }

  int? _extractTrailingNumber(String name) {
    final norm = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    final m = RegExp(r'(\d+)\s*$').firstMatch(norm);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  String _normalizeTreeName(String raw, {String? fallbackId}) {
    final norm = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (norm.isEmpty) {
      if (fallbackId != null && RegExp(r'^\d+$').hasMatch(fallbackId)) {
        return 'ต้นที่ $fallbackId';
      }
      return '';
    }
    final m = RegExp(r'^(?:ต้น|ต้นที่)\s*(\d+)$').firstMatch(norm);
    if (m != null) return 'ต้นที่ ${m.group(1)}';
    if (RegExp(r'^\d+$').hasMatch(norm)) return 'ต้นที่ $norm';
    return norm;
  }

  String _treeLabelById(String treeId) {
    final tid = treeId.toString().trim();
    if (_trees.isNotEmpty) {
      final idx = _trees.indexWhere((t) => t.id.toString() == tid);
      if (idx >= 0) {
        final rawName = _s(_trees[idx].name);
        final normalized = _normalizeTreeName(rawName, fallbackId: tid);
        if (normalized.isNotEmpty) return normalized;
        if (RegExp(r'^\d+$').hasMatch(tid)) return 'ต้นที่ $tid';
        return 'ไม่ทราบชื่อต้น';
      }
    }
    if (RegExp(r'^\d+$').hasMatch(tid)) return 'ต้นที่ $tid';
    _ensureTreeNoIndex();
    final no = _treeNoById[tid];
    if (no != null) return 'ต้นที่ $no';
    return 'ไม่ทราบชื่อต้น';
  }

  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ??
        prefs.getString('access_token') ??
        prefs.getString('auth_token');
  }

  Future<void> _refreshApiBaseFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final p = (prefs.getString('api_base_url') ?? '').trim();
    var base = p.isNotEmpty ? p : API_BASE;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    _apiBaseUrl = base;
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

  Map<String, String> _headersJson(String? token) => {
        ..._headers(token),
        'Content-Type': 'application/json; charset=utf-8',
      };

  @override
  void initState() {
    super.initState();
    _trees = widget.trees.map((t) => _TreeLite(id: t.id.toString(), name: _s(t.name))).toList();
    Future.microtask(() async {
      await _loadTreesFromApi();
    });
    _reloadFromPrefs();
    _loadRemindersForMonth(_focusedDay);
    _startRefreshWatcher();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trees != oldWidget.trees) {
      _trees = widget.trees.map((t) => _TreeLite(id: t.id.toString(), name: _s(t.name))).toList();
      _ensureTreeNoIndex();
      _pruneRemindersNotInTrees();
      _rebuildDueIndexFromReminders();
    }
  }

  @override
  void dispose() {
    _watcher?.cancel();
    super.dispose();
  }

  void _startRefreshWatcher() {
    _watcher?.cancel();
    _watcher = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      final prefs = await SharedPreferences.getInstance();
      final ts1 = prefs.getInt('app_refresh_ts_v1')?.toString() ?? '';
      final ts2 = prefs.getInt('home_calendar_refresh_ts')?.toString() ?? '';
      final stamp = '$ts1|$ts2';
      if (stamp != _lastRefreshStamp) {
        _lastRefreshStamp = stamp;
        await _reloadFromPrefs();
        await _loadRemindersForMonth(_focusedDay);
      }
    });
  }

  Future<void> _reloadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _refreshApiBaseFromPrefs();
      await _loadTreesFromApi(silent: true);
      final raw = prefs.getString('tree_last_diagnosis_v1') ?? '{}';
      final decoded = jsonDecode(raw);
      if (!mounted) return;
      setState(() {
        if (decoded is Map) {
          final mapped = decoded.map((k, v) => MapEntry(k.toString(), v));
          _lastDiagnosisByTreeId = Map<String, dynamic>.from(mapped);
        } else {
          _lastDiagnosisByTreeId = <String, dynamic>{};
        }
      });
      _rebuildDueIndexFromReminders();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lastDiagnosisByTreeId = {};
      });
      _rebuildDueIndexFromReminders();
    }
  }

  Future<void> _loadTreesFromApi({bool silent = false}) async {
    try {
      await _refreshApiBaseFromPrefs();
      final token = await _readToken();
      if (token == null || token.isEmpty) return;

      final uri = Uri.parse(_joinApi(_apiBaseUrl, '/orange_trees/read_orange_trees.php'));
      final res = await http.get(uri, headers: _headers(token)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      List data = [];
      if (decoded is Map && decoded['data'] is List) {
        data = decoded['data'] as List;
      } else if (decoded is List) {
        data = decoded;
      }

      final items = <_TreeLite>[];
      for (final it in data) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);
        final id = _s(m['tree_id'] ?? m['id']);
        if (id.isEmpty) continue;
        final name = _s(m['tree_name'] ?? m['name']);
        items.add(_TreeLite(id: id, name: name));
      }

      items.sort((a, b) {
        final an = _extractTrailingNumber(a.name);
        final bn = _extractTrailingNumber(b.name);
        if (an != null && bn != null && an != bn) return an.compareTo(bn);
        final ai = int.tryParse(a.id);
        final bi = int.tryParse(b.id);
        if (ai != null && bi != null && ai != bi) return ai.compareTo(bi);
        return a.id.compareTo(b.id);
      });

      if (!mounted) return;
      setState(() {
        _trees = items;
      });

      _ensureTreeNoIndex();
      _pruneRemindersNotInTrees();
    } catch (_) {}
  }

  void _pruneRemindersNotInTrees() {
    if (_trees.isEmpty || _reminders.isEmpty) return;
    final ids = _trees.map((t) => t.id).toSet();
    final before = _reminders.length;
    _reminders.removeWhere((r) => !ids.contains(r.treeId));
    if (_reminders.length != before) {
      _rebuildDueIndexFromReminders();
    }
  }

  Future<void> _loadRemindersForMonth(DateTime focus) async {
    if (_loadingReminders) return;
    _loadingReminders = true;

    try {
      await _refreshApiBaseFromPrefs();
      await _loadTreesFromApi(silent: true);
      final token = await _readToken();
      if (token == null || token.isEmpty) {
        _loadingReminders = false;
        return;
      }

      final first = DateTime(focus.year, focus.month, 1);
      final last = DateTime(focus.year, focus.month + 1, 0);

      final uri = Uri.parse(
        _joinApi(
          _apiBaseUrl,
          '/care_reminders/read_care_reminders.php?date_from=${_ymd(first)}&date_to=${_ymd(last)}',
        ),
      );

      final res = await http.get(uri, headers: _headers(token)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        _loadingReminders = false;
        return;
      }

      final decoded = jsonDecode(res.body);
      List data = [];
      if (decoded is Map && decoded['data'] is List) {
        data = decoded['data'] as List;
      } else if (decoded is List) {
        data = decoded;
      }

      final rows = <_ReminderRow>[];
      for (final it in data) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);

        final reminderId = _toInt(m['reminder_id'] ?? m['id']);
        final treeId = _s(m['tree_id']);
        String note = _s(m['note']);
        final chemicalName = _s(m['chemical_name']);
        if (chemicalName.isNotEmpty) {
          final n = note.trim();
          if (n.isEmpty) {
            note = chemicalName;
          } else if (!n.contains(chemicalName)) {
            note = '$n ($chemicalName)';
          } else {
            note = n;
          }
        }

        final rawDate = _s(m['reminder_date']);
        DateTime? dt;
        if (rawDate.isNotEmpty) {
          dt = DateTime.tryParse(rawDate);
          if (dt == null && rawDate.length >= 10) {
            dt = DateTime.tryParse(rawDate.substring(0, 10));
          }
        }
        if (dt == null) continue;

        final isDone = _toInt(m['is_done']);
        final dhId = (m['diagnosis_history_id'] == null)
            ? null
            : int.tryParse(m['diagnosis_history_id'].toString());
        final tId =
            (m['treatment_id'] == null) ? null : int.tryParse(m['treatment_id'].toString());

        rows.add(
          _ReminderRow(
            reminderId: reminderId,
            treeId: treeId,
            reminderDate: _dateOnly(dt),
            isDone: isDone,
            note: note,
            diagnosisHistoryId: dhId,
            treatmentId: tId,
          ),
        );
      }

      if (_trees.isNotEmpty) {
        final ids = _trees.map((t) => t.id).toSet();
        rows.removeWhere((r) => !ids.contains(r.treeId));
      }

      if (!mounted) return;
      setState(() {
        _reminders
          ..clear()
          ..addAll(rows);
      });

      _rebuildDueIndexFromReminders();

      // ✅ โหลด reminders เสร็จแล้ว -> เช็ค follow-up อัตโนมัติ
      _scheduleFollowupCheck();
    } catch (_) {
    } finally {
      _loadingReminders = false;
    }
  }

  void _rebuildDueIndexFromReminders() {
    _remindersByDay.clear();
    for (final r in _reminders) {
      _remindersByDay.putIfAbsent(r.dateKey, () => []);
      _remindersByDay[r.dateKey]!.add(r);
    }
    if (mounted) setState(() {});
  }

  List<_ReminderRow> _itemsOfDay(DateTime day) => _remindersByDay[_ymd(day)] ?? const [];
  bool _hasDue(DateTime day) => _itemsOfDay(day).isNotEmpty;

  bool _isAllDoneOnDay(DateTime day) {
    final items = _itemsOfDay(day);
    if (items.isEmpty) return false;
    return items.every((x) => x.isDone == 1);
  }

  bool _isFutureDay(DateTime day) {
    final today = _dateOnly(DateTime.now());
    return _dateOnly(day).isAfter(today);
  }

  Future<void> _toggleDone(_ReminderRow r, bool done) async {
    if (_isFutureDay(r.reminderDate)) return;

    final token = await _readToken();
    if (token == null || token.isEmpty) return;
    await _refreshApiBaseFromPrefs();

    try {
      final uri = Uri.parse(_joinApi(_apiBaseUrl, '/care_reminders/update_care_reminders.php'));
      final res = await http
          .post(
            uri,
            headers: _headersJson(token),
            body: jsonEncode({
              'reminder_id': r.reminderId,
              'is_done': done ? 1 : 0,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final idx = _reminders.indexWhere((x) => x.reminderId == r.reminderId);
        if (idx >= 0) {
          setState(() {
            _reminders[idx] = _reminders[idx].copyWith(isDone: done ? 1 : 0);
          });
          _rebuildDueIndexFromReminders();

          // ✅ ถ้าผู้ใช้ “ยกเลิกทำแล้ว” -> ล้างสถานะ follow-up ที่เคยตอบไว้
          // เพื่อให้ถ้าติ๊ก “ทำแล้ว” ใหม่ สามารถเด้งถามติดตามผลอีกครั้ง (ใช้สำหรับทดสอบ/เผลอกด)
          if (!done) {
            final dhId = r.diagnosisHistoryId;
            if (dhId != null && dhId > 0) {
              await _clearFollowupAnsweredForDh(dhId);
            }
          }

          // ✅ เผื่อกรณีทำครบพอดี แล้วเข้าเงื่อนไขติดตามผล
          _scheduleFollowupCheck();
        }
      }
    } catch (_) {}
  }

  Future<void> _clearFollowupAnsweredForDh(int diagnosisHistoryId) async {
    try {
      final items = _reminders.where((x) => x.diagnosisHistoryId == diagnosisHistoryId).toList();
      if (items.isEmpty) return;

      items.sort((a, b) => a.reminderDate.compareTo(b.reminderDate));
      final lastKey = _ymd(items.last.reminderDate);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('followup_v1_answered_${diagnosisHistoryId}_$lastKey');
      await prefs.remove('followup_v1_snooze_${diagnosisHistoryId}_$lastKey');
      await prefs.remove('followup_v1_result_${diagnosisHistoryId}_$lastKey');
      await prefs.remove('followup_v1_next_start_${diagnosisHistoryId}_$lastKey');
    } catch (_) {}
  }

  Future<void> _openDueDialog(DateTime day) async {
    final items = _itemsOfDay(day);
    if (items.isEmpty) return;

    final dateText = '${day.day}/${day.month}/${day.year}';

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'งานที่ต้องทำวันนี้',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          if (Navigator.of(dialogCtx, rootNavigator: true).canPop()) {
                            Navigator.of(dialogCtx, rootNavigator: true).pop();
                          }
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.close, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'วันที่: $dateText',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...items.map((it) {
                    final doneNow = it.isDone == 1;
                    final isFuture = _isFutureDay(day);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEAEAEA)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${it.note.isNotEmpty ? it.note : 'งานดูแล'}  ${doneNow ? "(ทำแล้ว)" : "(ยังไม่ได้ทำ)"}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: doneNow ? kPrimaryGreen : Colors.red,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ต้น: ${_treeLabelById(it.treeId)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF6B6B6B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: doneNow,
                            activeColor: kPrimaryGreen,
                            onChanged: isFuture
                                ? null
                                : (v) async {
                                    await _toggleDone(it, v);
                                    if (Navigator.of(dialogCtx, rootNavigator: true).canPop()) {
                                      Navigator.of(dialogCtx, rootNavigator: true).pop();
                                    }
                                  },
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dayCell(DateTime day, {required bool selected, required bool outside}) {
    final bool due = _hasDue(day);
    final bool allDone = due ? _isAllDoneOnDay(day) : false;

    Color? fillColor;
    BoxBorder? border;

    if (due) {
      fillColor = allDone ? kPrimaryGreen : Colors.red;
    } else if (selected) {
      border = Border.all(color: kPrimaryGreen, width: 2);
    }

    final Color textColor = due
        ? Colors.white
        : selected
            ? kPrimaryGreen
            : (outside ? Colors.grey.shade400 : Colors.black87);

    return Center(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: fillColor ?? Colors.transparent,
          shape: BoxShape.circle,
          border: border,
        ),
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  


  // -----------------------------
  // ✅ Follow-up v1 (ยังไม่หาย) : สร้างแผนรอบถัดไป + พยายามแนะนำสารตัวถัดไป
  // -----------------------------

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _suggestNextChemicalLabel(String lastNote) {
    // lastNote มักเป็น "พ่นยา: XXXX"
    String s = lastNote.trim();
    final idx = s.indexOf(':');
    if (idx >= 0 && idx + 1 < s.length) {
      s = s.substring(idx + 1).trim();
    }

    // ตัวอย่าง-1A -> ตัวอย่าง-1B
    final mLetter = RegExp(r'^(.*?)([A-Z])$').firstMatch(s);
    if (mLetter != null) {
      final base = mLetter.group(1) ?? '';
      final ch = mLetter.group(2) ?? 'A';
      final code = ch.codeUnitAt(0);
      if (code >= 65 && code < 90) {
        final next = String.fromCharCode(code + 1);
        return (base + next).trim();
      }
    }

    // ...9 -> ...10
    final mNum = RegExp(r'^(.*?)(\d+)$').firstMatch(s);
    if (mNum != null) {
      final base = mNum.group(1) ?? '';
      final num = int.tryParse(mNum.group(2) ?? '') ?? 0;
      return (base + (num + 1).toString()).trim();
    }

    return "$s (ตัวถัดไป)".trim();
  }

  void _showSnackFloating(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 200), // ✅ ดันขึ้นให้พ้นแถบเมนู
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<List<dynamic>?> _apiGetList(String path, {String? token}) async {
    try {
      final url = _joinApi(_apiBaseUrl, path);
      final res = await http.get(Uri.parse(url), headers: _headers(token));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is List) return data;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _apiPostJson(String path, Map<String, dynamic> body,
      {String? token}) async {
    try {
      final url = _joinApi(_apiBaseUrl, path);
      final res = await http.post(
        Uri.parse(url),
        headers: _headersJson(token),
        body: jsonEncode(body),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) return data;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchDiagnosisHistoryMini(int diagnosisHistoryId) async {
    try {
      final token = await _readToken();
      final url = _joinApi(
        _apiBaseUrl,
        'diagnosis_history/read_diagnosis_history.php?id=$diagnosisHistoryId',
      );
      final res = await http.get(Uri.parse(url), headers: _headers(token));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) return data;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchLatestEpisodeByDiagnosisHistory(int diagnosisHistoryId) async {
    final token = await _readToken();
    final list = await _apiGetList(
      'treatment_episodes/read_treatment_episodes.php?diagnosis_history_id=$diagnosisHistoryId',
      token: token,
    );
    if (list == null || list.isEmpty) return null;
    final first = list.first;
    if (first is Map<String, dynamic>) return first;
    if (first is Map) return Map<String, dynamic>.from(first);
    return null;
  }

  Future<Map<String, dynamic>?> _selectNextChemicalAndGroup({
    required int riskLevelId,
    int? currentMoaGroupId,
    int? currentChemicalId,
  }) async {
    final token = await _readToken();

    // 1) หา order ของ MOA groups ตาม risk level
    final plan = await _apiGetList(
      'risk_level_moa_plan/read_risk_level_moa_plan.php?risk_level_id=$riskLevelId',
      token: token,
    );
    if (plan == null || plan.isEmpty) return null;

    List<Map<String, dynamic>> planRows = plan
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    int orderKey(Map<String, dynamic> m) =>
        _toInt(m['priority'] ?? m['order_index'] ?? m['order'] ?? 0);

    planRows.sort((a, b) => orderKey(a).compareTo(orderKey(b)));

    int moaIdOf(Map<String, dynamic> m) =>
        _toInt(m['moa_group_id'] ?? m['moaGroupId'] ?? m['id'] ?? 0);

    int curIdx = 0;
    if (currentMoaGroupId != null && currentMoaGroupId != 0) {
      final i = planRows.indexWhere((r) => moaIdOf(r) == currentMoaGroupId);
      if (i >= 0) curIdx = i;
    }

    // helper: โหลด chemicals ของ moa group
    Future<List<Map<String, dynamic>>?> loadChem(int moaGroupId) async {
      final rows = await _apiGetList(
        'risk_level_moa_chemicals/read_risk_level_moa_chemicals.php?risk_level_id=$riskLevelId&moa_group_id=$moaGroupId',
        token: token,
      );
      if (rows == null || rows.isEmpty) return null;
      final list = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      int ck(Map<String, dynamic> m) =>
          _toInt(m['priority'] ?? m['order_index'] ?? m['order'] ?? 0);
      list.sort((a, b) => ck(a).compareTo(ck(b)));
      return list;
    }

    // 2) พยายามเลือกสารตัวถัดไปใน group เดิมก่อน
    int selectedMoaId = moaIdOf(planRows[curIdx]);
    final chemsInCur = await loadChem(selectedMoaId);
    if (chemsInCur != null && chemsInCur.isNotEmpty) {
      int chemIdOf(Map<String, dynamic> m) =>
          _toInt(m['chemical_id'] ?? m['chemicalId'] ?? m['id'] ?? 0);

      int curChemIdx = -1;
      if (currentChemicalId != null && currentChemicalId != 0) {
        curChemIdx = chemsInCur.indexWhere((c) => chemIdOf(c) == currentChemicalId);
      }

      if (curChemIdx >= 0 && curChemIdx + 1 < chemsInCur.length) {
        final next = chemsInCur[curChemIdx + 1];
        return {
          'moa_group_id': selectedMoaId,
          'chemical_id': chemIdOf(next),
          'chemical_name': next['chemical_name'] ?? next['name'] ?? '',
          'moved_group': false,
        };
      }

      // ถ้าไม่มีตัวถัดไปใน group เดิม -> ไป group ถัดไป
      for (int step = 1; step <= planRows.length; step++) {
        final idx = (curIdx + step) % planRows.length;
        final moaId = moaIdOf(planRows[idx]);
        final chems = await loadChem(moaId);
        if (chems == null || chems.isEmpty) continue;
        final first = chems.first;
        return {
          'moa_group_id': moaId,
          'chemical_id': chemIdOf(first),
          'chemical_name': first['chemical_name'] ?? first['name'] ?? '',
          'moved_group': true,
        };
      }

      // fallback: เอาตัวแรกของ group เดิม
      final first = chemsInCur.first;
      return {
        'moa_group_id': selectedMoaId,
        'chemical_id': chemIdOf(first),
        'chemical_name': first['chemical_name'] ?? first['name'] ?? '',
        'moved_group': false,
      };
    }

    return null;
  }


  /// ✅ แสดงชื่อ “สารที่แนะนำครั้งถัดไป” (preview) ก่อนให้ผู้ใช้เลือกวันเริ่มรักษาใหม่
  /// - พยายามคำนวณจาก risk_level_moa_plan + risk_level_moa_chemicals + episode ล่าสุด
  /// - ถ้าดึงไม่สำเร็จ จะ fallback เป็นการเดาชื่อถัดไปจาก note เดิม
  Future<String> _previewNextChemicalLabelForFollowup({
    required int diagnosisHistoryId,
    required String lastNote,
  }) async {
    try {
      int riskLevelId = 0;
      int currentMoaGroupId = 0;
      int currentChemicalId = 0;

      final dh = await _fetchDiagnosisHistoryMini(diagnosisHistoryId);
      if (dh != null) {
        riskLevelId = _toInt(dh['risk_level_id'] ?? dh['riskLevelId'] ?? dh['disease_risk_level_id']);
      }

      final ep = await _fetchLatestEpisodeByDiagnosisHistory(diagnosisHistoryId);
      if (ep != null) {
        currentMoaGroupId = _toInt(ep['current_moa_group_id']);
        currentChemicalId = _toInt(ep['current_chemical_id']);
        final rlFromEp = _toInt(ep['risk_level_id']);
        if (riskLevelId == 0 && rlFromEp != 0) riskLevelId = rlFromEp;
      }

      Map<String, dynamic>? nextPick;
      if (riskLevelId != 0) {
        nextPick = await _selectNextChemicalAndGroup(
          riskLevelId: riskLevelId,
          currentMoaGroupId: currentMoaGroupId,
          currentChemicalId: currentChemicalId,
        );
      }

      final nameFromPick = (nextPick?['chemical_name'] ?? '').toString().trim();
      if (nameFromPick.isNotEmpty) return nameFromPick;

      return _suggestNextChemicalLabel(lastNote);
    } catch (_) {
      return _suggestNextChemicalLabel(lastNote);
    }
  }

  Future<bool> _createNextPlanAfterNotImproved(_FollowupCandidate c, DateTime nextStartDate) async {
    try {
      final token = await _readToken();
      if (token == null || token.isEmpty) return false;

      // ✅ กันซ้ำแบบง่าย: ถ้ามี reminder ในอนาคตของ diagnosis นี้อยู่แล้ว -> ไม่สร้างซ้ำ
      final hasFuture = _reminders.any((r) =>
          r.diagnosisHistoryId == c.diagnosisHistoryId &&
          _dateOnly(r.reminderDate).isAfter(_dateOnly(DateTime.now())));
      if (hasFuture) return true;

      // 1) ใช้ pattern วันที่จากแผนเดิม (offsets จากวันแรก)
      final dates = _reminders
          .where((r) => r.diagnosisHistoryId == c.diagnosisHistoryId)
          .map((r) => _dateOnly(r.reminderDate))
          .toSet()
          .toList()
        ..sort();
      final base = dates.isEmpty ? _dateOnly(nextStartDate) : dates.first;
      final offsets = (dates.isEmpty ? <int>[0] : dates.map((d) => d.difference(base).inDays).toList())
        ..sort();
      final uniqueOffsets = offsets.toSet().toList()..sort();

      // 2) ดึง riskLevel + episode เพื่อพยายามเลือก "สารตัวถัดไป"
      int riskLevelId = 0;
      int currentMoaGroupId = 0;
      int currentChemicalId = 0;
      int episodeId = 0;
      int groupAttemptNo = 1;
      int productAttemptNo = 1;

      final dh = await _fetchDiagnosisHistoryMini(c.diagnosisHistoryId);
      if (dh != null) {
        riskLevelId = _toInt(dh['risk_level_id'] ?? dh['riskLevelId'] ?? dh['disease_risk_level_id']);
      }

      final ep = await _fetchLatestEpisodeByDiagnosisHistory(c.diagnosisHistoryId);
      if (ep != null) {
        episodeId = _toInt(ep['episode_id'] ?? ep['id']);
        currentMoaGroupId = _toInt(ep['current_moa_group_id']);
        currentChemicalId = _toInt(ep['current_chemical_id']);
        groupAttemptNo = _toInt(ep['group_attempt_no']) == 0 ? 1 : _toInt(ep['group_attempt_no']);
        productAttemptNo = _toInt(ep['product_attempt_no']) == 0 ? 1 : _toInt(ep['product_attempt_no']);
        final rlFromEp = _toInt(ep['risk_level_id']);
        if (riskLevelId == 0 && rlFromEp != 0) riskLevelId = rlFromEp;
      }

      Map<String, dynamic>? nextPick;
      if (riskLevelId != 0) {
        nextPick = await _selectNextChemicalAndGroup(
          riskLevelId: riskLevelId,
          currentMoaGroupId: currentMoaGroupId,
          currentChemicalId: currentChemicalId,
        );
      }

      final nextMoaGroupId = _toInt(nextPick?['moa_group_id']);
      final nextChemicalId = _toInt(nextPick?['chemical_id']);
      final movedGroup = (nextPick?['moved_group'] == true);

      // label สำหรับ note (ให้เห็นชัดแม้ join ชื่อสารไม่ได้)
      String label;
      final nameFromPick = (nextPick?['chemical_name'] ?? '').toString().trim();
      if (nameFromPick.isNotEmpty) {
        label = nameFromPick;
      } else {
        label = _suggestNextChemicalLabel(c.lastNote);
      }

      // 3) อัปเดต episode ล่าสุด (ถ้ามี) ให้ชี้ไปสารตัวถัดไป + start_spray_date ใหม่
      if (episodeId != 0) {
        int newGroupAttemptNo = groupAttemptNo;
        int newProductAttemptNo = productAttemptNo;

        if (nextChemicalId != 0) {
          if (movedGroup) {
            newGroupAttemptNo = groupAttemptNo + 1;
            newProductAttemptNo = 1;
          } else {
            newProductAttemptNo = productAttemptNo + 1;
          }
        }

        await _apiPostJson(
          'treatment_episodes/update_treatment_episodes.php',
          {
            'episode_id': episodeId,
            'start_spray_date': _ymd(_dateOnly(nextStartDate)),
            'current_moa_group_id': nextMoaGroupId == 0 ? null : nextMoaGroupId,
            'current_chemical_id': nextChemicalId == 0 ? null : nextChemicalId,
            'group_attempt_no': newGroupAttemptNo,
            'product_attempt_no': newProductAttemptNo,
            'spray_round_no': 0,
            'last_evaluation': 'not_improved',
            'status': 'active',
          },
          token: token,
        );
      }

      // 4) สร้าง reminders รอบใหม่
      final treeIdInt = int.tryParse(c.treeId) ?? 0;
      if (treeIdInt == 0) return false;

      int round = 1;
      for (final off in uniqueOffsets) {
        final d = _dateOnly(nextStartDate.add(Duration(days: off)));
        final ymd = _ymd(d);

        final body = <String, dynamic>{
          'tree_id': treeIdInt,
          'reminder_date': ymd,
          'note': 'พ่นยา: $label',
          'is_done': 0,
          'diagnosis_history_id': c.diagnosisHistoryId,
          'start_spray_date': _ymd(_dateOnly(nextStartDate)),
          'spray_round_no': round,
          'spray_total_rounds': uniqueOffsets.length,
        };

        if (nextMoaGroupId != 0) body['moa_group_id'] = nextMoaGroupId;
        if (nextChemicalId != 0) body['chemical_id'] = nextChemicalId;

        final resp = await _apiPostJson('care_reminders/create_care_reminders.php', body, token: token);
        if (resp == null || resp['success'] != true) {
          // ถ้า fail บางรายการ ให้หยุดทันทีเพื่อไม่ให้ข้อมูลเพี้ยน
          return false;
        }
        round++;
      }

      // ✅ รีโหลดเดือนของวันเริ่มใหม่ เพื่อให้เห็นแผนทันที
      if (!mounted) return true;
      setState(() {
        _focusedDay = _dateOnly(nextStartDate);
        _selectedDate = _dateOnly(nextStartDate);
      });
      await _loadRemindersForMonth(_focusedDay);

      return true;
    } catch (_) {
      return false;
    }
  }

  // =========================================
  // ✅ Dialog ติดตามผล (ซ้อนบนหน้า Home)
  // =========================================
  String _dmy(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<_FollowupDialogResult?> _showFollowupDialog({
    required String treeLabel,
    required DateTime lastPlanDate,
    required int evaluationAfterDays,
    required String lastNote,
    required int diagnosisHistoryId,
  }) async {
    if (!mounted) return null;

    return showDialog<_FollowupDialogResult>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // title + close
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'ติดตามผลการรักษา',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(dialogCtx),
                          borderRadius: BorderRadius.circular(24),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close, size: 22),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // info card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE6E6E6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            treeLabel,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'แผนสิ้นสุดวันที่: ${_dmy(lastPlanDate)}',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ผ่านไป $evaluationAfterDays วันแล้ว',
                            style: const TextStyle(fontSize: 14, color: Colors.black54),
                          ),
                          if (lastNote.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              lastNote.trim(),
                              style: const TextStyle(fontSize: 13, color: Colors.black54),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),
                    const Text(
                      'ยาที่ใช้รักษาทำให้โรคหายหรือยัง?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(
                                dialogCtx,
                                const _FollowupDialogResult.cured(),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            child: const Text(
                              'หายแล้ว',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                                                            // ✅ แสดง “สารตัวถัดไป” ให้ผู้ใช้เห็นก่อนเลือกวันเริ่มรักษา
                              final nextLabel = await _previewNextChemicalLabelForFollowup(
                                diagnosisHistoryId: diagnosisHistoryId,
                                lastNote: lastNote,
                              );

                              final goPick = await showDialog<bool>(
                                context: dialogCtx,
                                useRootNavigator: true,
                                barrierDismissible: true,
                                builder: (ctx2) {
                                  return Dialog(
                                    backgroundColor: Colors.transparent,
                                    insetPadding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 24),
                                        child: Container(
                                          width: double.infinity,
                                          constraints: const BoxConstraints(maxWidth: 560),
                                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(22),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Color(0x33000000),
                                                blurRadius: 18,
                                                offset: Offset(0, 10),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  const Text(
                                                    'สารที่แนะนำครั้งถัดไป',
                                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                                                  ),
                                                  IconButton(
                                                    onPressed: () => Navigator.pop(ctx2, false),
                                                    icon: const Icon(Icons.close),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Container(
                                                padding: const EdgeInsets.all(14),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF5F5F5),
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(color: const Color(0xFFE0E0E0)),
                                                ),
                                                child: Text(
                                                  nextLabel,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w800,
                                                    color: kPrimaryGreen,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 14),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: OutlinedButton(
                                                      onPressed: () => Navigator.pop(ctx2, false),
                                                      style: OutlinedButton.styleFrom(
                                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(26),
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        'ยกเลิก',
                                                        style: TextStyle(fontWeight: FontWeight.w800),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: ElevatedButton(
                                                      onPressed: () => Navigator.pop(ctx2, true),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: kPrimaryGreen,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(26),
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        'เลือกวันที่เริ่มรักษา',
                                                        style: TextStyle(fontWeight: FontWeight.w800),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );

                              if (goPick != true) return;

                              // ✅ เลือกวันด้วย "ปฏิทินของไฟล์ select_start_spray_date_page.dart"
                              final picked = await Navigator.push<DateTime>(
                                dialogCtx,
                                MaterialPageRoute(
                                  builder: (_) => SelectStartSprayDatePage(
                                    initialDate: DateTime.now(),
                                    minDate: DateTime.now(),
                                  ),
                                ),
                              );

if (picked == null) return; // ผู้ใช้กดย้อนกลับ/ยกเลิก

                              final pickedOnly = _dateOnly(picked);
                              if (!mounted) return;

                              Navigator.pop(
                                dialogCtx,
                                _FollowupDialogResult.notCured(pickedOnly),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB71C1C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            child: const Text(
                              'ยังไม่หาย',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCongratsDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        Widget dot({double size = 10, double opacity = 1}) => Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: kPrimaryGreen.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 120,
                      child: Stack(
                        children: [
                          Positioned(top: 8, left: 24, child: dot(size: 10)),
                          Positioned(top: 22, left: 88, child: dot(size: 8, opacity: .25)),
                          Positioned(top: 6, left: 160, child: dot(size: 10)),
                          Positioned(top: 26, left: 210, child: dot(size: 8)),
                          Positioned(top: 14, right: 120, child: dot(size: 8, opacity: .25)),
                          Positioned(top: 10, right: 56, child: dot(size: 10)),
                          Positioned(top: 26, right: 24, child: dot(size: 10)),
                          Center(
                            child: Icon(
                              Icons.celebration,
                              color: kPrimaryGreen,
                              size: 54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'ยินดีด้วย 🎉',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'โรคหายแล้ว ขอบคุณที่ดูแลสวนส้มของคุณอย่าง\nสม่ำเสมอ',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Text(
                          'ตกลง',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }


// =========================================
  // ✅ Follow-up: ครบแผน + 5 วัน -> เด้งถาม
  // =========================================
  void _scheduleFollowupCheck() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptFollowup();
    });
  }

  List<_FollowupCandidate> _buildFollowupCandidates() {
    // group reminders by diagnosis_history_id
    final Map<int, List<_ReminderRow>> byDh = {};
    for (final r in _reminders) {
      final dh = r.diagnosisHistoryId;
      if (dh == null || dh <= 0) continue;
      byDh.putIfAbsent(dh, () => []);
      byDh[dh]!.add(r);
    }

    final List<_FollowupCandidate> out = [];

    for (final entry in byDh.entries) {
      final dhId = entry.key;
      final items = entry.value;
      if (items.isEmpty) continue;

      // ต้องทำครบทั้งหมดก่อน
      final allDone = items.every((x) => x.isDone == 1);
      if (!allDone) continue;

      // วันสุดท้ายของแผน
      items.sort((a, b) => a.reminderDate.compareTo(b.reminderDate));
      final lastDate = items.last.reminderDate;

      // เอา note ของวันสุดท้าย (ช่วยบอกสารล่าสุด)
      final lastSameDay = items.where((x) => _ymd(x.reminderDate) == _ymd(lastDate)).toList();
      String lastNote = '';
      if (lastSameDay.isNotEmpty) {
        lastNote = lastSameDay.last.note.trim();
      }

      out.add(
        _FollowupCandidate(
          diagnosisHistoryId: dhId,
          treeId: items.last.treeId,
          lastPlanDate: lastDate,
          lastNote: lastNote,
        ),
      );
    }

    // เรียงตาม follow-up date (เก่าก่อน)
    out.sort((a, b) {
      final af = a.lastPlanDate.add(const Duration(days: _kFollowupDaysAfterPlan));
      final bf = b.lastPlanDate.add(const Duration(days: _kFollowupDaysAfterPlan));
      return af.compareTo(bf);
    });

    return out;
  }

  /// ✅ อ่านค่า evaluation_after_days (จำนวนวันหลังแผนสิ้นสุดก่อนถามติดตามผล) จาก DB
  /// fallback = 5
  Future<int> _fetchEvaluationAfterDays(int diagnosisHistoryId) async {
    const int fallback = 5;

    try {
      final token = await _readToken();
      if (token == null) return fallback;

      final uri = Uri.parse(_joinApi(
        _apiBaseUrl,
        '/diagnosis_history/read_diagnosis_history.php?diagnosis_history_id=$diagnosisHistoryId',
      ));

      final res = await http.get(uri, headers: {
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      });

      if (res.statusCode != 200) return fallback;

      final decoded = jsonDecode(res.body);
      dynamic data = decoded;
      if (decoded is Map) data = decoded['data'] ?? decoded;

      Map<String, dynamic>? row;
      if (data is List && data.isNotEmpty && data.first is Map) {
        row = Map<String, dynamic>.from(data.first as Map);
      } else if (data is Map) {
        row = Map<String, dynamic>.from(data);
      }
      if (row == null) return fallback;

      final v = _toInt(row['evaluation_after_days']);
      if (v > 0) return v;

      final d = _toInt(row['days']);
      if (d > 0) return d;

      return fallback;
    } catch (_) {
      return fallback;
    }
  }


  Future<void> _checkAndPromptFollowup() async {
    if (!mounted) return;
    if (_followupPrompting) return;

    final today = _dateOnly(DateTime.now());
    final candidates = _buildFollowupCandidates();
    if (candidates.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    for (final c in candidates) {
      final evalDays = await _fetchEvaluationAfterDays(c.diagnosisHistoryId);
      final followupDate = _dateOnly(c.lastPlanDate.add(Duration(days: evalDays)));
      if (today.isBefore(followupDate)) continue;

      final answeredKey = 'followup_v1_answered_${c.diagnosisHistoryId}_${c.lastKey}';
      final snoozeKey = 'followup_v1_snooze_${c.diagnosisHistoryId}_${c.lastKey}';

      // ถ้าตอบไปแล้ว ไม่ถามซ้ำ
      if (prefs.getBool(answeredKey) == true) continue;

      // ถ้ากดปิด/ยกเลิกไว้ ให้เลื่อนไปถามวันถัดไป
      final snoozeUntil = prefs.getString(snoozeKey) ?? '';
      if (snoozeUntil.isNotEmpty) {
        final dt = DateTime.tryParse(snoozeUntil);
        if (dt != null && !today.isAfter(_dateOnly(dt))) {
          continue;
        }
      }

      _followupPrompting = true;

      try {
        final treeLabel = _treeLabelById(c.treeId);

        final result = await _showFollowupDialog(
          treeLabel: treeLabel,
          lastPlanDate: c.lastPlanDate,
          evaluationAfterDays: evalDays,
          lastNote: c.lastNote,
          diagnosisHistoryId: c.diagnosisHistoryId,
        );

        // ถ้าปิด/ยกเลิก -> snooze 1 วัน
        if (result == null) {
          final nextDay = today.add(const Duration(days: 1));
          await prefs.setString(snoozeKey, _ymd(nextDay));
          return;
        }

        // บันทึกว่า “ตอบแล้ว”
        await prefs.setBool(answeredKey, true);
        await prefs.setString(
          'followup_v1_result_${c.diagnosisHistoryId}_${c.lastKey}',
          result.cured ? 'cured' : 'not_cured',
        );

        if (result.cured) {
          if (!mounted) return;
          await _showCongratsDialog();
          return;
        }

        // not cured -> เก็บวันเริ่มรักษาใหม่ + flag ให้หน้าอื่นอ่านได้
        if (result.nextStartDate != null) {
          final ymd = _ymd(result.nextStartDate!);

          await prefs.setString(
            'followup_v1_next_start_${c.diagnosisHistoryId}_${c.lastKey}',
            ymd,
          );

          // ✅ เผื่อไฟล์อื่นของคุณอ่าน key นี้อยู่แล้ว
          await prefs.setString('start_spray_date', ymd);

          // ✅ เก็บแบบผูกต้น (ไว้ใช้ต่อได้)
          await prefs.setString('start_spray_date_tree_${c.treeId}', ymd);

          // trigger refresh ให้หน้าอื่น ๆ
          await prefs.setInt('app_refresh_ts_v1', DateTime.now().millisecondsSinceEpoch);

          final ok = await _createNextPlanAfterNotImproved(c, result.nextStartDate!);

          if (mounted) {
            if (ok) {
              _showSnackFloating('สร้างแผนรอบถัดไปแล้ว: $ymd');
            } else {
              _showSnackFloating('', isError: true);
            }
          }
        }

        return;
      } catch (_) {
        return;
      } finally {
        _followupPrompting = false;
      }
    }
  }

  // ==========================================================
  // ✅ build (UI เดิม)
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    final double calendarHeight = MediaQuery.of(context).size.height * 0.45;
    final int _weeks = _weeksInMonth(_focusedDay);
    final double _calendarRowHeight = (_weeks >= 6) ? 44 : 52;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'หน้าหลัก',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3A2A18),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SettingPage(
                            initialUsername: widget.username,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const CircleAvatar(
                        radius: 20,
                        backgroundColor: Color(0xFFE0E0E0),
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'ดูสภาพอากาศวันนี้ก่อนดูแลสวนส้มของคุณ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF8A6E55),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kPrimaryGreen,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.wb_sunny_rounded, color: Colors.white, size: 40),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'พยากรณ์อากาศวันนี้',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'อุณหภูมิ 28°C  ·  ความชื้น 65%\n'
                            'สภาพอากาศเหมาะสำหรับการตรวจโรคและดูแลสวนส้ม',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w400, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('ดี', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ปฏิทินสวนส้ม',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A2A18),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'แตะวันที่เพื่อดูงานรักษา ',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: calendarHeight,
                child: Card(
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: TableCalendar(
                      firstDay: DateTime.now().subtract(const Duration(days: 365)),
                      lastDay: DateTime.now().add(const Duration(days: 365 * 3)),
                      focusedDay: _focusedDay,
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                        leftChevronIcon: Icon(Icons.chevron_left, color: Color(0xFF6F4E37)),
                        rightChevronIcon: Icon(Icons.chevron_right, color: Color(0xFF6F4E37)),
                      ),
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(fontWeight: FontWeight.w400),
                        weekendStyle: TextStyle(fontWeight: FontWeight.w400),
                      ),
                      selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
                      calendarStyle: const CalendarStyle(
                        isTodayHighlighted: false,
                        outsideDaysVisible: true,
                      ),
                      rowHeight: _calendarRowHeight,
                      daysOfWeekHeight: 28,
                      onPageChanged: (focusedDay) async {
                        setState(() => _focusedDay = focusedDay);
                        await _loadRemindersForMonth(focusedDay);
                      },
                      onDaySelected: (selectedDay, focusedDay) async {
                        setState(() {
                          _selectedDate = selectedDay;
                          _focusedDay = focusedDay;
                        });
                        if (_hasDue(selectedDay)) {
                          await _openDueDialog(selectedDay);
                        }
                      },
                      calendarBuilders: CalendarBuilders(
                        defaultBuilder: (context, day, focusedDay) {
                          final selected = isSameDay(day, _selectedDate);
                          return _dayCell(day, selected: selected, outside: false);
                        },
                        selectedBuilder: (context, day, focusedDay) =>
                            _dayCell(day, selected: true, outside: false),
                        todayBuilder: (context, day, focusedDay) {
                          final selected = isSameDay(day, _selectedDate);
                          return _dayCell(day, selected: selected, outside: false);
                        },
                        outsideBuilder: (context, day, focusedDay) {
                          final selected = isSameDay(day, _selectedDate);
                          return _dayCell(day, selected: selected, outside: true);
                        },
                      ),
                    ),
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
