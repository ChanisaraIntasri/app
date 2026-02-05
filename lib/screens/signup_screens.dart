import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'signin_screens.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  static const Color kBrandGreen = Color(0xFF005E33);

  static const String kRegisterUrl =
      'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api/auth/register.php';

  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;

  // ✅ สำหรับแจ้งเตือนแบบวงขอบแดง + ข้อความใต้ช่อง (ตามภาพตัวอย่าง)
  String? _nameServerError;
  String? _emailServerError;
  String? _passwordServerError;
  String? _formErrorText;

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  String _pickFirstString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  String _extractMessage(Map<String, dynamic> data) {
    final keys = ['message', 'msg', 'error_description', 'detail', 'error'];
    for (final k in keys) {
      final s = _pickFirstString(data[k]).trim();
      if (s.isNotEmpty) return s;
    }
    final errs = data['errors'];
    if (errs is List) {
      for (final e in errs) {
        final s = _pickFirstString(e).trim();
        if (s.isNotEmpty) return s;
      }
    }
    if (errs is Map) {
      for (final v in errs.values) {
        final s = _pickFirstString(v).trim();
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  String _friendlyRegisterError(http.Response res, Map<String, dynamic> data) {
    // ✅ ถ้า statusCode บอกชัด
    if (res.statusCode == 409) {
      return 'อีเมลนี้ถูกใช้งานแล้ว';
    }

    final rawCode = _pickFirstString(
      data['error_code'] ?? data['code'] ?? data['error'] ?? '',
    ).trim();
    final code = rawCode.toUpperCase();
    final serverMsg = _extractMessage(data);
    final low = serverMsg.toLowerCase();

    // โค้ดจาก backend หลายแบบ
    if (code.contains('EMAIL_EXISTS') ||
        code.contains('EMAIL_ALREADY') ||
        code.contains('DUPLICATE') ||
        code.contains('ALREADY_EXISTS')) {
      return 'อีเมลนี้ถูกใช้งานแล้ว';
    }
    if (code.contains('WEAK_PASSWORD') || code.contains('PASSWORD_TOO_SHORT')) {
      return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
    }

    // จับจากข้อความ (เช่น MySQL duplicate)
    if (low.contains('duplicate') &&
        (low.contains('email') || low.contains('entry'))) {
      return 'อีเมลนี้ถูกใช้งานแล้ว';
    }

    if (serverMsg.isNotEmpty && serverMsg.length <= 140) {
      return serverMsg;
    }

    return 'สมัครสมาชิกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: kBrandGreen, width: 2),
      ),
      // ✅ ขอบแดงตอน error (เหมือนภาพตัวอย่าง)
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    );
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  void _goToSignIn() {
    if (_loading) return;
    // ถ้าหน้านี้ถูก push มาจาก login ให้ pop กลับจะเนียนกว่า
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
    );
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    // ✅ เคลียร์ error เก่าก่อน validate
    setState(() {
      _nameServerError = null;
      _emailServerError = null;
      _passwordServerError = null;
      _formErrorText = null;
    });

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final res = await http
          .post(
            Uri.parse(kRegisterUrl),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'username': _nameCtl.text.trim(),
              'email': _emailCtl.text.trim(),
              'password': _passCtl.text,
            }),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> data = {};
      try {
        if (res.body.isNotEmpty) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) data = decoded;
        }
      } catch (_) {
        // body ไม่ใช่ JSON
      }

      final success = (res.statusCode >= 200 && res.statusCode < 300) &&
          (data['ok'] == true || data['status']?.toString() == 'success');

      if (success) {
        if (!mounted) return;
        // ✅ บันทึกว่าเป็นการสมัครใหม่ เพื่อให้ครั้งแรกที่เข้าสู่ระบบพาไปหน้า Share
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString("pending_first_login_email", _emailCtl.text.trim().toLowerCase());
        } catch (_) {}

        // ✅ ไม่ใช้ SnackBar (ตามที่ขอ) -> เด้งกลับหน้าเข้าสู่ระบบเลย
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SignInScreen()),
          (route) => false,
        );
      } else {
        final msg = _friendlyRegisterError(res, data);

        if (!mounted) return;

        setState(() {
          if (msg == 'อีเมลนี้ถูกใช้งานแล้ว') {
            _emailServerError = msg;
          } else if (msg == 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร') {
            _passwordServerError = msg;
          } else {
            _formErrorText = msg;
          }
        });

        // กระตุ้นให้แสดงข้อความใต้ช่องทันที
        _formKey.currentState?.validate();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _formErrorText = 'เครือข่ายมีปัญหา กรุณาลองใหม่อีกครั้ง';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Transform.translate(
                        offset: const Offset(0, -28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'สมัครสมาชิก',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'สร้างบัญชีเพื่อเริ่มใช้งาน',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.black54,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 24),

                            TextFormField(
                              controller: _nameCtl,
                              textInputAction: TextInputAction.next,
                              decoration: _decoration('ชื่อผู้ใช้'),
                              onChanged: (_) {
                                if (_nameServerError != null ||
                                    _formErrorText != null) {
                                  setState(() {
                                    _nameServerError = null;
                                    _formErrorText = null;
                                  });
                                }
                              },
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'กรุณากรอกชื่อผู้ใช้';
                                }
                                return _nameServerError;
                              },
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _emailCtl,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: _decoration('อีเมล'),
                              onChanged: (_) {
                                if (_emailServerError != null ||
                                    _formErrorText != null) {
                                  setState(() {
                                    _emailServerError = null;
                                    _formErrorText = null;
                                  });
                                }
                              },
                              validator: (v) {
                                final value = v?.trim() ?? '';
                                if (value.isEmpty) return 'กรุณากรอกอีเมล';
                                if (!_isValidEmail(value)) {
                                  return 'รูปแบบอีเมลไม่ถูกต้อง';
                                }
                                return _emailServerError; // ✅ อีเมลซ้ำ
                              },
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _passCtl,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              decoration: _decoration('รหัสผ่าน').copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: kBrandGreen,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              onChanged: (_) {
                                if (_passwordServerError != null ||
                                    _formErrorText != null) {
                                  setState(() {
                                    _passwordServerError = null;
                                    _formErrorText = null;
                                  });
                                }
                              },
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'กรุณากรอกรหัสผ่าน';
                                }
                                if (v.length < 6) {
                                  return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                                }
                                return _passwordServerError;
                              },
                              onFieldSubmitted: (_) {
                                if (!_loading) _register();
                              },
                            ),

                            const SizedBox(height: 16),

                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _register,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kBrandGreen,
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
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
                                        'สมัครสมาชิก',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),

                            // ✅ แจ้งเตือนแบบข้อความสีแดง (กรณีไม่ผูกกับช่องใดช่องหนึ่ง)
                            if (_formErrorText != null &&
                                (_formErrorText ?? '').trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _formErrorText!,
                                  textAlign: TextAlign.left,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),

                            Center(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text(
                                    'มีบัญชีแล้ว? ',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: _loading ? null : _goToSignIn,
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        'เข้าสู่ระบบ',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _loading
                                              ? Colors.black38
                                              : kBrandGreen,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}