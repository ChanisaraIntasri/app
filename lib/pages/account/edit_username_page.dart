import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// สีเขียวหลัก
const Color kPrimaryGreen = Color(0xFF005E33);

// URL API สำหรับอัปเดตชื่อผู้ใช้ + รหัสผ่าน
const String kUpdateProfileUrl =
    'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api/auth/update_profile.php';

class EditUsernamePage extends StatefulWidget {
  final String initialUsername; // ชื่อเดิมของผู้ใช้

  const EditUsernamePage({
    super.key,
    required this.initialUsername,
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

  @override
  void initState() {
    super.initState();
    // เอาชื่อเดิมมาใส่ในช่องกรอก
    _usernameCtl = TextEditingController(text: widget.initialUsername);
    _currentPwdCtl = TextEditingController();
    _newPwdCtl = TextEditingController();
    _confirmPwdCtl = TextEditingController();
  }

  @override
  void dispose() {
    _usernameCtl.dispose();
    _currentPwdCtl.dispose();
    _newPwdCtl.dispose();
    _confirmPwdCtl.dispose();
    super.dispose();
  }

  /// สร้าง style ของช่องกรอก (กรอบโค้งมน + ขอบเขียวตอนโฟกัส)
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
        borderSide: BorderSide(
          color: Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        borderSide: BorderSide(
          color: kPrimaryGreen,
          width: 2,
        ),
      ),
    );
  }

  /// แสดงกล่องแจ้งเตือนกลางหน้าจอ
  Future<void> _showErrorDialog(String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'แจ้งเตือน',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          message,
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'ตกลง',
              style: TextStyle(color: kPrimaryGreen),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // เช็คฟอร์ม ถ้าไม่ผ่าน แสดง dialog กลางจอ
    if (!(_formKey.currentState?.validate() ?? false)) {
      await _showErrorDialog('กรุณาตรวจสอบข้อมูลให้ถูกต้องและครบถ้วน');
      return;
    }

    setState(() => _loading = true);

    try {
      final newUsername = _usernameCtl.text.trim();
      final currentPassword = _currentPwdCtl.text;
      final newPassword = _newPwdCtl.text.trim();
      final confirmPassword = _confirmPwdCtl.text.trim();

      // เตรียม body สำหรับส่งไป API
      final Map<String, dynamic> body = {
        "username": newUsername,
      };

      // ถ้ามีการกรอกรหัสผ่านใหม่ (ถือว่า user ต้องการเปลี่ยนรหัส)
      if (newPassword.isNotEmpty || confirmPassword.isNotEmpty) {
        body["current_password"] = currentPassword;
        body["new_password"] = newPassword;
      }

      final res = await http.post(
        Uri.parse(kUpdateProfileUrl),
        headers: {
          "Content-Type": "application/json; charset=utf-8",
        },
        body: jsonEncode(body),
      );

      if (res.statusCode != 200) {
        throw Exception("HTTP ${res.statusCode}");
      }

      final data = jsonDecode(res.body);

      // { "status": "success", "message": "อัปเดตสำเร็จ", ... }
      if (data["status"] == "success") {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data["message"]?.toString() ?? "อัปเดตข้อมูลสำเร็จ",
            ),
            backgroundColor: kPrimaryGreen,
          ),
        );

        // ส่งชื่อใหม่กลับไปหน้า Setting ให้ไปอัปเดต UI ต่อ
        Navigator.pop(context, newUsername);
      } else {
        final msg = data["message"]?.toString() ?? "อัปเดตไม่สำเร็จ";
        await _showErrorDialog(msg);
      }
    } catch (e) {
      await _showErrorDialog('เกิดข้อผิดพลาดในการอัปเดตข้อมูล\n$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: const Text('แก้ไขโปรไฟล์'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== ส่วนแก้ไขชื่อผู้ใช้ =====
                const Text(
                  'ข้อมูลบัญชี',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: kPrimaryGreen,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameCtl,
                  decoration: _inputDecoration('ชื่อผู้ใช้'),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'กรุณากรอกชื่อผู้ใช้';
                    if (t.length < 3) return 'ต้องมีอย่างน้อย 3 ตัวอักษร';
                    return null;
                  },
                ),

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // ===== ส่วนเปลี่ยนรหัสผ่าน =====
                const Text(
                  'เปลี่ยนรหัสผ่าน (ไม่บังคับ)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: kPrimaryGreen,
                  ),
                ),
                const SizedBox(height: 12),

                // รหัสผ่านปัจจุบัน
                TextFormField(
                  controller: _currentPwdCtl,
                  obscureText: _obscureCurrent,
                  decoration: _inputDecoration('รหัสผ่านปัจจุบัน').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureCurrent
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureCurrent = !_obscureCurrent;
                        });
                      },
                    ),
                  ),
                  validator: (v) {
                    final newPwd = _newPwdCtl.text;
                    final confirmPwd = _confirmPwdCtl.text;
                    final cur = v ?? '';

                    // ถ้ามีการกรอกรหัสผ่านใหม่/ยืนยัน ต้องบังคับให้ใส่รหัสผ่านปัจจุบัน
                    if (newPwd.isNotEmpty || confirmPwd.isNotEmpty) {
                      if (cur.isEmpty) {
                        return 'กรุณากรอกรหัสผ่านปัจจุบัน';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // รหัสผ่านใหม่
                TextFormField(
                  controller: _newPwdCtl,
                  obscureText: _obscureNew,
                  decoration: _inputDecoration('รหัสผ่านใหม่').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNew ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureNew = !_obscureNew;
                        });
                      },
                    ),
                  ),
                  validator: (v) {
                    final t = v ?? '';
                    final confirmPwd = _confirmPwdCtl.text;

                    // ถ้าผู้ใช้ไม่กรอกรหัสใหม่เลย (ทั้ง new + confirm ว่าง) แปลว่าไม่เปลี่ยนรหัสผ่าน -> ผ่าน
                    if (t.isEmpty && confirmPwd.isEmpty) {
                      return null;
                    }

                    // ถ้าเริ่มจะเปลี่ยนรหัส ต้องเช็คความยาว
                    if (t.length < 6) {
                      return 'รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ยืนยันรหัสผ่านใหม่
                TextFormField(
                  controller: _confirmPwdCtl,
                  obscureText: _obscureConfirm,
                  decoration: _inputDecoration('ยืนยันรหัสผ่านใหม่').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirm = !_obscureConfirm;
                        });
                      },
                    ),
                  ),
                  validator: (v) {
                    final newPwd = _newPwdCtl.text;
                    final confirm = v ?? '';

                    // ถ้าทั้ง new/confirm ว่าง แปลว่าไม่เปลี่ยนรหัสผ่าน
                    if (newPwd.isEmpty && confirm.isEmpty) {
                      return null;
                    }

                    if (confirm.isEmpty) {
                      return 'กรุณายืนยันรหัสผ่านใหม่';
                    }

                    if (confirm != newPwd) {
                      return 'รหัสผ่านใหม่และการยืนยันไม่ตรงกัน';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // ===== ปุ่มบันทึก =====
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'บันทึก',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
