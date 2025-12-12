import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/citrus_tree_record.dart';

// สีเขียวหลัก
const kPrimaryGreen = Color(0xFF005E33);
// พื้นหลังโทนเทาอ่อน
const kBg = Color.fromARGB(255, 248, 248, 248);

class AddTreeRecordPage extends StatefulWidget {
  const AddTreeRecordPage({super.key});

  @override
  State<AddTreeRecordPage> createState() => _AddTreeRecordPageState();
}

class _AddTreeRecordPageState extends State<AddTreeRecordPage> {
  final _formKey = GlobalKey<FormState>();

  // ผู้ใช้กรอกเอง
  final _nameController = TextEditingController(text: 'ต้นที่ 1');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ---------- style ช่องกรอกให้เป็นกรอบมน ----------
  InputDecoration _inputDecoration({
    String? label,
    String? hint,
  }) {
    return InputDecoration(
      labelText: (label == null || label.isEmpty) ? null : label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      alignLabelWithHint: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        borderSide: BorderSide(
          color: kPrimaryGreen,
          width: 2,
        ),
      ),
    );
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final record = CitrusTreeRecord(
      id: id,
      name: _nameController.text.trim(),
      disease: '',            // ตอนนี้ยังไม่รู้โรค
      recommendation: '',     // คำแนะนำจากโมเดล
      note: '',               // หน้าเพิ่มต้นส้มไม่เก็บโน้ตแล้ว → ส่งค่าว่าง
      createdAt: DateTime.now(),
    );

    // ส่ง record กลับไปให้หน้า History (SharePage)
    Navigator.of(context).pop(record);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('เพิ่มบันทึกต้นส้ม'),
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- ข้อมูลต้นส้ม ----------
              const Text(
                'ข้อมูลต้นส้ม',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A2A18),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: _inputDecoration(
                  label: 'ชื่อต้น / หมายเลขต้น',
                  hint: 'เช่น ต้นที่ 1, แปลง A-ต้น 3',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'กรอกชื่อต้นส้มก่อนนะ'
                    : null,
              ),
              const SizedBox(height: 32),

              // ---------- ปุ่มบันทึก ----------
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'บันทึกต้นส้ม',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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
