import 'package:flutter/material.dart';
import '../diagnosis/select_start_spray_date_page.dart';

const kPrimaryGreen = Color(0xFF005E33);

enum FollowUpOutcome { cured, notCured }

class FollowUpResult {
  final FollowUpOutcome outcome;
  final DateTime? nextStartDate;

  const FollowUpResult({
    required this.outcome,
    this.nextStartDate,
  });
}

class TreatmentFollowUpPage extends StatefulWidget {
  final String treeLabel; // เช่น "ต้นที่ 1" หรือชื่อจริง
  final DateTime planLastDate; // วันสุดท้ายของแผน (เช่น 26)
  final int daysAfter; // 5 วัน
  final String lastUsedNote; // โน้ต/ชื่อสารเดิมจาก reminder (ถ้ามี)

  const TreatmentFollowUpPage({
    super.key,
    required this.treeLabel,
    required this.planLastDate,
    this.daysAfter = 5,
    this.lastUsedNote = '',
  });

  @override
  State<TreatmentFollowUpPage> createState() => _TreatmentFollowUpPageState();
}

class _TreatmentFollowUpPageState extends State<TreatmentFollowUpPage> {
  bool _notCuredStep = false;
  DateTime? _selectedStartDate;

  String _fmtThai(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.planLastDate;
    final followupText = 'ผ่านไป ${widget.daysAfter} วันแล้ว';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('ติดตามผลการรักษา'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // กล่องข้อมูล
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEAEAEA)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.treeLabel,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'แผนการรักษาสิ้นสุดวันที่ ${_fmtThai(last)}',
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          followupText,
                          style: const TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                        if (widget.lastUsedNote.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'สาร/งานล่าสุด: ${widget.lastUsedNote.trim()}',
                            style: const TextStyle(fontSize: 14, color: Colors.black87),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // คำถามหลัก
                  const Text(
                    'ยาที่ใช้รักษาทำให้โรคหายหรือยัง?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),

                  if (!_notCuredStep) ...[
                    // ปุ่ม 2 ตัว (ขั้นแรก)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(
                                context,
                                const FollowUpResult(outcome: FollowUpOutcome.cured),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: const Text(
                              'หายแล้ว',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() => _notCuredStep = true);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB71C1C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: const Text(
                              'ยังไม่หาย',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'หมายเหตุ: ถ้าตอบ “ยังไม่หาย” ระบบจะให้เลือกวันเริ่มรักษาใหม่',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ] else ...[
                    // ขั้น “ยังไม่หาย”
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFEAEAEA)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'ระบบจะแนะนำสารเคมีใหม่ให้',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'ต่อไปเลือกวันที่คุณพร้อมเริ่มรักษา',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                          ),
                          const SizedBox(height: 14),

                          OutlinedButton(
                            onPressed: () async {
                              final picked = await Navigator.push<DateTime>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SelectStartSprayDatePage(
                                    initialDate: DateTime.now(),
                                    minDate: DateTime.now(),
                                  ),
                                ),
                              );
                              if (picked != null) {
                                setState(() => _selectedStartDate = picked);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black,
                              side: const BorderSide(color: kPrimaryGreen, width: 2),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: const Text(
                              'เลือกวันที่พร้อมรักษา',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),

                          const SizedBox(height: 12),

                          if (_selectedStartDate != null)
                            Text(
                              'วันที่ที่เลือก: ${_fmtThai(_selectedStartDate!)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            )
                          else
                            Text(
                              'ยังไม่ได้เลือกวันที่',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),

                          const SizedBox(height: 14),

                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _notCuredStep = false;
                                      _selectedStartDate = null;
                                    });
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black,
                                    side: const BorderSide(color: Colors.black26),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                  ),
                                  child: const Text('ย้อนกลับ'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: (_selectedStartDate == null)
                                      ? null
                                      : () {
                                          Navigator.pop(
                                            context,
                                            FollowUpResult(
                                              outcome: FollowUpOutcome.notCured,
                                              nextStartDate: _selectedStartDate,
                                            ),
                                          );
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimaryGreen,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                  ),
                                  child: const Text(
                                    'ยืนยัน',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'ปิด',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
