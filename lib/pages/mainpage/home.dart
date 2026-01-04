import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

// ✅ model
import 'package:flutter_application_1/models/citrus_tree_record.dart';

const kPrimaryGreen = Color(0xFF005E33);
const kPageBg = Color.fromARGB(255, 251, 251, 251);
const kCalendarCardBg = Colors.white;

/// key "yyyy-MM-dd"
String _dateKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _diagnosedAt(CitrusTreeRecord t) =>
    t.diagnosedAt ?? t.lastScanAt ?? t.createdAt;

/// 1 กลุ่ม = โรคเดียวกัน + severity เท่ากัน
class _Group {
  final String key; // disease__severity
  final String disease;
  final String severity;
  final String taskName;
  final int everyDays;
  final int totalTimes;
  final DateTime startDate;
  final List<CitrusTreeRecord> trees;

  const _Group({
    required this.key,
    required this.disease,
    required this.severity,
    required this.taskName,
    required this.everyDays,
    required this.totalTimes,
    required this.startDate,
    required this.trees,
  });
}

/// งานใน "วันหนึ่ง"
class _DueItem {
  final DateTime date;
  final _Group group;

  const _DueItem({required this.date, required this.group});

  bool isDoneAllTrees() {
    final k = _dateKey(date);
    return group.trees.every((t) => t.treatmentDoneDates.contains(k));
  }
}

class HomePage extends StatefulWidget {
  final List<CitrusTreeRecord>? trees;
  final ValueChanged<List<CitrusTreeRecord>>? onTreesUpdated;

  const HomePage({super.key, this.trees, this.onTreesUpdated});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  late List<CitrusTreeRecord> _trees;
  Map<String, List<_DueItem>> _dueIndex = {};

  @override
  void initState() {
    super.initState();

    // ✅ ลบ DEMO: ใช้ข้อมูลจริงเท่านั้น (ถ้าไม่มีข้อมูล = ว่าง)
    _trees = List<CitrusTreeRecord>.from(widget.trees ?? const []);
    _rebuildIndex();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ ถ้า parent ส่ง trees ใหม่มา ให้ sync
    if (widget.trees != oldWidget.trees) {
      _trees = List<CitrusTreeRecord>.from(widget.trees ?? const []);
      _rebuildIndex();
    }
  }

  void _rebuildIndex() {
    final groups = _buildGroups(_trees);

    final Map<String, List<_DueItem>> index = {};
    for (final g in groups) {
      final occurrences = _generateOccurrences(
        start: g.startDate,
        everyDays: g.everyDays,
        totalTimes: g.totalTimes,
      );

      for (final d in occurrences) {
        final k = _dateKey(d);
        index.putIfAbsent(k, () => []);
        index[k]!.add(_DueItem(date: d, group: g));
      }
    }

    _dueIndex = index;
    if (mounted) setState(() {});
  }

  List<_Group> _buildGroups(List<CitrusTreeRecord> trees) {
    final filtered = trees
        .where((t) => t.disease.trim().isNotEmpty && t.disease.trim() != '-')
        .toList();

    final Map<String, List<CitrusTreeRecord>> map = {};
    for (final t in filtered) {
      final disease = t.disease.trim().toLowerCase();
      final severity = (t.severity).trim().toLowerCase();
      final key = '${disease}__${severity}';
      map.putIfAbsent(key, () => []);
      map[key]!.add(t);
    }

    final List<_Group> out = [];
    map.forEach((key, list) {
      final base = list.first;

      final taskName =
          base.treatmentTaskName.trim().isEmpty ? 'พ่นยา' : base.treatmentTaskName.trim();

      final everyDays = base.treatmentEveryDays; // ✅ ไม่ใส่ค่าเดาเอง

      // ✅ ไม่บังคับ 4 ครั้งแล้ว และไม่เดาเอง
      final totalTimes = base.treatmentTotalTimes;

      final start = list
          .map(_diagnosedAt)
          .map(_dateOnly)
          .reduce((a, b) => a.isBefore(b) ? a : b);

      final parts = key.split('__');
      final disease = parts.isNotEmpty ? parts[0] : base.disease;
      final severity = parts.length > 1 ? parts[1] : base.severity;

      out.add(
        _Group(
          key: key,
          disease: disease,
          severity: severity,
          taskName: taskName,
          everyDays: everyDays,
          totalTimes: totalTimes,
          startDate: start,
          trees: list,
        ),
      );
    });

    return out;
  }

  List<DateTime> _generateOccurrences({
    required DateTime start,
    required int everyDays,
    required int totalTimes,
  }) {
    // ✅ ถ้า API ยังไม่ส่ง everyDays/totalTimes มา -> ไม่สร้างวันรักษา
    if (everyDays <= 0 || totalTimes <= 0) return const [];

    final s = _dateOnly(start);
    final List<DateTime> out = [];
    for (int i = 0; i < totalTimes; i++) {
      out.add(s.add(Duration(days: everyDays * i)));
    }
    return out;
  }

  List<_DueItem> _dueItemsOf(DateTime day) => _dueIndex[_dateKey(day)] ?? const [];
  bool _hasDue(DateTime day) => _dueItemsOf(day).isNotEmpty;

  bool _isAllDoneOnDay(DateTime day) {
    final items = _dueItemsOf(day);
    if (items.isEmpty) return false;
    return items.every((it) => it.isDoneAllTrees());
  }

  void _setDoneForGroup({
    required _Group group,
    required DateTime day,
    required bool done,
  }) {
    final k = _dateKey(day);

    final updated = _trees.map((t) {
      final isInGroup = group.trees.any((x) => x.id == t.id);
      if (!isInGroup) return t;

      final nextDone = Set<String>.from(t.treatmentDoneDates);
      if (done) {
        nextDone.add(k);
      } else {
        nextDone.remove(k);
      }
      return t.copyWith(treatmentDoneDates: nextDone);
    }).toList();

    setState(() => _trees = updated);

    widget.onTreesUpdated?.call(List<CitrusTreeRecord>.from(_trees));
    _rebuildIndex();
  }

  // ✅ FIX: สวิตช์ใน dialog ต้องเปลี่ยนทันที + กดแล้วปิด dialog กลับหน้าหลักเลย
  Future<void> _openDueDialog(DateTime day) async {
    if (_dueItemsOf(day).isEmpty) return;
    if (!mounted) return;

    final dateText = '${day.day}/${day.month}/${day.year}';

    final Map<String, bool> tempSwitch = {};

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final items = _dueItemsOf(day);

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
                        final key = '${it.group.key}__${_dateKey(it.date)}';
                        final bool doneNow = tempSwitch[key] ?? it.isDoneAllTrees();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F7F7),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFEAEAEA)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${it.group.taskName}  ${doneNow ? "(ทำแล้ว)" : "(ยังไม่ได้ทำ)"}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: doneNow ? kPrimaryGreen : Colors.red,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: doneNow,
                                    activeColor: kPrimaryGreen,
                                    onChanged: (v) {
                                      setDialogState(() => tempSwitch[key] = v);
                                      _setDoneForGroup(group: it.group, day: it.date, done: v);

                                      Future.delayed(const Duration(milliseconds: 120), () {
                                        if (Navigator.of(dialogCtx, rootNavigator: true).canPop()) {
                                          Navigator.of(dialogCtx, rootNavigator: true).pop();
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'โรค: ${it.group.disease}  •  ความรุนแรง: ${it.group.severity}',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'ต้นที่ต้องรักษา:',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: it.group.trees
                                    .map(
                                      (t) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(color: const Color(0xFFE1E1E1)),
                                        ),
                                        child: Text(
                                          t.name,
                                          style: const TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    )
                                    .toList(),
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
      },
    );
  }

  /// ✅ ตามที่ขอ:
  /// - วันต้องรักษา = วงกลมเต็ม แดง / ถ้าทำแล้ว = เขียว
  /// - วันปกติที่เลือก = วงขอบเขียว
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
      backgroundColor: kPageBg,
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
                'แตะวันที่เพื่อดูงานรักษา (ถ้ามี)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Colors.black54),
              ),
              const SizedBox(height: 8),

              SizedBox(
                height: calendarHeight,
                child: Card(
                  color: kCalendarCardBg,
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
                      onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
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
