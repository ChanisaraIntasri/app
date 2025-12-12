
class CitrusTreeRecord {
  final String id;
  final String name;            // ชื่อต้น หรือ "ต้นที่ 1"
  final String disease;         // โรคที่พบ / อาการ (มาจากโมเดล หรือว่างได้)
  final String recommendation;  // คำแนะนำการดูแล (มาจากโมเดล หรือว่างได้)
  final String note;            // โน้ตที่ผู้ใช้บันทึกเอง
  final DateTime createdAt;

  const CitrusTreeRecord({
    required this.id,
    required this.name,
    this.disease = '',          // ถ้าไม่ส่งมาจะเป็นสตริงว่าง
    this.recommendation = '',   // ถ้าไม่ส่งมาจะเป็นสตริงว่าง
    this.note = '',             // ถ้าไม่ส่งมาจะเป็นสตริงว่าง
    required this.createdAt,
  });
}
