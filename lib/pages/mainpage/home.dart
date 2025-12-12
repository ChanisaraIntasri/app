import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/mainpage/day_note_page.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:table_calendar/table_calendar.dart';

const kPrimaryGreen = Color(0xFF005E33);

// พื้นหลังจอ (ครีมอ่อนมาก ๆ)
const kPageBg = Color.fromARGB(255, 251, 251, 251);

// พื้นหลังบล็อกปฏิทิน: ขาว/ครีมที่ "เข้มกว่าพื้นหลังนิดหน่อย"
const kCalendarBg = Color.fromARGB(255, 248, 246, 244);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // วันที่ถูกเลือก & วันที่โฟกัสในปฏิทิน
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  // เก็บข้อมูลงาน/โน้ตของแต่ละวัน
  // key = วันที่แบบ year-month-day (ตัดเวลา)
  final Map<DateTime, List<DayNoteResult>> _dayNotes = {};

  // ตัดเวลาออก เหลือแค่ปี-เดือน-วัน
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // ให้ TableCalendar ใช้โหลด event ของแต่ละวัน
  List<DayNoteResult> _getNotesForDay(DateTime day) {
    return _dayNotes[_dateOnly(day)] ?? const <DayNoteResult>[];
  }

  // เปิดหน้าสร้าง/แก้ไขบันทึก (ซ่อน bottom nav)
  Future<void> _openDayNote(DateTime date) async {
    final result = await PersistentNavBarNavigator.pushNewScreen(
      context,
      screen: DayNotePage(selectedDate: date),
      withNavBar: false, // ✅ ซ่อนแถบเมนูล่าง
      pageTransitionAnimation: PageTransitionAnimation.cupertino,
    );

    // ถ้ากดบันทึกจริง และเป็น DayNoteResult
    if (result is DayNoteResult && result.hasTask) {
      final key = _dateOnly(result.date);
      setState(() {
        final List<DayNoteResult> current =
            List<DayNoteResult>.from(_dayNotes[key] ?? const <DayNoteResult>[]);
        current.add(result);
        _dayNotes[key] = current;
      });
    } else {
      setState(() {}); // refresh เฉย ๆ
    }
  }

  // ----------------------------
  // แสดงรายละเอียดแบบ "บล็อกสีข้าว" กลางจอ
  // ----------------------------
  void _showDayDetailsSheet(DateTime day) {
    final key = _dateOnly(day);

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54, // พื้นหลังเทา ๆ ด้านหลัง
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color.fromARGB(255, 255, 255, 255), // บล็อกสีข้าว
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 80,
          ), // ให้เป็นบล็อกลอยกลางจอ
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              final List<DayNoteResult> notes =
                  _dayNotes[key] ?? const <DayNoteResult>[];

              if (notes.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'ยังไม่มีบันทึกสำหรับวันนี้',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('เพิ่มบันทึกใหม่'),
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await _openDayNote(day);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }

              final dayText = '${day.day}/${day.month}/${day.year}';

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // แถวหัว + ปุ่มปิด
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'บันทึกวันที่ $dayText',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // รายการบันทึกทั้งหมดของวันนั้น
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: notes.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (ctx, index) {
                          final note = notes[index];

                          final bool isFertilizer =
                              note.activity == ActivityKind.fertilizer;
                          final icon =
                              isFertilizer ? Icons.grass : Icons.sanitizer;
                          final Color bgIcon = isFertilizer
                              ? const Color(0xFFFF7A00)
                              : const Color(0xFF4CAF50);
                          final String activityLabel =
                              isFertilizer ? 'ใส่ปุ๋ย' : 'พ่นยา';

                          // ----- คำนวณสถานะ -----
                          String statusLabel;
                          Color statusColor;

                          if (note.isReminder) {
                            statusLabel =
                                note.done ? 'ทำแล้ว' : 'ยังไม่ได้ทำ';
                            statusColor =
                                note.done ? Colors.green : Colors.red;
                          } else {
                            statusLabel = 'ทำแล้ว (บันทึกย้อนหลัง)';
                            statusColor = kPrimaryGreen;
                          }

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white, // การ์ดในบล็อกสีข้าว
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: bgIcon,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        icon,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      activityLabel,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  (note.noteText == null ||
                                          note.noteText!.isEmpty)
                                      ? 'ไม่มีรายละเอียด'
                                      : note.noteText!,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 10),

                                // แถวสถานะ + สวิตช์
                                Row(
                                  children: [
                                    Text(
                                      'สถานะ: $statusLabel',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: statusColor,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (note.isReminder)
                                      Switch(
                                        value: note.done,
                                        activeColor: kPrimaryGreen,
                                        onChanged: (v) {
                                          // อัปเดตค่าใน map หลัก
                                          setState(() {
                                            final List<DayNoteResult> list =
                                                List<DayNoteResult>.from(
                                              _dayNotes[key] ??
                                                  const <DayNoteResult>[],
                                            );
                                            list[index] = DayNoteResult(
                                              date: note.date,
                                              hasTask: note.hasTask,
                                              isReminder: note.isReminder,
                                              activity: note.activity,
                                              done: v,
                                              noteText: note.noteText,
                                            );
                                            _dayNotes[key] = list;
                                          });

                                          // อัปเดตใน dialog เองด้วย
                                          setModalState(() {});
                                        },
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                // ปุ่มบันทึกสถานะ (โชว์เฉพาะ reminder + ทำแล้ว)
                                if (note.isReminder && note.done)
                                  Align(
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      width: 220,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: kPrimaryGreen,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 16,
                                          ),
                                        ),
                                        onPressed: () async {
                                          // TODO: ตรงนี้ถ้าต้องการ sync กับ backend จริง ๆ
                                          // ให้เรียก CareLogsApi.update(...) หรือ API อื่นของคุณได้เลย
                                          Navigator.of(ctx).pop();
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'บันทึกสถานะการแจ้งเตือนแล้ว'),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.save,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'บันทึก',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // ปุ่มเพิ่มบันทึกใหม่ในวันเดียวกัน
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('เพิ่มบันทึกใหม่'),
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await _openDayNote(day);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // สูงของบล็อกปฏิทิน ประมาณ 45% ของจอ
    final double calendarHeight = MediaQuery.of(context).size.height * 0.45;

    return Scaffold(
      backgroundColor: kPageBg, // 👈 ใช้พื้นหลังครีมอ่อน
      body: SafeArea(
        child: Padding(
          // ลด padding ด้านบนและล่าง ให้ทุกอย่างขยับขึ้น
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== หัวข้อหน้า =====
              const Text(
                'Home',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3A2A18),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'ดูสภาพอากาศวันนี้ก่อนดูแลสวนส้มของคุณ',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8A6E55),
                ),
              ),
              const SizedBox(height: 10),

              // ===== การ์ดพยากรณ์อากาศ =====
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
                    const Icon(
                      Icons.wb_sunny_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'พยากรณ์อากาศวันนี้',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'อุณหภูมิ 28°C  ·  ความชื้น 65%\n'
                            'สภาพอากาศเหมาะสำหรับการตรวจโรคและดูแลสวนส้ม',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'ดี',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ===== หัวข้อปฏิทิน =====
              const Text(
                'ปฏิทินสวนส้ม',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3A2A18),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'แตะวันที่ เพื่อบันทึกสิ่งที่ทำวันนี้ หรือสร้างการแจ้งเตือนล่วงหน้า',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),

              // ===== บล็อกปฏิทิน (TableCalendar) =====
              SizedBox(
                height: calendarHeight,
                child: Card(
                  color: kCalendarBg,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: TableCalendar<DayNoteResult>(
                      firstDay: DateTime.now()
                          .subtract(const Duration(days: 365)),
                      lastDay: DateTime.now()
                          .add(const Duration(days: 365 * 3)),
                      focusedDay: _focusedDay,

                      // วันไหนถูกเลือก
                      selectedDayPredicate: (day) =>
                          isSameDay(day, _selectedDate),

                      // โหลด event ของแต่ละวัน
                      eventLoader: _getNotesForDay,

                      startingDayOfWeek: StartingDayOfWeek.monday,

                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                      ),

                      calendarStyle: CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: kPrimaryGreen.withOpacity(0.75),
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: const BoxDecoration(
                          color: kPrimaryGreen,
                          shape: BoxShape.circle,
                        ),
                        markersAlignment: Alignment.bottomCenter,
                        markersMaxCount: 1,
                      ),

                      // เวลาเปลี่ยนหน้าเดือน
                      onPageChanged: (focusedDay) {
                        _focusedDay = focusedDay;
                      },

                      // เวลาแตะวันที่
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDate = _dateOnly(selectedDay);
                          _focusedDay = focusedDay;
                        });

                        final notes = _getNotesForDay(selectedDay);
                        if (notes.isEmpty) {
                          _openDayNote(selectedDay);
                        } else {
                          _showDayDetailsSheet(selectedDay);
                        }
                      },

                      // วาดสัญลักษณ์บนวันนั้น ๆ
                      calendarBuilders: CalendarBuilders<DayNoteResult>(
                        markerBuilder: (context, date, events) {
                          if (events.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          // ถ้ามีแต่ "บันทึกย้อนหลัง" ทั้งหมด (ไม่มี reminder เลย)
                          final bool onlyLogs = events.isNotEmpty &&
                              events.every((e) => e.isReminder == false);

                          if (onlyLogs) {
                            return Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFFC94A),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.sentiment_satisfied_alt,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }

                          // ---- ด้านล่างนี้คือเคสที่ "มี reminder อย่างน้อย 1 อัน" ----
                          final reminders =
                              events.where((e) => e.isReminder).toList();

                          final bool hasFertilizer = reminders.any(
                            (e) => e.activity == ActivityKind.fertilizer,
                          );
                          final bool hasSpray = reminders.any(
                            (e) => e.activity == ActivityKind.spray,
                          );

                          IconData icon;
                          Color bgColor;

                          if (hasFertilizer && hasSpray) {
                            icon = Icons.notifications_active_rounded;
                            bgColor = const Color(0xFF6A4C93); // ม่วงเข้ม
                          } else {
                            final reminder = reminders.first;
                            final bool isF =
                                reminder.activity == ActivityKind.fertilizer;
                            icon = isF ? Icons.grass : Icons.sanitizer;
                            bgColor = isF
                                ? const Color(0xFFFF7A00) // ส้ม = ใส่ปุ๋ย
                                : const Color(0xFF4CAF50); // เขียว = พ่นยา
                          }

                          // ถ้าแจ้งเตือนในวันนั้น "ทำครบทุกอันแล้ว"
                          final bool allDone =
                              reminders.every((e) => e.done == true);
                          if (allDone) {
                            bgColor = bgColor.withOpacity(0.4);
                          }

                          return Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: bgColor,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                icon,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
