import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
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

      final Map<String, dynamic> data =
          res.body.isEmpty ? {} : (jsonDecode(res.body) as Map<String, dynamic>);

      final success = data['ok'] == true;

      if (success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('สมัครสมาชิกสำเร็จ กรุณาเข้าสู่ระบบ')),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SignInScreen()),
          (route) => false,
        );
      } else {
        final code = (data['error'] ?? '').toString();
        String msg;
        switch (code) {
          case 'EMAIL_EXISTS':
            msg = 'อีเมลนี้ถูกใช้แล้ว';
            break;
          case 'WEAK_PASSWORD':
            msg = 'รหัสผ่านสั้นเกินไป';
            break;
          default:
            msg = code.isEmpty ? 'สมัครสมาชิกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง' : code;
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เครือข่ายมีปัญหา กรุณาลองใหม่อีกครั้ง')),
      );
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
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'กรุณากรอกชื่อผู้ใช้';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _emailCtl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: _decoration('อีเมล'),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return 'กรุณากรอกอีเมล';
                              if (!_isValidEmail(value)) {
                                return 'รูปแบบอีเมลไม่ถูกต้อง';
                              }
                              return null;
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
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'กรุณากรอกรหัสผ่าน';
                              }
                              if (v.length < 6) {
                                return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _register(),
                          ),

                          // ✅ ระยะห่างปุ่มสีเขียว “เหมือนหน้าเข้าสู่ระบบ”
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

                          const SizedBox(height: 16),

                          // ✅ เปลี่ยนจากปุ่มเป็นข้อความ + ไม่มีขีดเส้นใต้
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
              );
            },
          ),
        ),
      ),
    );
  }
}
