import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/welcome_screen.dart';
import 'package:flutter_application_1/pages/mainpage/main_nav.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color _orange = Color(0xFFFF7A00);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _orange),
      appBarTheme: const AppBarTheme(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      initialRoute: '/welcome',
      routes: {
        '/welcome': (context) => const WelcomeScreen(),

        // 🔧 แก้ตรงนี้: ใส่ initialUsername ให้ครบ
        // route นี้ส่วนใหญ่ไม่ถูกใช้ เพราะหลัง login/register
        // เราจะ push MainNav(...) แบบส่งชื่อจริงเข้าไปอยู่แล้ว
        '/main': (context) => const MainNav(initialUsername: 'farmer_somchai'),
      },
    );
  }
}
