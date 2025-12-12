// lib/services/citrus_model_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class CitrusModelApi {
  static final Uri _endpoint = Uri.parse(
    'https://citusmodelapione-production.up.railway.app/v1/predict',
  );

  /// ส่งรูปไปโมเดลแบบ multipart/form-data
  static Future<Map<String, dynamic>> predictFromBytes(
    List<int> bytes, {
    String filename = 'image.jpg',
  }) async {
    final req = http.MultipartRequest('POST', _endpoint)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file', // เปลี่ยนถ้า backend ใช้ key อื่น
          bytes,
          filename: filename,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      throw Exception('Predict failed (${res.statusCode}): ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
