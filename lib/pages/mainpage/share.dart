import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/citrus_tree_record.dart';
import 'package:flutter_application_1/pages/subpage/add_tree_record_page.dart';
import 'package:flutter_application_1/pages/subpage/edit_tree_note_page.dart';

const kBg = Color.fromARGB(255, 255, 255, 255);
const kPrimaryGreen = Color(0xFF005E33);
const kCardBg = Color(0xFFEDEDED); // สีเดียวกับปุ่ม +

class SharePage extends StatefulWidget {
  const SharePage({super.key}); // หน้า History

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  final List<CitrusTreeRecord> _records = [];

  // ให้ intro โผล่เฉพาะตอนยังไม่มีข้อมูล
  bool _showIntro = true;

  Future<void> _addNewTree() async {
    final CitrusTreeRecord? newRecord = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AddTreeRecordPage(),
      ),
    );

    if (newRecord != null) {
      setState(() {
        _records.add(newRecord);
        _showIntro = false; // มีข้อมูลแล้ว ไม่ต้องโชว์ intro แล้ว
      });
    }
  }

  Future<void> _showRecordDetail(CitrusTreeRecord record, int index) async {
    // controller สำหรับชื่อ (แก้ไขได้ใน dialog)
    final nameController = TextEditingController(text: record.name);

    final String? action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        bool isEditing = false;
        CitrusTreeRecord currentRecord = record;

        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocalState) {
              // ✅ ขยายความสูง dialog ตามขนาดหน้าจอ (80% ของความสูง)
              final maxDialogHeight =
                  MediaQuery.of(ctx).size.height * 0.8;

              // ฟังก์ชันบันทึกการแก้ไข "ชื่อ" ต้นส้ม
              void saveEdits() {
                final updated = CitrusTreeRecord(
                  id: currentRecord.id,
                  name: nameController.text.trim(),
                  disease: currentRecord.disease,
                  recommendation: currentRecord.recommendation,
                  note: currentRecord.note,
                  createdAt: currentRecord.createdAt,
                );

                setState(() {
                  _records[index] = updated;
                });

                setLocalState(() {
                  currentRecord = updated;
                  isEditing = false;
                });
              }

              String _displayOrPlaceholder(String value) {
                if (value.trim().isEmpty) {
                  return 'ยังไม่มีข้อมูล';
                }
                return value;
              }

              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxDialogHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // แถวหัว dialog + ปุ่ม แก้ไข / บันทึก
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'รายละเอียดต้นส้ม',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF3A2A18),
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                if (isEditing) {
                                  // ตอนนี้อยู่โหมดแก้ไข → กดเพื่อบันทึก
                                  saveEdits();
                                } else {
                                  // เข้าโหมดแก้ไข
                                  setLocalState(() {
                                    isEditing = true;
                                  });
                                }
                              },
                              icon: Icon(
                                isEditing ? Icons.check : Icons.edit,
                                size: 18,
                              ),
                              label: Text(isEditing ? 'บันทึก' : 'แก้ไข'),
                              style: TextButton.styleFrom(
                                foregroundColor: kPrimaryGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ===== กรอบชื่อต้น / หมายเลขต้น (แก้ไขได้) =====
                        _editableFieldBlock(
                          title: 'ชื่อต้น / หมายเลขต้น',
                          controller: nameController,
                          enabled: isEditing,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 10),

                        // ===== กรอบโรค / อาการที่พบ (อ่านอย่างเดียว) =====
                        _readonlyBlock(
                          title: 'โรค / อาการที่พบ',
                          content: _displayOrPlaceholder(
                            currentRecord.disease,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ===== กรอบคำแนะนำ / การจัดการ (อ่านอย่างเดียว) =====
                        _readonlyBlock(
                          title: 'คำแนะนำ / การจัดการ',
                          content: _displayOrPlaceholder(
                            currentRecord.recommendation,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ===== กรอบโน้ต → เป็นปุ่มไปหน้าแก้ไขโน้ตเต็ม ๆ =====
                        GestureDetector(
                          onTap: () {
                            // ปิด dialog แล้วให้ SharePage ไปเปิดหน้า EditTreeNotePage ต่อ
                            Navigator.pop(ctx, 'edit_note');
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            decoration: BoxDecoration(
                              color: kCardBg,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'โน้ตเกี่ยวกับการดูแลต้นนี้',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF3A2A18),
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: Color(0xFF8A6E55),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                // ✅ ไม่แสดงเนื้อหาโน้ตจริงแล้ว
                                Text(
                                  'แตะเพื่อเพิ่มโน้ต',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF8A6E55),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Text(
                          'บันทึกเมื่อ ${currentRecord.createdAt.day}/${currentRecord.createdAt.month}/${currentRecord.createdAt.year}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ปุ่มลบ + ปิด
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx, 'delete'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 8,
                                  ),
                                ),
                                child: const Text('ลบบันทึกนี้'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, 'close'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryGreen,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 8,
                                  ),
                                ),
                                child: const Text('ปิด'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    // ใช้เสร็จแล้ว dispose controller ทิ้ง
    nameController.dispose();

    if (action == 'delete') {
      setState(() => _records.removeAt(index));
    } else if (action == 'edit_note') {
      // ไปหน้าแก้ไขโน้ต แล้วรับโน้ตที่แก้กลับมา
      final current = _records[index]; // เผื่อชื่อถูกแก้ไขไปแล้ว
      
      // ✅ เพิ่ม rootNavigator: true เพื่อไม่ให้แสดงแถบเมนูด้านล่าง
      final String? updatedNote = await Navigator.of(context, rootNavigator: true).push<String>(
        MaterialPageRoute(
          builder: (_) => EditTreeNotePage(
            treeName: current.name,
            initialNote: current.note,
          ),
        ),
      );

      if (updatedNote != null) {
        setState(() {
          _records[index] = CitrusTreeRecord(
            id: current.id,
            name: current.name,
            disease: current.disease,
            recommendation: current.recommendation,
            note: updatedNote,
            createdAt: current.createdAt,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Stack(
          children: [
            // ===== ทั้งหน้ามาอยู่ใน CustomScrollView (เลื่อนแน่นอน) =====
            CustomScrollView(
              slivers: [
                // หัวเขียวด้านบน
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: kPrimaryGreen,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'บันทึกประวัติสวนส้ม',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'บันทึกโรคและคำแนะนำของต้นส้มแต่ละต้น\n'
                            'แตะที่การ์ดเพื่อดูรายละเอียด หรือปัดซ้ายเพื่อลบ',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // เนื้อหา
                if (_records.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'ยังไม่มีบันทึกต้นส้ม\nกดปุ่ม + ด้านล่างขวาเพื่อเพิ่มต้นแรก',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final record = _records[index];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Dismissible(
                              key: ValueKey(record.id),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) {
                                setState(() => _records.removeAt(index));
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 22,
                                ),
                              ),
                              child: GestureDetector(
                                onTap: () => _showRecordDetail(record, index),
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: kCardBg,
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // ไอคอนรูปต้นส้ม
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.spa_rounded,
                                          color: kPrimaryGreen,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // ข้อมูลต้นส้ม (แสดงเฉพาะชื่อ + hint)
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              record.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF3A2A18),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'แตะเพื่อดูโรค คำแนะนำ และโน้ตที่บันทึกไว้',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF8A6E55),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // วันที่บันทึก
                                      Text(
                                        '${record.createdAt.day}/${record.createdAt.month}/${record.createdAt.year}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: _records.length,
                      ),
                    ),
                  ),
              ],
            ),

            // Intro overlay (โชว์เมื่อยังไม่มี record และยังไม่กดปิด)
            if (_showIntro && _records.isEmpty)
              _IntroOverlay(
                onSkip: () {
                  setState(() => _showIntro = false);
                },
                onDone: () {
                  setState(() => _showIntro = false);
                },
              ),
          ],
        ),
      ),

      // ขยับปุ่ม + ให้สูงขึ้นหน่อย กันชนกับ bottom nav
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(
          onPressed: _addNewTree,
          backgroundColor: kCardBg,
          elevation: 3,
          child: const Icon(Icons.add, color: Colors.black87),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

/// ===== helper: กรอบแสดงข้อมูลแบบอ่านอย่างเดียว =====
Widget _readonlyBlock({
  required String title,
  required String content,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kCardBg,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3A2A18),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          content,
          style: TextStyle(
            fontSize: 13,
            color: content.trim().isEmpty
                ? Colors.grey[500]
                : const Color(0xFF5A4634),
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

/// ===== helper: กรอบสำหรับ TextField (แก้ไขได้/ไม่ได้ตาม enabled) =====
Widget _editableFieldBlock({
  required String title,
  required TextEditingController controller,
  required bool enabled,
  int maxLines = 1,
  String? hint,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    decoration: BoxDecoration(
      color: kCardBg,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3A2A18),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            border: InputBorder.none,
          ),
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF5A4634),
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

/// ===== Overlay แนะนำ =====

class _IntroSlide {
  final String title;
  final String desc;
  final IconData icon;

  const _IntroSlide({
    required this.title,
    required this.desc,
    required this.icon,
  });
}

class _IntroOverlay extends StatefulWidget {
  final VoidCallback onSkip;
  final VoidCallback onDone;

  const _IntroOverlay({
    required this.onSkip,
    required this.onDone,
  });

  @override
  State<_IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<_IntroOverlay> {
  final _pageController = PageController();
  int _index = 0;

  final List<_IntroSlide> _slides = const [
    _IntroSlide(
      title: 'เริ่มบันทึกต้นส้ม',
      desc:
          'สร้างการ์ดให้แต่ละต้นส้ม เพื่อดูประวัติและอาการย้อนหลังได้ง่าย ๆ',
      icon: Icons.spa_rounded,
    ),
    _IntroSlide(
      title: 'ติดตามโรคและอาการ',
      desc:
          'จดว่าเคยพบโรคอะไร ใช้อะไรแก้บ้าง ช่วยลดการซ้ำซ้อนและลืมข้อมูลสำคัญ',
      icon: Icons.healing_rounded,
    ),
    _IntroSlide(
      title: 'วางแผนการดูแล',
      desc:
          'ใช้ข้อมูลที่บันทึกไว้ วางแผนพ่นยา ใส่ปุ๋ย และตัดแต่งกิ่งได้แม่นยำขึ้น',
      icon: Icons.event_note_rounded,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.35),
        child: Center(
          child: Container(
            width: 320,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: widget.onSkip,
                    child: const Icon(Icons.close, size: 20),
                  ),
                ),
                SizedBox(
                  height: 180,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) {
                      final s = _slides[i];
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor:
                                kPrimaryGreen.withOpacity(0.12),
                            child: Icon(
                              s.icon,
                              color: kPrimaryGreen,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            s.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF222222),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.desc,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6A6A6A),
                              height: 1.4,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: widget.onSkip,
                      child: const Text('ข้าม'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        _index == _slides.length - 1 ? 'เริ่มบันทึก' : 'ถัดไป',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}