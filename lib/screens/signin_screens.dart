import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/pages/mainpage/main_nav.dart';
import 'package:flutter_application_1/screens/signup_screens.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  static const kBrandGreen = Color(0xFF005E33);
  static const String kLoginUrl =
      'https://latricia-nonodoriferous-snoopily.ngrok-free.dev/crud/api/auth/login.php';

  static const String kPrefTokenKey = 'token';
  static const String kPrefTokenLegacyKey = 'auth_token';

  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: kBrandGreen, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      );

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    try {
      final res = await http
          .post(
            Uri.parse(kLoginUrl),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'email': _emailCtl.text.trim(),
              'password': _passCtl.text,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final Map<String, dynamic> data =
          res.body.isEmpty ? {} : (jsonDecode(res.body) as Map<String, dynamic>);

      final success =
          (data['ok'] == true) || (data['status']?.toString() == 'success');

      if (success) {
        final dynamic userRaw = data['user'] ?? data['data'];

        String username;
        int? userId;
        String token = '';

        if (userRaw is Map<String, dynamic>) {
          token = (userRaw['token'] ?? '').toString();

          username = (userRaw['usernืame'] ??
                  userRaw['name'] ??
                  userRaw['email'] ??
                  '')
              .toString();

          final idRaw = userRaw['id'] ?? userRaw['user_id'];
          if (idRaw is int) {
            userId = idRaw;
          } else if (idRaw is String) {
            userId = int.tryParse(idRaw);
          }
        } else {
          username = _emailCtl.text.trim();
        }

        if (username.isEmpty) username = _emailCtl.text.trim();

        if (token.isEmpty) {
          token = (data['token'] ?? data['session_id'] ?? '').toString();
        }

        final prefs = await SharedPreferences.getInstance();

        if (token.isNotEmpty) {
          await prefs.setString(kPrefTokenKey, token);
          await prefs.setString(kPrefTokenLegacyKey, token);
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('เข้าสู่ระบบสำเร็จ แต่ไม่พบข้อมูล token'),
              duration: Duration(seconds: 3),
            ),
          );
        }

        if (userId != null) {
          await prefs.setInt('user_id', userId);
        }
        await prefs.setString('username', username);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เข้าสู่ระบบสำเร็จ')),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MainNav(initialUsername: username),
          ),
          (route) => false,
        );
      } else {
        final serverMsg = (data['error']?.toString().trim().isNotEmpty ?? false)
            ? data['error'].toString()
            : null;

        final msg =
            serverMsg ?? 'เข้าสู่ระบบไม่สำเร็จ กรุณาตรวจสอบอีเมลหรือรหัสผ่าน';

        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
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

  void _goToSignUp() {
    if (_loading) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
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
              final double topGap =
                  (constraints.maxHeight * 0.12).clamp(56.0, 120.0);

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
                        mainAxisAlignment: MainAxisAlignment.start, // ✅ ขยับขึ้น
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: topGap), // ✅ เว้นระยะด้านบนแบบสมดุล

                          const Text(
                            'เข้าสู่ระบบ',
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
                            'เข้าสู่ระบบเพื่อเริ่มใช้งาน',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.black54,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 24),

                          TextFormField(
                            controller: _emailCtl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: _dec('อีเมล'),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'กรุณากรอกอีเมล';
                              if (!_isValidEmail(t)) {
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
                            decoration: _dec('รหัสผ่าน').copyWith(
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
                            onFieldSubmitted: (_) => _login(),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'กรุณากรอกรหัสผ่าน';
                              }
                              if (v.length < 6) {
                                return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _login,
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
                                      'เข้าสู่ระบบ',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
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
                                  'ยังไม่ได้เป็นสมาชิก? ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                InkWell(
                                  onTap: _loading ? null : _goToSignUp,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'สมัครสมาชิก',
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

                          const SizedBox(height: 24),
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
