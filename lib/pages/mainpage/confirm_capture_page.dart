import 'dart:io';
import 'package:flutter/material.dart';

const kPrimaryGreen = Color(0xFF005E33);

class ConfirmCapturePage extends StatelessWidget {
  final String imagePath;

  const ConfirmCapturePage({
    super.key,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ✅ รูปเต็มจอ (กันกรณีไฟล์หาย)
          Positioned.fill(
            child: file.existsSync()
                ? Image.file(
                    file,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  )
                : Container(
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: const Text(
                      'ไม่พบไฟล์รูปภาพ',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
          ),

          // ✅ ปุ่มย้อนกลับ (ไม่มีแถบด้านบนแล้ว)
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Material(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => Navigator.pop(context, false),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ✅ เงาด้านล่างให้อ่านปุ่มชัด
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Color(0xAA000000),
                      Color(0xE6000000),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ✅ ปุ่มด้านล่าง
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'ถ่ายใหม่',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          'ยืนยัน',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
