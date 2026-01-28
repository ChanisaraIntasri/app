import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

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

  // ✅ FIX: ไม่บังคับส่ง trees (แก้ error main_nav.dart const HomePage())
  const HomePage({super.key, this.trees = const [], this.onTreesUpdated});

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

class _HomePageState extends State<HomePage> {
  // ------------ state ------------
  late List<CitrusTreeRecord> _trees;

  // ✅ map tree_id -> ลำดับต้นที่ (ต้นที่ 1,2,3...) เพื่อแสดงแบบที่ผู้ใช้เข้าใจ
  Map<String, int> _treeNoById = {};

  void _ensureTreeNoIndex() {
    // ถ้ามี list ต้น (มาจากหน้า Share/เพิ่มต้น) ใช้ลำดับตาม list นี้เลย
    if (_trees.isNotEmpty) {
      _treeNoById = {
        for (int i = 0; i < _trees.length; i++) _trees[i].id.toString(): i + 1,
      };
      return;
    }

    // ถ้าไม่มี list ต้นส่งเข้ามา ให้สร้างลำดับจาก treeId ที่พบใน reminders
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

  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  bool _loadingReminders = false;
  String _lastRefreshStamp = '';

  // key: tree_id -> {disease,severity,diagnosedAt,...}
  Map<String, dynamic> _lastDiagnosisByTreeId = {};

  // ---------- tree display helper ----------
  // แสดง "ชื่อต้น" ถ้ามี, ไม่งั้นแสดง "ต้นที่ N" (ไม่แสดง id ตรง ๆ)
  String _treeLabelById(String treeId) {
    final tid = treeId.toString().trim();

    // 1) ถ้ามี list ต้นและมีชื่อ → ใช้ชื่อ
    if (_trees.isNotEmpty) {
      final idx = _trees.indexWhere((t) => t.id.toString() == tid);
      if (idx >= 0) {
        final n = _s(_trees[idx].name);
        if (n.isNotEmpty) {
          // ถ้าชื่อดูเหมือน "ต้น 70" หรือเป็นตัวเลขล้วน ๆ → ไม่เอา (ถือว่าเป็น id)
          final norm = n.replaceAll(RegExp(r'\s+'), ' ').trim();
          final looksLikeId =
              RegExp(r'^(ต้น\s*)?\d+$').hasMatch(norm) || norm == 'ต้น $tid';
          if (!looksLikeId) return n;
        }

        // ไม่มีชื่อ/ชื่อเป็น id → ใช้ลำดับใน list
        return 'ต้นที่ ${idx + 1}';
      }
    }

    // 2) ถ้าไม่พบใน list → ใช้ mapping จาก reminders เพื่อเป็น "ต้นที่ N"
    _ensureTreeNoIndex();
    final no = _treeNoById[tid];
    if (no != null) return 'ต้นที่ $no';

    // 3) fallback สุดท้าย (กันพัง)
    return tid.isNotEmpty ? 'ต้นที่ ?' : 'ไม่ทราบชื่อต้น';
  }

  // reminders ของช่วงเดือนที่กำลังโฟกัส
  final List<_ReminderRow> _reminders = [];

  // map dateKey -> reminders list
  final Map<String, List<_ReminderRow>> _remindersByDay = {};

  Timer? _watcher;

  // ------------ helpers ------------
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

  String _normKey(String s) => s.trim().toLowerCase();

  String _severityToCode(String s) {
    final t = _normKey(s);
    if (t.contains('high') || t.contains('สูง') || t.contains('รุนแรง')) return 'high';
    if (t.contains('medium') || t.contains('กลาง') || t.contains('ปานกลาง')) return 'medium';
    if (t.contains('low') || t.contains('ต่ำ') || t.contains('น้อย')) return 'low';
    return t;
  }

  // ------------ init ------------
  @override
  void initState() {
    super.initState();
    _trees = List<CitrusTreeRecord>.from(widget.trees);

    _reloadFromPrefs();
    _loadRemindersForMonth(_focusedDay);
    _startRefreshWatcher();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trees != oldWidget.trees) {
      _trees = List<CitrusTreeRecord>.from(widget.trees);
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
      final ts = prefs.getInt('app_refresh_ts_v1')?.toString() ?? '';
      if (ts.isNotEmpty && ts != _lastRefreshStamp) {
        _lastRefreshStamp = ts;
        await _reloadFromPrefs();
        await _loadRemindersForMonth(_focusedDay);
      }
    });
  }

  Future<void> _reloadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('tree_last_diagnosis_v1') ?? '{}';
      final decoded = jsonDecode(raw);
      if (!mounted) return;
      setState(() {
        // ✅ FIX: แปลง Map<dynamic,dynamic> -> Map<String,dynamic>
        if (decoded is Map) {
          final mapped = decoded.map((k, v) => MapEntry(k.toString(), v));
          _lastDiagnosisByTreeId = Map<String, dynamic>.from(mapped);
        } else {
          _lastDiagnosisByTreeId = <String, dynamic>{};
        }
      });

      // หลังจากโหลด prefs → rebuild index จาก reminders ที่มีอยู่
      _rebuildDueIndexFromReminders();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lastDiagnosisByTreeId = {};
      });
      _rebuildDueIndexFromReminders();
    }
  }

  // ---------- reminders load/build ----------
  Future<void> _loadRemindersForMonth(DateTime focus) async {
    if (_loadingReminders) return;
    _loadingReminders = true;

    try {
      final token = await _readToken();
      if (token == null || token.isEmpty) {
        _loadingReminders = false;
        return;
      }

      final first = DateTime(focus.year, focus.month, 1);
      final last = DateTime(focus.year, focus.month + 1, 0);

      final uri = Uri.parse(
        _joinApi(
          API_BASE,
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
        final note = _s(m['note']);

        final rawDate = _s(m['reminder_date']);
        DateTime? dt;
        if (rawDate.isNotEmpty) {
          // รองรับทั้ง "yyyy-MM-dd" และ "yyyy-MM-dd HH:mm:ss"
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

      if (!mounted) return;
      setState(() {
        _reminders
          ..clear()
          ..addAll(rows);
      });

      _rebuildDueIndexFromReminders();
    } catch (_) {
      // ignore
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

  // ✅ อนุญาตให้ติ๊กได้เฉพาะ "วันนี้" หรือ "วันย้อนหลัง" เท่านั้น (ห้ามวันอนาคต)
  bool _isFutureDay(DateTime day) {
    final today = _dateOnly(DateTime.now());
    return _dateOnly(day).isAfter(today);
  }

  Future<void> _toggleDone(_ReminderRow r, bool done) async {
    // ✅ กันติ๊กวันอนาคต + กันย้อนกลับเป็นยังไม่ทำ
    if (_isFutureDay(r.reminderDate)) return;
    if (!done) return; // ห้ามย้อนกลับเป็น "ยังไม่ได้ทำ"

    final token = await _readToken();
    if (token == null || token.isEmpty) return;

    // update DB
    try {
      final uri = Uri.parse(_joinApi(API_BASE, '/care_reminders/update_care_reminders.php'));
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
        // update local
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
                                    // ✅ 1) ถ้าติ๊กว่า "ทำแล้ว" แล้ว ห้ามย้อนกลับเป็น "ยังไม่ได้ทำ"
                                    // ✅ 2) ถ้าเป็น "วันอนาคต" ห้ามติ๊ก
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

  @override
  Widget build(BuildContext context) {
    final double calendarHeight = MediaQuery.of(context).size.height * 0.45;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'หน้าหลัก',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A2A18),
                ),
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
                      rowHeight: 52,
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
