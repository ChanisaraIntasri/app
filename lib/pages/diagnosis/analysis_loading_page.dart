import 'package:flutter/material.dart';

const kPrimaryGreen = Color(0xFF005E33);

/// หน้ารอโมเดลวินิจฉัย (พื้นหลังขาว + วงกลมสีเขียวโหลดเต็มวง)
class AnalysisLoadingPage extends StatefulWidget {
  const AnalysisLoadingPage({super.key});

  @override
  State<AnalysisLoadingPage> createState() => _AnalysisLoadingPageState();
}

class _AnalysisLoadingPageState extends State<AnalysisLoadingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // ✅ วิ่ง 0..1 ซ้ำ ๆ เพื่อให้เห็น "โหลดเต็มวง"
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // ✅ กันกด back ออกระหว่างรอ
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: _controller.value,
                        strokeWidth: 10,
                        backgroundColor: const Color(0xFFE6E6E6),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(kPrimaryGreen),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                const Text(
                  'กำลังวิเคราะห์โรค...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kPrimaryGreen,
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
