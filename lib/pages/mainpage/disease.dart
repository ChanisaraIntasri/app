import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// นำเข้าหน้าผลประเมินความเสี่ยง
import 'diagnosis_result_page.dart';



// ✅ Base URL ของ FastAPI ผ่าน Cloudflare Tunnel (ตัวใหม่)
// ห้ามใส่ ?fbclid=... ต่อท้าย
const String kBaseUrl =
    'https://cope-handy-knowledgestorm-alt.trycloudflare.com';

// map ชื่อโรค (ภาษาไทยใน UI) -> ชื่อ disease ที่ backend ใช้ใน DiagnoseRequest
const Map<String, String> kDiseaseSlugMap = {
  "โรคแคงเกอร์": "canker",
  "ราดำ": "sooty_mold",
  "โรคเมลาโนส": "melanose_greasy",
  "โรคจุดมัน": "melanose_greasy", // ใช้ rule ชุดเดียวกับ melanose
  "กรีนนิ่ง": "greening",
  "โรคแอนทราคโนส": "antracnose",
  "หนอนชอนใบ": "leaf_miner",
};


/// หน้าเลือกโรค
class DiseaseListScreen extends StatelessWidget {
  const DiseaseListScreen({super.key});

  final List<String> _diseaseList = const [
    "โรคแคงเกอร์",
    "ราดำ",
    "โรคเมลาโนส",
    "โรคจุดมัน",
    "กรีนนิ่ง",
    "โรคแอนทราคโนส",
    "หนอนชอนใบ",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE2ECD8),
      appBar: AppBar(
        title: const Text(
          "เลือกโรคที่ต้องการตรวจ",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        itemCount: _diseaseList.length,
        itemBuilder: (context, index) {
          final diseaseName = _diseaseList[index];

          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        QuestionScreen(diseaseName: diseaseName),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBE8),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Text(
                  diseaseName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// =====================
/// หน้าคำถาม + ส่งไปวินิจฉัย
/// =====================
class QuestionScreen extends StatefulWidget {
  final String diseaseName;
  const QuestionScreen({super.key, required this.diseaseName});

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  // คำถามจาก backend
  List<Map<String, dynamic>> _questions = [];

  // index คำถามปัจจุบัน
  int _currentIndex = 0;

  // เก็บคำตอบ field -> value ให้ตรงกับ DiagnoseRequest
  final Map<String, dynamic> _answers = {};

  // สำหรับคำถามแบบ single_choice
  String? _selectedOption;

  // สำหรับคำถามแบบ number
  final TextEditingController _numberController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  /// โหลดคำถามจาก /questions/{disease}
  Future<void> _loadQuestions() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _questions = [];
      _currentIndex = 0;
      _selectedOption = null;
      _answers.clear();
      _numberController.text = "";
    });

    try {
      final slug = kDiseaseSlugMap[widget.diseaseName];
      if (slug == null) {
        throw Exception("ไม่พบ slug สำหรับโรคนี้");
      }

      final url = Uri.parse('$kBaseUrl/questions/$slug');
      final res = await http.get(url);

      if (res.statusCode != 200) {
        throw Exception("HTTP ${res.statusCode}");
      }

      final body = jsonDecode(res.body);

      List<dynamic> rawList;
      if (body is Map && body['questions'] is List) {
        rawList = body['questions'] as List;
      } else if (body is List) {
        rawList = body;
      } else {
        throw Exception("รูปแบบข้อมูลจาก API ไม่ถูกต้อง");
      }

      _questions = rawList.map<Map<String, dynamic>>((e) {
        final q = e as Map<String, dynamic>;
        return {
          'field': q['field'] ?? '',
          'question': q['question'] ?? '',
          'type': q['type'] ?? 'single_choice',
          'options': (q['options'] is List)
              ? (q['options'] as List).map((o) => o.toString()).toList()
              : <String>[],
        };
      }).toList();

      if (_questions.isEmpty) {
        throw Exception("ไม่พบคำถามใน API");
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = "โหลดคำถามไม่สำเร็จ: Exception: $e";
      });
    }
  }

  /// เลือกคำตอบ single_choice
  void _onSelectOption(String option) {
    final currentQ = _questions[_currentIndex];
    final field = currentQ['field'] as String;
    setState(() {
      _selectedOption = option;
      _answers[field] = option;
    });
  }

  /// เปลี่ยนค่าจาก TextField แบบ number
  void _onNumberChanged(String value) {
    final currentQ = _questions[_currentIndex];
    final field = currentQ['field'] as String;
    _answers[field] = value;
  }

  /// handle ปุ่ม ถัดไป / ประเมินความเสี่ยง
  Future<void> _next() async {
    final currentQ = _questions[_currentIndex];
    final String field = currentQ['field'] as String;
    final String type = currentQ['type'] as String;

    // ตรวจว่าตอบคำถามแล้วหรือยัง
    if (type == 'single_choice') {
      final ans = _answers[field];
      if (ans == null || (ans is String && ans.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณาเลือกคำตอบก่อน')),
        );
        return;
      }
    } else if (type == 'number') {
      final raw = _answers[field]?.toString() ?? '';
      if (raw.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณากรอกตัวเลข')),
        );
        return;
      }
      final num? parsed = num.tryParse(raw);
      if (parsed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รูปแบบตัวเลขไม่ถูกต้อง')),
        );
        return;
      }
      _answers[field] = parsed;
    }

    // ถ้ามีคำถามต่อไป → ไปข้อถัดไป
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOption = null;

        final nextQ = _questions[_currentIndex];
        final nextField = nextQ['field'] as String;
        final nextType = nextQ['type'] as String;

        if (nextType == 'single_choice') {
          _selectedOption = _answers[nextField] as String?;
        } else if (nextType == 'number') {
          _numberController.text = _answers[nextField]?.toString() ?? '';
        }
      });
    } else {
      // ไม่มีคำถามแล้ว → ส่งไป diagnose-risk
      await _submitToBackend();
    }
  }

  /// ส่งคำตอบไป backend /diagnose-risk แล้วไปหน้า DiagnosisResultPage
  Future<void> _submitToBackend() async {
    final slug = kDiseaseSlugMap[widget.diseaseName];
    if (slug == null) return;

    setState(() {
      _submitting = true;
    });

    try {
      final body = {
        'disease': slug, // ให้ตรงกับ DiagnoseRequest.disease
        ..._answers,
      };

      final res = await http.post(
        Uri.parse('$kBaseUrl/diagnose-risk'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = jsonDecode(res.body);

      if (data['status'] == 'success') {
        final result = data['result'] as Map<String, dynamic>;

        final String riskLevel = result['risk_level']?.toString() ?? '';
        final int riskScore =
            (result['risk_score'] is num) ? (result['risk_score'] as num).toInt() : 0;
        final String advice = result['advice']?.toString() ?? '';

        if (!mounted) return;

        // ไปหน้าแสดงผลใหม่
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DiagnosisResultPage(
              diseaseName: widget.diseaseName, // ชื่อไทยในแอป
              riskLevel: riskLevel,
              riskScore: riskScore,
              advice: advice,
            ),
          ),
        );
      } else if (data['status'] == 'need_more_info') {
        final missing = data['missing_questions'] as List<dynamic>? ?? [];
        _showNeedMoreInfoDialog(missing);
      } else {
        final msg = data['message'] ?? 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.toString())),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งข้อมูลไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  /// แสดง dialog ถ้า backend ต้องการข้อมูลเพิ่ม
  void _showNeedMoreInfoDialog(List<dynamic> missing) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ต้องการข้อมูลเพิ่มเติม'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ระบบยังต้องการข้อมูลเพิ่มในหัวข้อต่อไปนี้:'),
              const SizedBox(height: 8),
              ...missing.map((m) {
                final mm = m as Map<String, dynamic>;
                return Text('• ${mm['question'] ?? mm['field']}');
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('ตกลง'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ระหว่างโหลดคำถาม
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFE2ECD8),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // โหลดไม่สำเร็จ / ไม่มีคำถาม
    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFE2ECD8),
        body: Center(
          child: Text(_errorMessage ?? 'ไม่พบคำถาม'),
        ),
      );
    }

    final currentQ = _questions[_currentIndex];
    final type = currentQ['type'] as String;
    final options = (currentQ['options'] as List).cast<String>();

    // sync ค่า number ตอนเข้าข้อ number
    if (type == 'number' && _numberController.text.isEmpty) {
      final field = currentQ['field'] as String;
      _numberController.text = _answers[field]?.toString() ?? '';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE2ECD8),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "ยกเลิก",
                      style: TextStyle(color: Colors.black, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "อาการ: ${widget.diseaseName}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text("ข้อที่ ${_currentIndex + 1} / ${_questions.length}"),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: (_currentIndex + 1) / _questions.length,
                  backgroundColor: Colors.grey.shade300,
                  color: Colors.orange,
                  minHeight: 6,
                ),
                const SizedBox(height: 30),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5CD90),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    currentQ['question']?.toString() ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // แสดง UI ตามชนิดคำถาม
                if (type == 'single_choice') ...[
                  ...options.map((option) {
                    final bool isSelected = _selectedOption == option;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: InkWell(
                        onTap: () => _onSelectOption(option),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFFFFFBE8),
                            borderRadius: BorderRadius.circular(20),
                            border: isSelected
                                ? Border.all(color: Colors.orange, width: 2)
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isSelected)
                                const Icon(Icons.check_circle,
                                    color: Colors.orange, size: 20),
                              if (isSelected) const SizedBox(width: 10),
                              Text(
                                option,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ] else if (type == 'number') ...[
                  TextField(
                    controller: _numberController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'กรอกตัวเลข',
                      filled: true,
                      fillColor: Color(0xFFFFFBE8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                    ),
                    onChanged: _onNumberChanged,
                  ),
                ],

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: _submitting ? null : _next,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _currentIndex == _questions.length - 1
                                ? "ประเมินความเสี่ยง"
                                : "ถัดไป",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
