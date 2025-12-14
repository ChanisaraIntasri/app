import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import 'home.dart';
import 'share.dart';
import 'scan_page.dart';
import 'setting.dart';

// สีหลักต่าง ๆ ของ nav bar
const kNavBg = Colors.white;                // พื้นแถบเมนู (pill สีขาว)
const kNavIconActive = Colors.black87;      // ไอคอนที่เลือกอยู่
const kNavIconInactive = Colors.black45;    // ไอคอนที่ไม่ได้เลือก
const kScanAccent = Color(0xFFFF7A00);      // สีเน้นสำหรับปุ่มสแกน (ถ้าอยากให้เด่น)

class MainNav extends StatefulWidget {
  const MainNav({
    super.key,
    required this.initialUsername,
  });

  final String initialUsername;

  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> {
  late final PersistentTabController _controller;
  late String _username;

  @override
  void initState() {
    super.initState();
    _controller = PersistentTabController(initialIndex: 0); // ✅ เปิดมาเป็น Home
    _username = widget.initialUsername;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// ✅ ให้ "หน้า" ตรงกับ "ไอคอน"
  /// 0 = Home icon -> HomePage
  /// 1 = Camera icon -> push ScanPage (ใช้ dummy ในแท็บ)
  /// 2 = History icon -> SharePage
  /// 3 = Settings icon -> SettingPage
  List<Widget> _screens() => [
        const HomePage(),        // 0 ✅ Home icon = HomePage
        const SizedBox.shrink(), // 1 dummy สำหรับ Scan (เราจะ push แยก)
        const SharePage(),       // 2 ✅ History icon = SharePage
        SettingPage(
          initialUsername: _username,
        ),
      ];

  List<PersistentBottomNavBarItem> _items() => [
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.home_rounded),
          activeColorPrimary: kNavIconActive,
          inactiveColorPrimary: kNavIconInactive,
        ),
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.camera_alt_rounded),
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

      backgroundColor: kNavBg,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      decoration: const NavBarDecoration(
        borderRadius: BorderRadius.all(Radius.circular(40)),
        colorBehindNavBar: Colors.transparent,
      ),
      navBarHeight: 64,
      navBarStyle: NavBarStyle.style6,

      onItemSelected: (index) async {
        if (index == 1) {
          await PersistentNavBarNavigator.pushNewScreen(
            context,
            screen: const ScanPage(),
            withNavBar: false,
            pageTransitionAnimation: PageTransitionAnimation.cupertino,
          );

          // ✅ กลับมาแล้วให้ชี้ไป Home (ไอคอน Home + หน้า Home)
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
