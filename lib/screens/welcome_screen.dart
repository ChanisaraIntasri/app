import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/signin_screens.dart'; // 👈 เปลี่ยนมา import SignIn

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();

    // แสดงโลโก้ 3 วินาที แล้วไปหน้า SignIn
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => const SignInScreen(), // 👈 เปลี่ยนเป็น SignInScreen
          transitionsBuilder: (context, animation, __, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: Image.asset(
          'assets/images/logo.jpg',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
