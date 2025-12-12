// lib/pages/mainpage/confirm_capture_page.dart
import 'dart:io';
import 'package:flutter/material.dart';

const kOrange = Color(0xFFFF7A00);

class ConfirmCapturePage extends StatefulWidget {
  final String imagePath;
  const ConfirmCapturePage({super.key, required this.imagePath});

  @override
  State<ConfirmCapturePage> createState() => _ConfirmCapturePageState();
}

class _ConfirmCapturePageState extends State<ConfirmCapturePage> {
  bool _busy = false; // กันกดปุ่มซ้ำรัวๆ

  void _retake() {
    if (_busy) return;
    Navigator.of(context).pop(false);
  }

  void _usePhoto() {
    if (_busy) return;
    setState(() => _busy = true);
    // คืนค่า true ให้หน้าเดิม แล้วค่อยปล่อย busy (ไม่จำเป็นต้อง setState อีก)
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('ตัวอย่างภาพ', style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        children: [
          // รูปแบบเต็ม จิ้มซูมได้
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.contain,
              ),
            ),
          ),

          // ไล่เฉดมืดล่าง เพื่อให้อ่านปุ่ม/ตัวหนังสือง่าย
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 140,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54, Colors.black87],
                  ),
                ),
              ),
            ),
          ),

          // ปุ่มล่าง: ถ่ายใหม่ / ใช้รูปนี้
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _busy ? null : _retake,
                      child: const Text('ถ่ายใหม่'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                      onPressed: _busy ? null : _usePhoto,
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('ยืนยันรูปนี้'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
