import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_application_1/models/citrus_tree_record.dart';

const kPrimaryGreen = Color(0xFF005E33);

const kPageBg = Color(0xFFF7F6F2);
const kCardWhite = Colors.white;
const kShadowColor = Color.fromARGB(18, 0, 0, 0);

class TreeTreatmentPlanPage extends StatefulWidget {
  final CitrusTreeRecord record;

  const TreeTreatmentPlanPage({super.key, required this.record});

  @override
  State<TreeTreatmentPlanPage> createState() => _TreeTreatmentPlanPageState();
}

class _TreeTreatmentPlanPageState extends State<TreeTreatmentPlanPage> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  late String _taskName;
  late int _everyDays;
  late DateTime _startDate;
  late Set<String> _doneDates;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();

    _taskName = widget.record.treatmentTaskName.isEmpty
        ? 'พ่นยา'
        : widget.record.treatmentTaskName;
    _everyDays = widget.record.treatmentEveryDays <= 0
        ? 3
        : widget.record.treatmentEveryDays;
    _startDate = widget.record.treatmentStartDate;
    _doneDates = Set<String>.from(widget.record.treatmentDoneDates);
  }

  // ถ้าโปรเจกต์คุณมี dateKey() อยู่แล้ว ใช้ของเดิมก็ได้
  String dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isDue(DateTime day) {
    final d0 = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final d1 = DateTime(day.year, day.month, day.day);
    final diff = d1.difference(d0).inDays;
    if (diff < 0) return false;
    return diff % _everyDays == 0;
  }

  bool _isDone(DateTime day) => _doneDates.contains(dateKey(day));

  void _setDone(DateTime day, bool value) {
    final k = dateKey(day);
    if (value) {
      _doneDates.add(k);
    } else {
      _doneDates.remove(k);
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    setState(() {
      _startDate = picked;
      _doneDates.clear();
    });
  }

  void _saveAndPop() {
    final updated = widget.record.copyWith(
      treatmentTaskName: _taskName.trim().isEmpty ? 'พ่นยา' : _taskName.trim(),
      treatmentEveryDays: _everyDays <= 0 ? 3 : _everyDays,
      treatmentStartDate: _startDate,
      treatmentDoneDates: _doneDates,
    );
    Navigator.pop(context, updated);
  }

  // ✅ กดสวิตช์แล้ว "บันทึก + ปิด dialog" อัตโนมัติ
  Future<void> _showDueDialog(DateTime day) async {
    final taskText = _taskName.trim().isEmpty ? "พ่นยา" : _taskName.trim();
    final dateText = '${day.day}/${day.month}/${day.year}';

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        bool done = _isDone(day);

        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kCardWhite,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: kShadowColor,
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                                children: [
                                  TextSpan(text: taskText),
                                  const TextSpan(text: '  '),
                                  TextSpan(
                                    text: done ? '(ทำแล้ว)' : '(ยังไม่ได้ทำ)',
                                    style: TextStyle(
                                      color: done ? kPrimaryGreen : Colors.red,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Switch(
                            value: done,
                            activeColor: kPrimaryGreen,
                            onChanged: (v) {
                              // 1) บันทึกลง state
                              setState(() => _setDone(day, v));
                              // 2) ปิดบล็อกทันที (ไม่ต้องกดกากบาท)
                              Navigator.pop(context);
                            },
                          ),
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(999),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.close, size: 20),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ครบกำหนด: $dateText',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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

  // ✅ ครบกำหนด = วงเต็มแดง, ทำแล้ว = วงเต็มเขียว
  // ✅ วันปกติที่เลือก = วงขอบเขียว
  Widget _dayCell(DateTime day, {required bool selected, required bool outside}) {
    final due = _isDue(day);
    final done = due ? _isDone(day) : false;

    final Color? fill = due ? (done ? kPrimaryGreen : Colors.red) : null;
    final bool ringSelected = selected && !due;

    final Color textColor = fill != null
        ? Colors.white
        : ringSelected
            ? kPrimaryGreen
            : (outside ? Colors.grey.shade400 : Colors.black87);

    return Center(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: fill ?? Colors.transparent,
          shape: BoxShape.circle,
          border: ringSelected ? Border.all(color: kPrimaryGreen, width: 2) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPageBg,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: const Text('แผนการรักษา'),
        // ✅ เอาปุ่มบันทึกออกจากด้านบนแล้ว
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            // ======= บล็อกตั้งค่า =======
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kCardWhite,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: kShadowColor,
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TextFormField(
                      initialValue: _taskName,
                      onChanged: (v) => _taskName = v,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        labelText: 'งานที่ต้องทำ',
                        hintText: 'เช่น พ่นยา / ใส่ปุ๋ย',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: _everyDays.toString(),
                            keyboardType: TextInputType.number,
                            onChanged: (v) =>
                                _everyDays = int.tryParse(v.trim()) ?? 3,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              labelText: 'ทำทุก ๆ (วัน)',
                              hintText: 'เช่น 3',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _pickStartDate,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFEDEDED)),
                              ),
                              child: Text(
                                'เริ่มนับจาก: ${_startDate.day}/${_startDate.month}/${_startDate.year}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ======= ปฏิทิน =======
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: kCardWhite,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: kShadowColor,
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: TableCalendar(
                  firstDay: DateTime.now().subtract(const Duration(days: 365)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _focusedDay,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {CalendarFormat.month: 'month'},

                  // ให้บล็อกไม่ยาวลงล่างเกินไป
                  sixWeekMonthsEnforced: false,
                  shouldFillViewport: false,

                  selectedDayPredicate: (day) =>
                      _selectedDay != null && _isSameDay(day, _selectedDay!),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });

                    if (_isDue(selectedDay)) {
                      Future.microtask(() => _showDueDialog(selectedDay));
                    }
                  },
                  headerStyle: const HeaderStyle(
                    titleCentered: true,
                    formatButtonVisible: false,
                    titleTextStyle:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    leftChevronIcon: Icon(Icons.chevron_left, size: 26),
                    rightChevronIcon: Icon(Icons.chevron_right, size: 26),
                  ),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                    weekendStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  daysOfWeekHeight: 28,
                  rowHeight: 52,
                  calendarStyle: const CalendarStyle(
                    isTodayHighlighted: false,
                    outsideDaysVisible: true,
                  ),
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, focusedDay) {
                      final selected = _selectedDay != null &&
                          _isSameDay(day, _selectedDay!);
                      return _dayCell(day, selected: selected, outside: false);
                    },
                    selectedBuilder: (context, day, focusedDay) {
                      return _dayCell(day, selected: true, outside: false);
                    },
                    outsideBuilder: (context, day, focusedDay) {
                      final selected = _selectedDay != null &&
                          _isSameDay(day, _selectedDay!);
                      return _dayCell(day, selected: selected, outside: true);
                    },
                    todayBuilder: (context, day, focusedDay) {
                      final selected = _selectedDay != null &&
                          _isSameDay(day, _selectedDay!);
                      return _dayCell(day, selected: selected, outside: false);
                    },
                  ),
                ),
              ),
            ),

            // ✅ ปุ่มบันทึก “อยู่ด้านล่างปฏิทิน”
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saveAndPop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'บันทึก',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
