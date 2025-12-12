import 'package:flutter/material.dart';

const kOrange = Color(0xFFFF7A00);
const kBgMint = Color(0xFFE7F2E3); // เขียวอ่อนคล้ายภาพตัวอย่าง
const kCard = Colors.white;

/// หน้าสรุปผลประเมินความเสี่ยง + คำแนะนำ จาก API /diagnose-risk
class DiagnosisResultPage extends StatelessWidget {
  final String diseaseName; // เช่น "โรคแคงเกอร์" (ชื่อภาษาไทยที่ใช้ในแอป)
  final String riskLevel;   // เช่น "เสี่ยงสูง" จาก API
  final int riskScore;      // ตัวเลข risk_score จาก API
  final String advice;      // ข้อความคำแนะนำจาก API

  const DiagnosisResultPage({
    super.key,
    required this.diseaseName,
    required this.riskLevel,
    required this.riskScore,
    required this.advice,
  });

  Color _riskColor() {
    if (riskLevel.contains("สูง")) {
      return Colors.red.shade600;
    } else if (riskLevel.contains("ปานกลาง")) {
      return Colors.orange.shade700;
    } else if (riskLevel.contains("ต่ำ")) {
      return Colors.green.shade700;
    }
    return Colors.black87;
  }

  @override
  Widget build(BuildContext context) {
    // แปลง advice เป็นบรรทัด ๆ ถ้ามี /n หลายบรรทัด จะได้โชว์เป็น bullet ได้
    final List<String> adviceLines = advice
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: kBgMint,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // หัวเรื่อง
              Text(
                'ผลวินิจฉัย : $diseaseName',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),

              // การ์ด "ผลประเมินความเสี่ยง"
              Container(
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 10,
                      color: Colors.black12,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // แคปซูลหัวการ์ด
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F9F8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.stacked_line_chart, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'ผลประเมินความเสี่ยง',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text(
                      'ระดับความเสี่ยง',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      riskLevel,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _riskColor(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'คะแนนความเสี่ยง : $riskScore',
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // การ์ด "คำแนะนำในการจัดการโรค" (ใช้ advice จาก API)
              Container(
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 10,
                      color: Colors.black12,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // แคปซูลหัวการ์ด
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F9F8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text('💊', style: TextStyle(fontSize: 20)),
                          SizedBox(width: 8),
                          Text(
                            'คำแนะนำในการจัดการโรค',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (adviceLines.length <= 1)
                      // ถ้า advice เป็นข้อความเดียว ยาว ๆ
                      Text(
                        advice,
                        style: const TextStyle(fontSize: 16, height: 1.4),
                      )
                    else
                      // ถ้าเป็นหลายบรรทัด -> แสดงเป็น bullet
                      ...adviceLines.map(
                        (t) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Icon(Icons.circle, size: 6),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  t,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ปุ่มกลับหน้าหลัก
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: InkWell(
                    onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
                    borderRadius: BorderRadius.circular(20),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: kOrange,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(blurRadius: 8, color: Colors.black12),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.home_filled,
                            color: Colors.white,
                            size: 32,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'กลับหน้าหลัก',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
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
