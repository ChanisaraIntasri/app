import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

// Import หน้า Setting
import 'setting.dart';

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

// ... (ส่วน Class _TreeLite, _ReminderRow และ _HomePageState ตั้งแต่บรรทัด 72 ถึง 706 เหมือนเดิม ไม่ต้องลบ) ...
// เพื่อความกระชับ ผมจะข้ามส่วน logic เดิมไป และมาแก้ที่ method build เลยนะครับ

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

class _HomePageState extends State<HomePage> {
  // ------------ state ------------
  List<_TreeLite> _trees = [];
  Map<String, int> _treeNoById = {};
  
  // ... (ตัวแปร state เดิมทั้งหมด) ...
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  bool _loadingReminders = false;
  String _lastRefreshStamp = '';
  String _apiBaseUrl = API_BASE;
  Map<String, dynamic> _lastDiagnosisByTreeId = {};
  final List<_ReminderRow> _reminders = [];
  final Map<String, List<_ReminderRow>> _remindersByDay = {};
  Timer? _watcher;

  // ✅ TableCalendar บางเดือน (เช่น March 2026) จะมี 6 แถวของวัน
  // แต่เรา constrain ความสูงปฏิทินไว้คงที่ (calendarHeight) ทำให้เดือนที่มี 6 แถว
  // เกิด RenderFlex overflow ได้ จึงคำนวณจำนวนแถวของเดือนนั้น ๆ เพื่อปรับ rowHeight
  int _weeksInMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final daysInMonth = last.day;

    // Dart: Monday=1..Sunday=7 และเราตั้ง startingDayOfWeek เป็น Monday
    const startWeekday = DateTime.monday; // 1
    int offset = first.weekday - startWeekday;
    offset = (offset % 7 + 7) % 7; // ให้เป็น 0..6 เสมอ

    final totalCells = offset + daysInMonth;
    return (totalCells / 7).ceil(); // 4..6
  }

  // ... (Methods เดิมทั้งหมด: _ensureTreeNoIndex, _treeLabelById, _readToken, _refreshApiBaseFromPrefs, _loadTreesFromApi, _loadRemindersForMonth ฯลฯ) ...
  // (ผมละส่วน logic ไว้ตามคำขอว่าห้ามลบ แต่เวลาคุณ copy ไปใช้ ให้คง logic เดิมไว้ทั้งหมดนะครับ)
  
  void _ensureTreeNoIndex() {
      // (Logic เดิม)
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

  // (ขออนุญาตข้าม method อื่นๆ มาที่ build เลยนะครับ เพื่อประหยัดพื้นที่ แต่โค้ดเดิมของคุณต้องอยู่นะครับ)
  String _treeLabelById(String treeId) {
    // (Logic เดิม)
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
      
  String _normKey(String s) => s.trim().toLowerCase();
  
  // ... (Methods helper อื่นๆ ใส่ไว้เหมือนเดิม) ...
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
      // (Logic เดิม)
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
      // (Logic เดิม)
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
     // (Logic เดิม)
     if (_isFutureDay(r.reminderDate)) return;
    if (!done) return; 

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
        }
      }
    } catch (_) {}
  }
  
  // ... (Method _openDueDialog และ _dayCell เหมือนเดิม) ...
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
                            onChanged: (isFuture || doneNow)
                                ? null
                                : (v) async {
                                    if (!v) return;
                                    await _toggleDone(it, true);
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

  // ==========================================================
  // ✅ แก้ไขส่วน build เพื่อเพิ่มปุ่ม Profile (Setting) ตรงนี้
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
              // ✅ ปรับ header จาก Text ธรรมดา เป็น Row
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
                  // ✅ ปุ่ม Profile ไอคอนกลมๆ
                  InkWell(
                    onTap: () {
                      // ไปหน้า Setting
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
                      padding: const EdgeInsets.all(4), // ขอบขาวรอบๆ
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
              
              // ... (ส่วน Weather Widget และ Calendar Widget เหมือนเดิมเป๊ะ) ...
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