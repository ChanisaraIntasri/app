import 'dart:convert';
import 'package:http/http.dart' as http;

class CareLog {
  final int? logId;
  final int treeId;
  final DateTime careDate;
  final String careType;
  final bool isReminder;
  final bool done;
  final String? note;
  final String? productName;
  final double? amount;
  final String? unit;
  final String? area;

  CareLog({
    this.logId,
    required this.treeId,
    required this.careDate,
    required this.careType,
    required this.isReminder,
    required this.done,
    this.note,
    this.productName,
    this.amount,
    this.unit,
    this.area,
  });

  factory CareLog.fromJson(Map<String, dynamic> json) {
    bool _toBool(dynamic v) =>
        v == true || v == 1 || v == "1" || v == "true";

    return CareLog(
      logId: json['log_id'] != null ? int.tryParse("${json['log_id']}") : null,
      treeId: int.tryParse("${json['tree_id']}") ?? 1,
      careDate: DateTime.parse(json['care_date']),
      careType: json['care_type'] as String,
      isReminder: _toBool(json['is_reminder']),
      done: _toBool(json['is_done']),
      note: json['note'] as String?,
      productName: json['product_name'] as String?,
      amount: json['amount'] != null
          ? double.tryParse("${json['amount']}")
          : null,
      unit: json['unit'] as String?,
      area: json['area'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (logId != null) 'log_id': logId,
      'tree_id': treeId,
      'care_date': careDate.toIso8601String().split('T')[0], // yyyy-MM-dd
      'care_type': careType,
      'is_reminder': isReminder,
      'is_done': done,
      if (note != null) 'note': note,
      if (productName != null) 'product_name': productName,
      if (amount != null) 'amount': amount,
      if (unit != null) 'unit': unit,
      if (area != null) 'area': area,
    };
  }
}

class CareLogsApi {
  static const String _base =
      'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api/care_logs';

  static Map<String, String> _jsonHeaders(String token) => {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
      };

  static Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
      };

  /// ตรวจสอบว่า response สำเร็จหรือไม่
  static bool _isSuccess(Map<String, dynamic> json) {
    return json['ok'] == true ||
        json['status'] == 'success' ||
        json['success'] == true;
  }

  /// สร้าง care_log ใหม่
  static Future<CareLog> create(
    CareLog log, {
    required String token,
  }) async {
    final uri = Uri.parse('$_base/create_care_logs.php');

    print('📤 Creating care log: ${log.toJson()}');

    final res = await http.post(
      uri,
      headers: _jsonHeaders(token),
      body: jsonEncode(log.toJson()),
    );

    print('📤 Response: ${res.statusCode}');
    print('📤 Body: ${res.body}');

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final json = jsonDecode(res.body);

    if (!_isSuccess(json)) {
      throw Exception(
          json['message'] ?? json['error'] ?? 'สร้าง care_log ไม่สำเร็จ');
    }

    return CareLog.fromJson(json['data']);
  }

  /// ดึงรายการ care_logs ทั้งหมด (รองรับ filter เบื้องต้น)
  static Future<List<CareLog>> getAll({
    required String token,
    int? treeId,
    String? careType,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final queryParams = <String, String>{};

    if (treeId != null) queryParams['tree_id'] = treeId.toString();
    if (careType != null) queryParams['care_type'] = careType;
    if (fromDate != null) {
      queryParams['from_date'] = fromDate.toIso8601String().split('T')[0];
    }
    if (toDate != null) {
      queryParams['to_date'] = toDate.toIso8601String().split('T')[0];
    }

    final urlsToTry = [
      '$_base/get_care_logs.php',
      '$_base/read_care_logs.php',
    ];

    for (final baseUrl in urlsToTry) {
      try {
        final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);
        print('📥 Trying: $uri');

        final res = await http.get(
          uri,
          headers: _authHeaders(token),
        );

        print('📥 Response: ${res.statusCode}');

        if (res.statusCode == 404) {
          print('⚠️ 404 - Trying next URL...');
          continue;
        }

        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}: ${res.body}');
        }

        print('📥 Body: ${res.body}');

        final json = jsonDecode(res.body);

        if (!_isSuccess(json)) {
          throw Exception(json['message'] ??
              json['error'] ??
              'อ่าน care_logs ไม่สำเร็จ');
        }

        final List data = json['data'] as List;
        print('✅ Found ${data.length} care logs');

        return data.map((e) => CareLog.fromJson(e)).toList();
      } catch (e) {
        if (baseUrl == urlsToTry.last) {
          rethrow;
        }
        print('⚠️ Error: $e - Trying next URL...');
      }
    }

    throw Exception('ไม่พบ API endpoint ที่ใช้งานได้');
  }

  /// อัปเดต is_done
  static Future<void> updateDone(
    int logId,
    bool done, {
    required String token,
  }) async {
    final uri = Uri.parse('$_base/update_care_logs.php');

    final res = await http.post(
      uri,
      headers: _jsonHeaders(token),
      body: jsonEncode({
        'log_id': logId,
        'is_done': done,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final json = jsonDecode(res.body);
    if (!_isSuccess(json)) {
      throw Exception(json['message'] ??
          json['error'] ??
          'อัปเดต care_log ไม่สำเร็จ');
    }
  }

  /// ลบ care_log
  static Future<void> delete(
    int logId, {
    required String token,
  }) async {
    final uri = Uri.parse('$_base/delete_care_logs.php?log_id=$logId');

    final res = await http.get(
      uri,
      headers: _authHeaders(token),
    );

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final json = jsonDecode(res.body);
    if (!_isSuccess(json)) {
      throw Exception(
          json['message'] ?? json['error'] ?? 'ลบ care_log ไม่สำเร็จ');
    }
  }
}
