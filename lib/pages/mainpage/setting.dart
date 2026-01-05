import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/account/edit_username_page.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({
    super.key,
    this.initialUsername = 'farmer_somchai', 
  });

 
  static const Color kPrimaryGreen = Color(0xFF005E33); 
  static const Color kCardBg = Color(0xFFF5F5F5);
  static const Color kTextDark = Color(0xFF3A2A1A);
  static const double kRadius = 26;

  /// ชื่อผู้ใช้เริ่มต้น (ควรส่งมาจากตอน login)
  final String initialUsername;

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  late String _currentUsername;

  @override
  void initState() {
    super.initState();
    // ตั้งชื่อเริ่มต้นจากค่าที่ส่งเข้ามา
    _currentUsername = widget.initialUsername;
  }

  @override
  Widget build(BuildContext context) {
    final paddingTop = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          
          Container(
            padding: EdgeInsets.fromLTRB(
              24,
              paddingTop + 90, 
              24,
              80,
            ),
            color: SettingPage.kPrimaryGreen, 
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'setting',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'คุณสามารถจัดการบัญชีของคุณได้ที่นี่',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ===== เนื้อหาข้างล่าง =====
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // หัวข้อกลุ่ม Your account
                  Text(
                    'Your account',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SettingPage.kTextDark,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // การ์ด Account
                  _AccountCard(
                    title: 'Account',
                    subtitle: _currentUsername,
                    icon: Icons.person_outline,
                    onTap: () async {
                      final newUsername = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditUsernamePage(
                            initialUsername: _currentUsername,
                          ),
                        ),
                      );

                      if (newUsername != null && newUsername.isNotEmpty) {
                        setState(() {
                          _currentUsername = newUsername;
                        });

                        // TODO: ถ้ามี session/token เก็บ user info
                        // ให้ไปอัปเดต global state ตรงนั้นต่อด้วย
                        debugPrint('New username: $newUsername');
                      }
                    },
                  ),

                  const SizedBox(height: 24),

                  // ปุ่ม Sign out
                  Center(
                    child: TextButton(
                      onPressed: () async {
                        // TODO: ล้าง token / session ถ้ามี

                        Navigator.of(context, rootNavigator: true)
                            .pushNamedAndRemoveUntil(
                          '/welcome',
                          (route) => false,
                        );
                      },
                      child: const Text(
                        'Sign out',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

/// การ์ด Account สไตล์โค้ง ๆ
class _AccountCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _AccountCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(SettingPage.kRadius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: SettingPage.kCardBg,
          borderRadius: BorderRadius.circular(SettingPage.kRadius),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.white,
              child: Icon(
                icon,
                color: SettingPage.kPrimaryGreen, // << ไอคอนวงกลมเป็นสีเขียว
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: SettingPage.kTextDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
