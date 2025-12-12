class CitrusTreeRecord {
  final String id;
  final String name;        // ชื่อต้น หรือ "ต้นที่ 1"
  final String disease;     // โรคที่พบ / อาการ
  final String recommendation; // คำแนะนำการดูแล
  final DateTime createdAt;

  CitrusTreeRecord({
    required this.id,
    required this.name,
    required this.disease,
    required this.recommendation,
    required this.createdAt,
  });
}
