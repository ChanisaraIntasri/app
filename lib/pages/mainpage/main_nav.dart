import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import 'home.dart';
import 'scan_page.dart';
import 'share.dart';
import 'setting.dart';

// สีหลักต่าง ๆ ของ nav bar
const kNavBg = Colors.white;                // พื้นแถบเมนู (pill สีขาว)
const kNavIconActive = Colors.black87;      // ไอคอนที่เลือกอยู่
const kNavIconInactive = Colors.black45;    // ไอคอนที่ไม่ได้เลือก
const kScanAccent = Color(0xFFFF7A00);      // สีเน้นสำหรับปุ่มสแกน (ถ้ายังอยากให้เด่น)

class MainNav extends StatefulWidget {
  const MainNav({
    super.key,
    required this.initialUsername, // 👈 รับชื่อผู้ใช้จากภายนอก
  });

  /// ชื่อผู้ใช้ที่ได้มาจากตอนล็อกอิน / สมัคร
  final String initialUsername;

  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> {
  late final PersistentTabController _controller;

  // เก็บชื่อไว้ใน state เผื่ออนาคตอยากอัปเดตจากหน้าอื่น
  late String _username;

  @override
  void initState() {
    super.initState();
    _controller = PersistentTabController(initialIndex: 0);
    _username = widget.initialUsername;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// list หน้าหลักของแต่ละแท็บ
  /// index 1 (Scan) ใช้เป็น dummy เพราะเราจะ push ScanPage แยก route
  List<Widget> _screens() => [
        const HomePage(),        // 0
        const SizedBox.shrink(), // 1 - dummy สำหรับ Scan
        const SharePage(),       // 2
        SettingPage(             // 3 - ส่งชื่อผู้ใช้ให้หน้า Setting
          initialUsername: _username,
        ),
      ];

  /// ไอคอนในแท็บบาร์ (สไตล์ pill ขาวเหมือนในภาพ)
  List<PersistentBottomNavBarItem> _items() => [
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.home_rounded),
          activeColorPrimary: kNavIconActive,
          inactiveColorPrimary: kNavIconInactive,
        ),
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.camera_alt_rounded),
          // ให้ปุ่มสแกนเด่นด้วยสีส้มเวลา active (ถ้าอยากให้เหมือนแท็บอื่นให้เปลี่ยนเป็น kNavIconActive)
          activeColorPrimary: kScanAccent,
          inactiveColorPrimary: kNavIconInactive,
        ),
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.history_rounded),
          activeColorPrimary: kNavIconActive,
          inactiveColorPrimary: kNavIconInactive,
        ),
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.settings_rounded),
          activeColorPrimary: kNavIconActive,
          inactiveColorPrimary: kNavIconInactive,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return PersistentTabView(
      context,
      controller: _controller,
      screens: _screens(),
      items: _items(),

      confineToSafeArea: true,
      resizeToAvoidBottomInset: true,

      // 🟢 ทำให้แถบเป็น pill ขาว เหมือนในรูป
      backgroundColor: kNavBg,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      decoration: const NavBarDecoration(
        borderRadius: BorderRadius.all(Radius.circular(40)), // pill โค้งเยอะ ๆ
        colorBehindNavBar: Colors.transparent,
      ),
      navBarHeight: 64,
      navBarStyle: NavBarStyle.style6, // สไตล์เรียบ ๆ เน้นไอคอน

      // ตรงนี้คือ logic ซ่อนแท็บบาร์เวลาเข้า Scan
      onItemSelected: (index) async {
        if (index == 1) {
          // เปิดหน้า Scan แบบเต็มจอ (ไม่มี nav bar)
          await PersistentNavBarNavigator.pushNewScreen(
            context,
            screen: const ScanPage(),
            withNavBar: false,
            pageTransitionAnimation: PageTransitionAnimation.cupertino,
          );

          // พอกลับจากหน้าสแกน ให้กลับมา active ที่ Home
          _controller.index = 0;
          setState(() {});
        } else {
          _controller.index = index;
          setState(() {});
        }
      },
    );
  }
}
