import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/care_logs_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kPrimaryGreen = Color(0xFF005E33);
const kPageBg = Color.fromARGB(255, 255, 255, 255);

enum ActivityKind { fertilizer, spray }

class DayNoteResult {
  final DateTime date;
  final bool hasTask;
  final bool isReminder;
  final ActivityKind activity;
  final bool done;
  final String? noteText;

  DayNoteResult({
    required this.date,
    required this.hasTask,
    required this.isReminder,
    required this.activity,
    required this.done,
    this.noteText,
  });
}

class DayNotePage extends StatefulWidget {
  final DateTime selectedDate;

  const DayNotePage({super.key, required this.selectedDate});

  @override
  State<DayNotePage> createState() => _DayNotePageState();
}

class _DayNotePageState extends State<DayNotePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _textCtl = TextEditingController();
  final TextEditingController _fertAreaCtl = TextEditingController();
  final TextEditingController _fertAmountCtl = TextEditingController();
  final TextEditingController _sprayAmountCtl = TextEditingController();
  final TextEditingController _sprayTreeCountCtl = TextEditingController();

  bool _isReminder = false;
  ActivityKind _activityKind = ActivityKind.fertilizer;
  bool _saving = false;

  @override
  void dispose() {
    _textCtl.dispose();
    _fertAreaCtl.dispose();
    _fertAmountCtl.dispose();
    _sprayAmountCtl.dispose();
    _sprayTreeCountCtl.dispose();
    super.dispose();
  }

  String get _dateText =>
      '${widget.selectedDate.day}/${widget.selectedDate.month}/${widget.selectedDate.year}';

  String get _detailLabel {
    switch (_activityKind) {
      case ActivityKind.fertilizer:
        return 'รายละเอียดการใส่ปุ๋ย (เช่น ใส่ปุ๋ยสูตร 15-15-15 ฯลฯ)';
      case ActivityKind.spray:
        return 'รายละเอียดการพ่นยา (เช่น ชื่อยา อัตราส่วน วิธีพ่น ฯลฯ)';
    }
  }

  void _onSelectActivity(ActivityKind kind) {
    if (_activityKind == kind) return;
    setState(() {
      _activityKind = kind;
      _textCtl.clear();
    });
  }

  // ✅ แก้ไข: เปลี่ยนจาก 'pesticide' เป็น 'spray'
  String _activityToCareType(ActivityKind kind) {
    switch (kind) {
      case ActivityKind.fertilizer:
        return 'fertilizer';
      case ActivityKind.spray:
        return 'spray'; // ✅ แก้ไขแล้ว
    }
  }

  String _buildExtraNote() {
    final buffer = StringBuffer();

    if (_activityKind == ActivityKind.fertilizer) {
      final area = _fertAreaCtl.text.trim();
      final amount = _fertAmountCtl.text.trim();

      if (area.isNotEmpty) {
        buffer.writeln('พื้นที่ที่ใส่ปุ๋ย: $area');
      }
      if (amount.isNotEmpty) {
        buffer.writeln('ปริมาณปุ๋ยที่ใช้: $amount');
      }
    } else {
      final amount = _sprayAmountCtl.text.trim();
      final trees = _sprayTreeCountCtl.text.trim();

      if (amount.isNotEmpty) {
        buffer.writeln('ปริมาณยาที่ใช้: $amount');
      }
      if (trees.isNotEmpty) {
        buffer.writeln('จำนวนต้นที่พ่น: $trees');
      }
    }

    return buffer.toString().trim();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final baseNote = _textCtl.text.trim();
    final extra = _buildExtraNote();

    final note = [
      baseNote,
      if (extra.isNotEmpty) extra,
    ].join('\n\n').trim();

    final done = !_isReminder;

    setState(() => _saving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null || token.isEmpty) {
        throw Exception('NO_TOKEN');
      }

      const int treeId = 1;

      final careLog = CareLog(
        treeId: treeId,
        careDate: widget.selectedDate,
        careType: _activityToCareType(_activityKind),
        isReminder: _isReminder,
        done: done,
        note: note.isEmpty ? null : note,
      );

      // ✅ Debug: ดูว่า Flutter ส่งอะไร
      debugPrint('=== SENDING TO API ===');
      debugPrint('care_type: ${careLog.careType}');
      debugPrint('is_reminder: ${careLog.isReminder}');
      debugPrint('done: ${careLog.done}');
      debugPrint('note: $note');
      debugPrint('note length: ${note.length}');
      debugPrint('======================');

      await CareLogsApi.create(careLog, token: token);

      final result = DayNoteResult(
        date: widget.selectedDate,
        hasTask: true,
        isReminder: _isReminder,
        activity: _activityKind,
        done: done,
        noteText: note.isEmpty ? null : note,
      );

      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;

      String msg = e.toString();
      if (msg.contains('NO_TOKEN') ||
          msg.contains('UNAUTHORIZED') ||
          msg.contains('401')) {
        msg = 'บันทึกไม่สำเร็จ: กรุณาเข้าสู่ระบบใหม่อีกครั้ง';
      } else {
        msg = 'บันทึกไม่สำเร็จ: $e';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            maxLines: 3,
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPageBg,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: const Text('บันทึกกิจกรรมสวนส้ม'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'วันที่ $_dateText',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'กรอกรายละเอียดว่าคุณทำอะไร หรือจะทำอะไรในวันนั้น\n'
                          'จากนั้นเลือกว่าจะเป็นแค่บันทึก หรือใช้เป็นการแจ้งเตือนล่วงหน้า',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'ประเภทกิจกรรม',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _StatusChip(
                                label: 'ใส่ปุ๋ย',
                                icon: Icons.grass,
                                selected:
                                    _activityKind == ActivityKind.fertilizer,
                                onTap: () =>
                                    _onSelectActivity(ActivityKind.fertilizer),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatusChip(
                                label: 'พ่นยา',
                                icon: Icons.sanitizer,
                                selected: _activityKind == ActivityKind.spray,
                                onTap: () =>
                                    _onSelectActivity(ActivityKind.spray),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _textCtl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: _detailLabel,
                            border: const OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'กรุณากรอกรายละเอียด'
                              : null,
                        ),
                        const SizedBox(height: 12),

                        if (_activityKind == ActivityKind.fertilizer) ...[
                          TextFormField(
                            controller: _fertAreaCtl,
                            decoration: const InputDecoration(
                              labelText: 'พื้นที่ที่ใส่ปุ๋ย (เช่น 2 ไร่, 5 แถว ฯลฯ)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _fertAmountCtl,
                            decoration: const InputDecoration(
                              labelText:
                                  'ปริมาณปุ๋ยที่ใช้ (เช่น 10 กก., 5 กระสอบ ฯลฯ)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.text,
                          ),
                          const SizedBox(height: 16),
                        ] else ...[
                          TextFormField(
                            controller: _sprayAmountCtl,
                            decoration: const InputDecoration(
                              labelText: 'ปริมาณยาที่ใช้ (เช่น 20 ลิตร ฯลฯ)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.text,
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _sprayTreeCountCtl,
                            decoration: const InputDecoration(
                              labelText: 'จำนวนต้นที่พ่น (เช่น 15 ต้น ฯลฯ)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.text,
                          ),
                          const SizedBox(height: 16),
                        ],

                        const Text(
                          'รูปแบบการบันทึก',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),

                        RadioListTile<bool>(
                          value: false,
                          groupValue: _isReminder,
                          onChanged: (v) {
                            setState(() => _isReminder = v ?? false);
                          },
                          activeColor: kPrimaryGreen,
                          title: Row(
                            children: const [
                              Icon(
                                Icons.sentiment_satisfied_alt,
                                color: kPrimaryGreen,
                              ),
                              SizedBox(width: 8),
                              Text('แค่บันทึกกิจกรรม (ไม่ต้องแจ้งเตือน)'),
                            ],
                          ),
                          subtitle: const Text(
                            'ใช้เก็บประวัติว่าทำอะไรในวันนี้ เช่น ใส่ปุ๋ย / พ่นยาที่ทำไปแล้ว',
                            style: TextStyle(fontSize: 12),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),

                        RadioListTile<bool>(
                          value: true,
                          groupValue: _isReminder,
                          onChanged: (v) {
                            setState(() => _isReminder = v ?? false);
                          },
                          activeColor: kPrimaryGreen,
                          title: Row(
                            children: const [
                              Icon(
                                Icons.notifications_active,
                                color: kPrimaryGreen,
                              ),
                              SizedBox(width: 8),
                              Text('บันทึกเป็นการแจ้งเตือนล่วงหน้า'),
                            ],
                          ),
                          subtitle: const Text(
                            'ใช้สำหรับงานที่ต้องทำในอนาคต เช่น ใส่ปุ๋ยครั้งต่อไป หรือพ่นยารอบหน้า',
                            style: TextStyle(fontSize: 12),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving ? 'กำลังบันทึก...' : 'บันทึก',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? kPrimaryGreen : Colors.white;
    final fg = selected ? Colors.white : kPrimaryGreen;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPrimaryGreen, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}