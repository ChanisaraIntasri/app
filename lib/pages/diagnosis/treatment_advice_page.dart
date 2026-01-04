import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mainpage/main_nav.dart';

const kPrimaryGreen = Color(0xFF005E33);

/// หน้าคำแนะนำการรักษา (พื้นหลังสีขาว)
/// แสดง:
/// 1) ผลวินิจฉัย (ชื่อโรค)
/// 2) ระดับความรุนแรง
/// 3) คำแนะนำการรักษา (พับ/ขยายได้)
class TreatmentAdvicePage extends StatefulWidget {
  final String treeId;
  final String diseaseId;
  final String diseaseName;

  /// คะแนนรวมจากการตอบแบบสอบถาม
  final double totalScore;

  /// ระดับความรุนแรงที่คำนวณได้ (จาก disease_risk_levels)
  final String riskLevelId;
  final String riskLevelName;

  /// ข้อความเพิ่มเติม (ถ้ามี)
  final String? note;

  /// รายการคำแนะนำ (1 รายการต่อ 1 treatment หรือแยกหัวข้อ)
  final List<String> adviceList;

  /// ใส่รูปได้ (ไม่ใส่ก็ได้)
  /// - ถ้าเป็น URL (http/https) จะใช้ Image.network
  /// - ถ้าเป็น assets/... จะใช้ Image.asset
  /// - อย่างอื่นจะพยายามใช้ Image.file
  final String? referenceImagePath; // "ภาพเปรียบเทียบ"
  final String? userImagePath;      // "ภาพของคุณ"

  const TreatmentAdvicePage({
    super.key,
    required this.treeId,
    required this.diseaseId,
    required this.diseaseName,
    required this.totalScore,
    required this.riskLevelId,
    required this.riskLevelName,
    this.note,
    required this.adviceList,
    this.referenceImagePath,
    this.userImagePath,
  });

  @override
  State<TreatmentAdvicePage> createState() => _TreatmentAdvicePageState();
}

class _TreatmentAdvicePageState extends State<TreatmentAdvicePage> {
  bool _showAdvice = true;

  bool _isHttpUrl(String s) => s.startsWith('http://') || s.startsWith('https://');
  bool _isAsset(String s) => s.startsWith('assets/');

  ImageProvider<Object>? _imgProvider(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final p = path.trim();

    if (_isHttpUrl(p)) return NetworkImage(p);
    if (_isAsset(p)) return AssetImage(p);

    // file path
    final f = File(p);
    if (f.existsSync()) return FileImage(f);
    return null;
  }

  Widget _imageBox({required String title, required String? imagePath}) {
    final provider = _imgProvider(imagePath);

    return Expanded(
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE6E6E6)),
                image: provider != null
                    ? DecorationImage(image: provider, fit: BoxFit.cover)
                    : null,
              ),
              child: provider == null
                  ? const Center(
                      child: Icon(Icons.image_outlined, size: 34, color: Colors.black45),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _headerText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(
          'ผลวินิจฉัย : ${widget.diseaseName}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'ความรุนแรง : ${widget.riskLevelName}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        if (widget.note != null && widget.note!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(widget.note!, style: const TextStyle(fontSize: 14)),
        ],
      ],
    );
  }

  Widget _adviceToggleButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _showAdvice = !_showAdvice),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6E6E6)),
        ),
        child: Row(
          children: [
            const Text('🤖 ', style: TextStyle(fontSize: 16)),
            const Expanded(
              child: Text(
                'แนะนำวิธีการรักษา',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
            Icon(_showAdvice ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    );
  }

  Widget _adviceCard() {
    final merged = widget.adviceList.where((x) => x.trim().isNotEmpty).toList();
    final body = merged.isEmpty ? 'ยังไม่มีคำแนะนำในระดับความรุนแรงนี้' : merged.join('\n\n');

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 220),
      crossFadeState:
          _showAdvice ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE6E6E6)),
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(0.05),
            ),
          ],
        ),
        child: Text(
          body,
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
      ),
      secondChild: const SizedBox(height: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // ✅ ตามที่ขอ: พื้นหลังขาว
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: const Text('คำแนะนำการรักษา'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _imageBox(title: 'ภาพเปรียบเทียบ', imagePath: widget.referenceImagePath),
                  const SizedBox(width: 12),
                  _imageBox(title: 'ภาพของคุณ', imagePath: widget.userImagePath),
                ],
              ),
              const SizedBox(height: 16),
              _headerText(),
              const SizedBox(height: 16),
              _adviceToggleButton(),
              _adviceCard(),
              const SizedBox(height: 18),

              // ปุ่มรับแผนการรักษา
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () async {
                    // ✅ ไปหน้า Home (ผ่าน MainNav) และล้าง stack
                    final prefs = await SharedPreferences.getInstance();
                  
                    // พยายามอ่านชื่อผู้ใช้ที่เคยบันทึกไว้ (ถ้าไม่มีจะเป็นค่าว่าง)
                    const keys = <String>['username','userName','initialUsername','name','displayName'];
                    String initialUsername = '';
                    for (final k in keys) {
                      final v = prefs.getString(k);
                      if (v != null && v.trim().isNotEmpty) {
                        initialUsername = v.trim();
                        break;
                      }
                    }
                  
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => MainNav(initialUsername: initialUsername)),
                      (r) => false,
                    );
                  },
                  child: const Text(
                    'รับแผนการรักษา',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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
