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

  // ✅ สำหรับแจ้งเตือนแบบวงขอบแดง + ข้อความใต้ช่อง (ตามภาพตัวอย่าง)
  String? _emailServerError;
  String? _passwordServerError;
  String? _formErrorText;

  @override
  void dispose() {
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
    // บาง API ส่ง errors เป็น map/list
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

  String _friendlyLoginError(
    http.Response res,
    Map<String, dynamic> data,
  ) {
    // ✅ กรณี HTTP เป็น Unauthorized
    if (res.statusCode == 401 || res.statusCode == 403) {
      return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    }

    // ✅ อ่าน code/message จากเซิร์ฟเวอร์
    final rawCode = _pickFirstString(
      data['error_code'] ?? data['code'] ?? data['error'] ?? '',
    ).trim();
    final code = rawCode.toUpperCase();

    final serverMsg = _extractMessage(data);
    final lowMsg = serverMsg.toLowerCase();

    // โค้ดยอดฮิตจาก backend หลายแบบ
    if (code.contains('INVALID') ||
        code.contains('UNAUTHORIZED') ||
        code.contains('CREDENTIAL') ||
        code.contains('PASSWORD') ||
        code.contains('LOGIN_FAILED')) {
      return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    }
    if (code.contains('NOT_FOUND') ||
        code.contains('USER_NOT_FOUND') ||
        code.contains('EMAIL_NOT_FOUND')) {
      return 'ไม่พบบัญชีผู้ใช้นี้';
    }

    // จับจากข้อความ (เช่น backend ส่งเป็นภาษาอังกฤษ)
    if ((lowMsg.contains('password') &&
            (lowMsg.contains('wrong') ||
                lowMsg.contains('invalid') ||
                lowMsg.contains('incorrect'))) ||
        (lowMsg.contains('credential') && lowMsg.contains('invalid'))) {
      return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    }
    if (lowMsg.contains('email') &&
        lowMsg.contains('not') &&
        lowMsg.contains('found')) {
      return 'ไม่พบบัญชีผู้ใช้นี้';
    }

    // ถ้ามีข้อความจาก server ที่อ่านรู้เรื่อง ให้แสดง
    if (serverMsg.isNotEmpty && serverMsg.length <= 140) {
      return serverMsg;
    }
    return 'เข้าสู่ระบบไม่สำเร็จ กรุณาตรวจสอบอีเมลหรือรหัสผ่าน';
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
        // ✅ ขอบแดงตอน error (เหมือนภาพตัวอย่าง)
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      );

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  void _clearServerErrors() {
    if (_emailServerError == null &&
        _passwordServerError == null &&
        _formErrorText == null) return;
    setState(() {
      _emailServerError = null;
      _passwordServerError = null;
      _formErrorText = null;
    });
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    // ✅ เคลียร์ error เก่าก่อน validate
    setState(() {
      _emailServerError = null;
      _passwordServerError = null;
      _formErrorText = null;
    });

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

      Map<String, dynamic> data = {};
      try {
        if (res.body.isNotEmpty) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) data = decoded;
        }
      } catch (_) {
        // ถ้า body ไม่ใช่ JSON ให้ถือว่า data ว่าง แล้วใช้ statusCode เป็นหลัก
      }

      final success = (res.statusCode >= 200 && res.statusCode < 300) &&
          ((data['ok'] == true) || (data['status']?.toString() == 'success'));

      if (success) {
        final dynamic userRaw = data['user'] ?? data['data'];

        String username;
        int? userId;
        String token = '';

        if (userRaw is Map<String, dynamic>) {
          token = (userRaw['token'] ?? '').toString();

          username = (userRaw['username'] ??
                  userRaw['usernืame'] ??
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

        // ✅ ถ้าไม่มี token ให้แสดง error แบบฟอร์ม (ไม่ใช้ SnackBar)
        if (token.isEmpty) {
          if (!mounted) return;
          setState(() {
            _formErrorText = 'เข้าสู่ระบบสำเร็จ แต่ไม่พบข้อมูล token';
          });
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kPrefTokenKey, token);
        await prefs.setString(kPrefTokenLegacyKey, token);

        if (userId != null) {
          await prefs.setInt('user_id', userId);
        }

        await prefs.setString('username', username);

        // ✅ เงื่อนไขนำทางหลังเข้าสู่ระบบ:
        // - ถ้าเป็นการสมัครใหม่ (pending_first_login_email ตรงกับอีเมลที่ล็อกอิน) -> ไปหน้า Share ก่อน
        // - ครั้งต่อไป -> ไปหน้า Home
        final pendingEmail =
            (prefs.getString('pending_first_login_email') ?? '').trim().toLowerCase();
        final currentEmail = _emailCtl.text.trim().toLowerCase();
        final int initialIndex =
            (pendingEmail.isNotEmpty && pendingEmail == currentEmail) ? 1 : 0;
        if (initialIndex == 1) {
          // ล้าง flag หลังใช้ครั้งแรก
          await prefs.remove('pending_first_login_email');
        }

        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                MainNav(initialUsername: username, initialIndex: initialIndex),
          ),
          (route) => false,
        );
      } else {
        final msg = _friendlyLoginError(res, data);

        if (!mounted) return;

        setState(() {
          // ✅ ผูก error ให้ไปขึ้นใต้ช่องที่เกี่ยวข้อง
          if (msg == 'ไม่พบบัญชีผู้ใช้นี้') {
            _emailServerError = msg;
          } else if (msg == 'อีเมลหรือรหัสผ่านไม่ถูกต้อง') {
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
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: topGap),

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
                            onChanged: (_) {
                              // ✅ ถ้าผู้ใช้แก้ไข ให้ล้าง error ของช่องนั้น
                              if (_emailServerError != null ||
                                  _formErrorText != null) {
                                setState(() {
                                  _emailServerError = null;
                                  _formErrorText = null;
                                });
                              }
                            },
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'กรุณากรอกอีเมล';
                              if (!_isValidEmail(t)) return 'รูปแบบอีเมลไม่ถูกต้อง';
                              // ✅ error จาก server
                              return _emailServerError;
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
                            onChanged: (_) {
                              if (_passwordServerError != null ||
                                  _formErrorText != null) {
                                setState(() {
                                  _passwordServerError = null;
                                  _formErrorText = null;
                                });
                              }
                            },
                            onFieldSubmitted: (_) {
                              if (!_loading) _login();
                            },
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'กรุณากรอกรหัสผ่าน';
                              }
                              if (v.length < 6) {
                                return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                              }
                              // ✅ error จาก server
                              return _passwordServerError;
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
