import 'package:flutter/material.dart';

class CustomScaffold extends StatelessWidget {
  const CustomScaffold({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/oreng.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
          // ปิดกันชนล่าง เพื่อให้หน้าลูกวางได้ชิดขอบจริง ๆ
          SafeArea(
            top: true,
            bottom: false,
            child: child ?? const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
