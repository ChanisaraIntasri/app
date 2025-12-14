import 'dart:io';
import 'package:flutter/material.dart';

import 'package:flutter_application_1/models/citrus_tree_record.dart';
import 'package:flutter_application_1/pages/mainpage/tree_treatment_plan_page.dart';

const kPrimaryGreen = Color(0xFF005E33);
const kBg = Color.fromARGB(255, 255, 255, 255);
const kCardBg = Color(0xFFEDEDED);

class TreeHistoryPage extends StatefulWidget {
  final CitrusTreeRecord record;

  const TreeHistoryPage({super.key, required this.record});

  @override
  State<TreeHistoryPage> createState() => _TreeHistoryPageState();
}

class _TreeHistoryPageState extends State<TreeHistoryPage> {
  late CitrusTreeRecord _record;
  late String _recommendationDraft;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _recommendationDraft = _record.recommendation;
  }

  String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  void _saveAndPop() {
    final updated = _record.copyWith(
      recommendation: _recommendationDraft.trim(),
    );
    Navigator.pop(context, updated);
  }

  Future<void> _openPlan() async {
    final CitrusTreeRecord? updated = await Navigator.of(context).push<CitrusTreeRecord>(
      MaterialPageRoute(
        builder: (_) => TreeTreatmentPlanPage(record: _record),
      ),
    );

    if (updated == null) return;
    setState(() => _record = updated);
  }

  @override
  Widget build(BuildContext context) {
    final lastDisease = _record.disease.trim().isEmpty ? '-' : _record.disease.trim();
    final lastDate = _record.lastScanAt != null ? _fmtDate(_record.lastScanAt!) : '-';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: Text('ประวัติต้นส้ม: ${_record.name}'),
        actions: [
          TextButton(
            onPressed: _saveAndPop,
            child: const Text(
              'บันทึก',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        children: [
          // รูปล่าสุด (ถ้ามี)
          if (_record.lastScanImagePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.file(
                  File(_record.lastScanImagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: kCardBg,
                    alignment: Alignment.center,
                    child: const Text('ไม่สามารถแสดงรูปได้'),
                  ),
                ),
              ),
            )
          else
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: kCardBg,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Text('ยังไม่มีรูปการสแกน'),
            ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kCardBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('โรคล่าสุด', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('โรค: $lastDisease'),
                const SizedBox(height: 4),
                Text('วันที่สแกน: $lastDate'),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kCardBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('คำแนะนำการรักษา', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: _recommendationDraft,
                  onChanged: (v) => _recommendationDraft = v,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'เช่น ต้องพ่นยาทุก ๆ 3 วัน และตัดใบที่เป็นโรคออก',
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _openPlan,
              icon: const Icon(Icons.calendar_month),
              label: const Text(
                'แผนการรักษา (ปฏิทิน)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'ประวัติการสแกน',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),

          if (_record.scanHistory.isEmpty)
            Text(
              'ยังไม่มีประวัติการสแกน',
              style: TextStyle(color: Colors.grey[600]),
            )
          else
            ..._record.scanHistory.reversed.map((it) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: kPrimaryGreen.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.spa, color: kPrimaryGreen),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            it.disease,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _fmtDate(it.scannedAt),
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
