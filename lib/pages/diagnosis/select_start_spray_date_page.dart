import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

// ใช้โทนเดียวกับแอป
const kPrimaryGreen = Color(0xFF005E33);

/// หน้าเลือก "วันเริ่มพ่นยา" (คืนค่า DateTime ผ่าน Navigator.pop)
class SelectStartSprayDatePage extends StatefulWidget {
  final DateTime? initialDate;
  final DateTime? minDate; // กันเลือกย้อนหลัง

  const SelectStartSprayDatePage({
    super.key,
    this.initialDate,
    this.minDate,
  });

  @override
  State<SelectStartSprayDatePage> createState() => _SelectStartSprayDatePageState();
}

class _SelectStartSprayDatePageState extends State<SelectStartSprayDatePage> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    final now = _dateOnly(DateTime.now());
    _selectedDay = widget.initialDate != null ? _dateOnly(widget.initialDate!) : null;
    _focusedDay = _selectedDay ?? now;
  }

  bool _isBeforeMin(DateTime day) {
    if (widget.minDate == null) return false;
    return _dateOnly(day).isBefore(_dateOnly(widget.minDate!));
  }

  String _fmtThai(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd / $mm / $yyyy';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: const Text('เลือกวันเริ่มพ่นยา'),
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // กล่องกลางหน้าจอแบบภาพตัวอย่าง
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: kPrimaryGreen, width: 4),
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 6),
                        const Text(
                          'เลือกวันที่ ที่คุณพร้อมสำหรับการเริ่มรักษา',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 14),
                        TableCalendar(
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2035, 12, 31),
                          focusedDay: _focusedDay,
                          calendarFormat: CalendarFormat.month,
                          availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                          selectedDayPredicate: (day) {
                            if (_selectedDay == null) return false;
                            return isSameDay(_selectedDay, day);
                          },
                          onDaySelected: (selectedDay, focusedDay) {
                            if (_isBeforeMin(selectedDay)) return;
                            setState(() {
                              _selectedDay = _dateOnly(selectedDay);
                              _focusedDay = focusedDay;
                            });
                          },
                          onPageChanged: (focusedDay) {
                            setState(() => _focusedDay = focusedDay);
                          },
                          enabledDayPredicate: (day) => !_isBeforeMin(day),
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                          ),
                          daysOfWeekStyle: const DaysOfWeekStyle(
                            weekendStyle: TextStyle(color: Colors.black54),
                            weekdayStyle: TextStyle(color: Colors.black54),
                          ),
                          calendarStyle: CalendarStyle(
                            outsideDaysVisible: false,
                            todayDecoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: kPrimaryGreen, width: 1.5),
                            ),
                            selectedDecoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: kPrimaryGreen,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ✅ กล่องยืนยันวัน (ตามภาพ)
                        if (_selectedDay != null) ...[
                          Text(
                            'วันที่ที่คุณพร้อมสำหรับเริ่มพ่นคือ\n${_fmtThai(_selectedDay!)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 12),
                        ] else ...[
                          const Text(
                            'แตะเลือกวันที่จากปฏิทิน',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.black54),
                          ),
                          const SizedBox(height: 12),
                        ],

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.black26),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                ),
                                child: const Text('ยกเลิก'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: (_selectedDay == null)
                                    ? null
                                    : () => Navigator.pop(context, _selectedDay!),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryGreen,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                ),
                                child: const Text('ยืนยัน'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
