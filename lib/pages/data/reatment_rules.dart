//กติกาแผนรักษา” (เพราะไม่ตายตัว)
class TreatmentPlanRule {
  final String taskName;
  final int everyDays;
  final int totalTimes;
  const TreatmentPlanRule({
    required this.taskName,
    required this.everyDays,
    required this.totalTimes,
  });
}

class TreatmentRules {
  static const _default = TreatmentPlanRule(taskName: 'พ่นยา', everyDays: 3, totalTimes: 4);

  // ✅ คุณแก้ mapping ตรงนี้ได้ตามโรค/ความรุนแรงจริง
  static const Map<String, TreatmentPlanRule> _rules = {
    // key = "โรค__severity"
    'canker__high': TreatmentPlanRule(taskName: 'พ่นยา', everyDays: 3, totalTimes: 4),
    'canker__medium': TreatmentPlanRule(taskName: 'พ่นยา', everyDays: 5, totalTimes: 3),
    'canker__low': TreatmentPlanRule(taskName: 'พ่นยา', everyDays: 7, totalTimes: 2),
  };

  static TreatmentPlanRule getPlan({
    required String disease,
    required String severity,
  }) {
    final key = '${disease.trim().toLowerCase()}__${severity.trim().toLowerCase()}';
    return _rules[key] ?? _default;
  }
}
