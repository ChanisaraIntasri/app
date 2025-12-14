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
  final DateTime scannedAt;
  final String? imagePath;

  const TreeScanItem({
    required this.disease,
    required this.scannedAt,
    this.imagePath,
  });
}

@immutable
class CitrusTreeRecord {
  final String id;
  final String name;

  /// ✅ แปลง (กรอกหรือไม่ก็ได้)
  final String plot;

  /// ผลสแกนล่าสุด
  final String disease;

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

  /// เก็บวันที่ทำแล้วเป็น key "yyyy-MM-dd"
  final Set<String> treatmentDoneDates;

  const CitrusTreeRecord({
    required this.id,
    required this.name,
    required this.plot,
    required this.disease,
    required this.recommendation,
    required this.note,
    required this.createdAt,
    required this.lastScanAt,
    required this.lastScanImagePath,
    required this.scanHistory,
    required this.treatmentTaskName,
    required this.treatmentEveryDays,
    required this.treatmentStartDate,
    required this.treatmentDoneDates,
  });

  CitrusTreeRecord copyWith({
    String? id,
    String? name,
    String? plot,
    String? disease,
    String? recommendation,
    String? note,
    DateTime? createdAt,
    DateTime? lastScanAt,
    String? lastScanImagePath,
    List<TreeScanItem>? scanHistory,
    String? treatmentTaskName,
    int? treatmentEveryDays,
    DateTime? treatmentStartDate,
    Set<String>? treatmentDoneDates,
  }) {
    return CitrusTreeRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      plot: plot ?? this.plot,
      disease: disease ?? this.disease,
      recommendation: recommendation ?? this.recommendation,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      lastScanImagePath: lastScanImagePath ?? this.lastScanImagePath,
      scanHistory: scanHistory ?? List<TreeScanItem>.from(this.scanHistory),
      treatmentTaskName: treatmentTaskName ?? this.treatmentTaskName,
      treatmentEveryDays: treatmentEveryDays ?? this.treatmentEveryDays,
      treatmentStartDate: treatmentStartDate ?? this.treatmentStartDate,
      treatmentDoneDates: treatmentDoneDates ?? Set<String>.from(this.treatmentDoneDates),
    );
  }
}
