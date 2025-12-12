import 'package:flutter/material.dart';

const kBg = Color.fromARGB(255, 255, 255, 255);
const kPrimaryGreen = Color(0xFF005E33);
const kCardBg = Color(0xFFEDEDED);

class EditTreeNotePage extends StatefulWidget {
  final String treeName;    // ชื่อต้น เช่น "ต้นที่ 1"
  final String initialNote; // โน้ตเดิม (อาจว่างก็ได้)

  const EditTreeNotePage({
    super.key,
    required this.treeName,
    required this.initialNote,
  });

  @override
  State<EditTreeNotePage> createState() => _EditTreeNotePageState();
}

class _EditTreeNotePageState extends State<EditTreeNotePage> {
  /// controller ของโน้ตแต่ละช่อง
  final List<TextEditingController> _noteControllers = [];

  @override
  void initState() {
    super.initState();

    // แปลง initialNote เป็นหลายช่อง (แยกด้วย \n หรือ \n\n)
    final raw = widget.initialNote.trim();

    if (raw.isEmpty) {
      _noteControllers.add(TextEditingController());
    } else {
      final parts = raw.split(RegExp(r'\n+'));
      for (final p in parts) {
        final text = p.trim();
        if (text.isNotEmpty) {
          _noteControllers.add(TextEditingController(text: text));
        }
      }
      if (_noteControllers.isEmpty) {
        _noteControllers.add(TextEditingController());
      }
    }
  }

  @override
  void dispose() {
    for (final c in _noteControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addNoteCard() {
    setState(() {
      _noteControllers.add(TextEditingController());
    });
  }

  void _removeNoteCard(int index) {
    if (_noteControllers.length == 1) {
      // เหลือช่องเดียว → ไม่ลบ แต่ล้างข้อความแทน
      setState(() {
        _noteControllers[index].clear();
      });
      return;
    }

    final controller = _noteControllers.removeAt(index);
    controller.dispose();

    setState(() {});
  }

  void _saveAndReturn() {
    // รวมโน้ตทุกช่อง (เฉพาะที่ไม่ว่าง) → ส่งกลับไปหน้า SharePage
    final notes = _noteControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final combinedNote = notes.join('\n'); // เก็บแต่ละโน้ตเป็นบรรทัดใหม่
    Navigator.of(context).pop(combinedNote);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'โน้ตของ${widget.treeName}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: GestureDetector(
        // แตะพื้นหลังแล้วปิดคีย์บอร์ด
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- หัวข้อ + ปุ่มเพิ่ม ----------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              color: kBg, // ✅ ใช้สีเดียวกับพื้นหลังหลัก
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      'โน้ตเกี่ยวกับการดูแลต้นนี้',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3A2A18),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _addNoteCard,
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kBg,
                        border: Border.all(
                          color: kPrimaryGreen,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 20,
                        color: kPrimaryGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // ---------- รายการช่องโน้ต (เลื่อน) ----------
            Expanded(
              child: _noteControllers.isEmpty
                  ? Center(
                      child: Text(
                        'ยังไม่มีโน้ต\nแตะปุ่ม + ด้านบนเพื่อเพิ่มโน้ต',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      itemCount: _noteControllers.length,
                      itemBuilder: (context, index) {
                        return _NoteField(
                          index: index,
                          controller: _noteControllers[index],
                          onDelete: () => _removeNoteCard(index),
                        );
                      },
                    ),
            ),

            // ---------- ปุ่มบันทึกด้านล่าง ----------
            Container(
              color: kBg, // ✅ ใช้สีพื้นหลังเดียวกัน ไม่ให้ดูเป็นชั้น
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveAndReturn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'บันทึกโน้ต',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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

/// ช่องโน้ต 1 ช่อง (กล่องมน + ถังขยะด้านขวา)
class _NoteField extends StatelessWidget {
  final int index;
  final TextEditingController controller;
  final VoidCallback onDelete;

  const _NoteField({
    required this.index,
    required this.controller,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1.2,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'โน้ตครั้งที่ ${index + 1}',
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF3A2A18),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.red,
                size: 20,
              ),
              onPressed: onDelete,
              tooltip: 'ลบโน้ตนี้',
            ),
          ],
        ),
      ),
    );
  }
}
