import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// สีเขียวหลัก
const Color kPrimaryGreen = Color(0xFF005E33);

// URL API สำหรับอัปเดตชื่อผู้ใช้ + รหัสผ่าน
const String kUpdateProfileUrl =
    'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api/auth/update_profile.php';

// ✅ key ที่ใช้เก็บ token ใน SharedPreferences (ต้องใช้ให้ “ตรงกันทั้งแอป”)
const String kPrefTokenKey = 'token';
// (รองรับของเดิม) ถ้าเคยเซฟเป็น auth_token มาก่อน
const String kPrefTokenLegacyKey = 'auth_token';

class EditUsernamePage extends StatefulWidget {
  final String initialUsername;

  // ✅ ส่ง token มาก็ได้ (แนะนำ) หรือปล่อยว่างให้หน้าอ่านจาก SharedPreferences
  final String? token;

  const EditUsernamePage({
    super.key,
    required this.initialUsername,
    this.token,
  });

  @override
  State<EditUsernamePage> createState() => _EditUsernamePageState();
}

class _EditUsernamePageState extends State<EditUsernamePage> {
  late TextEditingController _usernameCtl;
  late TextEditingController _currentPwdCtl;
  late TextEditingController _newPwdCtl;
  late TextEditingController _confirmPwdCtl;

  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  String _token = ''; // ✅ token ที่จะใช้ยิง API

  @override
  void initState() {
    super.initState();
    _usernameCtl = TextEditingController(text: widget.initialUsername);
    _currentPwdCtl = TextEditingController();
    _newPwdCtl = TextEditingController();
    _confirmPwdCtl = TextEditingController();

    _initToken();
  }

  Future<void> _initToken() async {
    // 1) ใช้ token ที่ส่งมาจากหน้าก่อนหน้า (ถ้ามี)
    final fromNav = (widget.token ?? '').trim();
    if (fromNav.isNotEmpty) {
      setState(() => _token = fromNav);
      return;
    }

    // 2) ถ้าไม่ส่งมา ให้ดึงจาก SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(kPrefTokenKey) ??
            prefs.getString(kPrefTokenLegacyKey) ??
            '')
        .trim();

    // ถ้าเจอจาก key เดิม → copy มาเก็บใน key ใหม่ด้วย (ให้ตรงกันทั้งแอป)
    if (saved.isNotEmpty &&
        (prefs.getString(kPrefTokenKey) ?? '').trim().isEmpty) {
      await prefs.setString(kPrefTokenKey, saved);
    }

    if (mounted) setState(() => _token = saved);

    debugPrint('token(fromNav)=$fromNav');
    debugPrint('token(fromPrefs)=$saved');
  }

  @override
  void dispose() {
    _usernameCtl.dispose();
    _currentPwdCtl.dispose();
    _newPwdCtl.dispose();
    _confirmPwdCtl.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        borderSide: BorderSide(color: kPrimaryGreen, width: 2),
      ),
    );
  }

  Future<void> _showErrorDialog(String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('แจ้งเตือน',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(message, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ตกลง', style: TextStyle(color: kPrimaryGreen)),
          ),
        ],
      ),
    );
  }

  String _prettyMessage(dynamic msg) {
    if (msg == null) return '';
    final s = msg.toString().trim();
    if (s.isEmpty) return '';
    return s;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final newUsername = _usernameCtl.text.trim();
    final currentPassword = _currentPwdCtl.text;
    final newPassword = _newPwdCtl.text;
    final confirmPassword = _confirmPwdCtl.text;

    if (_token.trim().isEmpty) {
      await _showErrorDialog(
          'ไม่พบข้อมูลการเข้าสู่ระบบ (token)\nกรุณาเข้าสู่ระบบใหม่อีกครั้ง');
      return;
    }

    // ถ้าจะเปลี่ยนรหัสผ่าน → ต้องกรอกครบ และยืนยันตรงกัน
    final wantChangePassword =
        currentPassword.isNotEmpty || newPassword.isNotEmpty || confirmPassword.isNotEmpty;

    if (wantChangePassword) {
      if (currentPassword.isEmpty ||
          newPassword.isEmpty ||
          confirmPassword.isEmpty) {
        await _showErrorDialog('หากต้องการเปลี่ยนรหัสผ่าน กรุณากรอกให้ครบทุกช่อง');
        return;
      }
      if (newPassword != confirmPassword) {
        await _showErrorDialog('รหัสผ่านใหม่และยืนยันรหัสผ่านไม่ตรงกัน');
        return;
      }
      if (newPassword.length < 6) {
        await _showErrorDialog('รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร');
        return;
      }
    }

    setState(() => _loading = true);

    try {
      final body = <String, dynamic>{
        'username': newUsername,
      };

      if (wantChangePassword) {
        body['current_password'] = currentPassword;
        body['new_password'] = newPassword;
      }

      final res = await http.post(
        Uri.parse(kUpdateProfileUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode(body),
      );

      Map<String, dynamic>? decoded;
      try {
        decoded = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        decoded = null;
      }

      final ok = decoded != null && decoded!['ok'] == true;

      if (res.statusCode == 200 && ok) {
        final dataObj = decoded!['data'];
        final updatedUsername =
            (dataObj is Map<String, dynamic> && dataObj['username'] != null)
                ? dataObj['username'].toString()
                : newUsername;

        final msg = (dataObj is Map<String, dynamic>)
            ? _prettyMessage(dataObj['message'])
            : 'อัปเดตข้อมูลสำเร็จ';

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: kPrimaryGreen),
        );

        // ✅ อัปเดตชื่อใน SharedPreferences ด้วย
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', updatedUsername);

        Navigator.pop(context, updatedUsername);
        return;
      }

      final msg = _prettyMessage(decoded?['message']);
      if (res.statusCode == 401) {
        await _showErrorDialog('หมดอายุการเข้าสู่ระบบ/ยังไม่ได้ล็อกอิน\n$msg');
        return;
      }

      await _showErrorDialog('อัปเดตไม่สำเร็จ (HTTP ${res.statusCode})\n$msg');
    } catch (e) {
      await _showErrorDialog('เครือข่ายมีปัญหา กรุณาลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F4F4),
        elevation: 0,
        title: const Text(
          'แก้ไขโปรไฟล์',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFEFEF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ข้อมูลบัญชี',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _usernameCtl,
                    decoration: _inputDecoration('ชื่อผู้ใช้'),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return 'กรุณากรอกชื่อผู้ใช้';
                      if (t.length < 3) return 'ชื่อผู้ใช้ต้องมีอย่างน้อย 3 ตัวอักษร';
                      return null;
                    },
                  ),

                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 10),

                  const Text(
                    'เปลี่ยนรหัสผ่าน (ไม่บังคับ)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _currentPwdCtl,
                    obscureText: _obscureCurrent,
                    decoration: _inputDecoration('รหัสผ่านเดิม').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureCurrent
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: kPrimaryGreen,
                        ),
                        onPressed: () =>
                            setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _newPwdCtl,
                    obscureText: _obscureNew,
                    decoration: _inputDecoration('รหัสผ่านใหม่').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNew ? Icons.visibility_off : Icons.visibility,
                          color: kPrimaryGreen,
                        ),
                        onPressed: () =>
                            setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _confirmPwdCtl,
                    obscureText: _obscureConfirm,
                    decoration:
                        _inputDecoration('ยืนยันรหัสผ่านใหม่').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: kPrimaryGreen,
                        ),
                        onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'บันทึก',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color.fromARGB(255, 252, 250, 250),
                              ),
                            ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
