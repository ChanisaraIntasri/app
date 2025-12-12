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
        // ===========================
        // ✅ ดึงข้อมูลจาก response
        // ===========================
        // Backend ส่ง: { status: "success", data: { id, email, token, ... } }
        final dynamic userRaw = data['user'] ?? data['data'];

        String username;
        int? userId;
        String token = '';

        if (userRaw is Map<String, dynamic>) {
          // ✅ ดึง token จาก userRaw (อยู่ภายใน data object)
          token = (userRaw['token'] ?? '').toString();
          
          username = (userRaw['username'] ??
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
        
        if (username.isEmpty) {
          username = _emailCtl.text.trim();
        }

        // ถ้ายังไม่ได้ token ให้ลองดึงจาก level บนสุด
        if (token.isEmpty) {
          token = (data['token'] ?? data['session_id'] ?? '').toString();
        }

        debugPrint('✅ Login success');
        debugPrint('   username = $username');
        debugPrint('   user_id = $userId');
        debugPrint('🔑 token = $token');

        // ===========================
        // ✅ เก็บ token ลง SharedPreferences
        // ===========================
        final prefs = await SharedPreferences.getInstance();
        
        if (token.isNotEmpty) {
          await prefs.setString('auth_token', token);
          debugPrint('💾 Saved token to SharedPreferences');
        } else {
          debugPrint('⚠️ WARNING: No token found in response!');
          debugPrint('   Full response: $data');
          
          // แจ้งเตือนผู้ใช้
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('เข้าสู่ระบบสำเร็จ แต่ไม่พบ token (อาจมีปัญหาการบันทึกข้อมูล)'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        
        if (userId != null) {
          await prefs.setInt('user_id', userId);
        }
        await prefs.setString('username', username);

        // ===========================
        // ไปหน้า MainNav
        // ===========================
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in successfully')),
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
        final msg = serverMsg ?? 'Login failed (${res.statusCode})';

        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error: $e')),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 50),

                  const Text(
                    'Login OR Signup',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _emailCtl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: _dec('Email address'),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return 'Please enter email';
                      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(t);
                      return ok ? null : 'Email is invalid';
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _passCtl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    decoration: _dec('Password').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: kBrandGreen,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onFieldSubmitted: (_) => _login(),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter password';
                      }
                      if (v.length < 6) {
                        return 'At least 6 characters';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black87,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text(
                        'Forget password?',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
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
                              'Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: const [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.mail_outline,
                            size: 22,
                            color: Colors.black87,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Continue with Google',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SignUpScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kBrandGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: const Text(
                        'Sign up',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}