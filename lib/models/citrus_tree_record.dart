import 'package:flutter/foundation.dart';

String dateKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

@immutable
class TreeScanItem {
  final String disease;

  // ✅ NEW: ระดับความรุนแรงของ “ผลสแกนครั้งนั้น”
  // แนะนำให้เก็บเป็น string เช่น "low", "medium", "high"
  // หรือ "1", "2", "3" ก็ได้ (ตามที่คุณใช้ในระบบ)
  final String severity;

  final DateTime scannedAt;
  final String? imagePath;

  const TreeScanItem({
    required this.disease,
    this.severity = 'unknown', // ✅ NEW: default เพื่อไม่ให้โค้ดเดิมพัง
    required this.scannedAt,
    this.imagePath,
  });

  TreeScanItem copyWith({
    String? disease,
    String? severity,
    DateTime? scannedAt,
    String? imagePath,
  }) {
    return TreeScanItem(
      disease: disease ?? this.disease,
      severity: severity ?? this.severity,
      scannedAt: scannedAt ?? this.scannedAt,
      imagePath: imagePath ?? this.imagePath,
    );
  }
}

@immutable
class CitrusTreeRecord {
  final String id;
  final String name;

  /// ✅ แปลง (กรอกหรือไม่ก็ได้)
  final String plot;

  /// ผลสแกนล่าสุด
  final String disease;

  // ✅ NEW: ระดับความรุนแรงของ “ผลสแกนล่าสุด”
  // ใช้ร่วมกับ disease เพื่อ grouping: "โรคเดียวกัน + severity เท่ากัน"
  final String severity;

  // ✅ NEW: วันตรวจพบโรค (diagnosed date)
  // ตาม requirement ของคุณ: "เริ่มนับวันรักษา" ใช้วันตรวจพบโรค
  // ถ้ายังไม่ set สามารถ fallback ไปใช้ lastScanAt ได้ตอนคำนวณ
  final DateTime? diagnosedAt;

  /// คำแนะนำการรักษา (ผู้ใช้กรอก/แก้ได้)
  final String recommendation;

  final String note;
  final DateTime createdAt;

  final DateTime? lastScanAt;
  final String? lastScanImagePath;

  /// ✅ ประวัติการสแกนหลายครั้ง
  final List<TreeScanItem> scanHistory;

  /// ✅ แผนการรักษา
  /// เช่น taskName="พ่นยา", everyDays=3, startDate=วันที่เริ่มนับ
  final String treatmentTaskName;
  final int treatmentEveryDays;
  final DateTime treatmentStartDate;

  // ✅ NEW: จำนวน “ครั้ง” ที่ต้องรักษา (เช่น 4 ครั้ง)
  // ถ้า = 0 แปลว่า "ไม่จำกัด/ยังไม่กำหนด" (ไว้กันโค้ดเดิมพัง)
  final int treatmentTotalTimes;

  /// เก็บวันที่ทำแล้วเป็น key "yyyy-MM-dd"
  final Set<String> treatmentDoneDates;

  const CitrusTreeRecord({
    required this.id,
    required this.name,
    required this.plot,
    required this.disease,

    this.severity = 'unknown', // ✅ NEW
    this.diagnosedAt,          // ✅ NEW

    required this.recommendation,
    required this.note,
    required this.createdAt,
    required this.lastScanAt,
    required this.lastScanImagePath,
    required this.scanHistory,
    required this.treatmentTaskName,
    required this.treatmentEveryDays,
    required this.treatmentStartDate,

    this.treatmentTotalTimes = 0, // ✅ NEW

    required this.treatmentDoneDates,
  });

  CitrusTreeRecord copyWith({
    String? id,
    String? name,
    String? plot,
    String? disease,

    String? severity,          // ✅ NEW
    DateTime? diagnosedAt,     // ✅ NEW (ตั้งค่าเป็นค่าใหม่ได้)
    bool clearDiagnosedAt = false, // ✅ NEW (ถ้าอยากล้างค่า)

    String? recommendation,
    String? note,
    DateTime? createdAt,
    DateTime? lastScanAt,
    String? lastScanImagePath,
    List<TreeScanItem>? scanHistory,
    String? treatmentTaskName,
    int? treatmentEveryDays,
    DateTime? treatmentStartDate,

    int? treatmentTotalTimes,  // ✅ NEW

    Set<String>? treatmentDoneDates,
  }) {
    return CitrusTreeRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      plot: plot ?? this.plot,
      disease: disease ?? this.disease,

      severity: severity ?? this.severity,
      diagnosedAt: clearDiagnosedAt ? null : (diagnosedAt ?? this.diagnosedAt),

      recommendation: recommendation ?? this.recommendation,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      lastScanImagePath: lastScanImagePath ?? this.lastScanImagePath,
      scanHistory: scanHistory ?? List<TreeScanItem>.from(this.scanHistory),
      treatmentTaskName: treatmentTaskName ?? this.treatmentTaskName,
      treatmentEveryDays: treatmentEveryDays ?? this.treatmentEveryDays,
      treatmentStartDate: treatmentStartDate ?? this.treatmentStartDate,

      treatmentTotalTimes: treatmentTotalTimes ?? this.treatmentTotalTimes,

      treatmentDoneDates:
          treatmentDoneDates ?? Set<String>.from(this.treatmentDoneDates),
    );
  }

  // ✅ NEW: helper key สำหรับ grouping (โรคเดียวกัน + severity เท่ากัน)
  String get diseaseSeverityKey => '${disease.trim()}__${severity.trim()}';

  // ✅ NEW: วันเริ่มนับตาม requirement (diagnosedAt เป็นหลัก)
  DateTime get diagnosedDateForPlan =>
      diagnosedAt ?? lastScanAt ?? createdAt;
}
