import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import 'home.dart';
import 'share.dart';
import 'setting.dart';

// สีหลักต่าง ๆ ของ nav bar
const kNavBg = Colors.white;                // พื้นแถบเมนู (pill สีขาว)
const kNavIconActive = Colors.black87;      // ไอคอนที่เลือกอยู่
const kNavIconInactive = Colors.black45;    // ไอคอนที่ไม่ได้เลือก
// (ลบเมนูกล้องออกจากแถบเมนูแล้ว)

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
  Timer? _navWatchTimer;
  @override
  void initState() {
    super.initState();
    _controller = PersistentTabController(initialIndex: 0); // ✅ เปิดมาเป็น Home
    _username = widget.initialUsername;

    // ✅ เฝ้าดู flag ที่ถูก set จากหน้า Treatment เพื่อสลับแท็บกลับ Home
    _navWatchTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _checkPendingNav();
    });

    // run once immediately
    _checkPendingNav();
  }

  Future<void> _checkPendingNav() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final forceHome = prefs.getBool('force_home_tab') ?? false;
      final pending = prefs.getInt('pending_nav_index');

      if (!forceHome && pending == null) return;

      final targetIndex = forceHome ? 0 : pending!;
      if (targetIndex < 0 || targetIndex > 2) {
        await prefs.remove('pending_nav_index');
        await prefs.setBool('force_home_tab', false);
        return;
      }

      if (_controller.index != targetIndex) {
        setState(() {
          _controller.index = targetIndex;
        });
      } else {
        // แม้ index เท่าเดิม ก็ยัง set ซ้ำเพื่อให้แน่ใจว่า nav เปลี่ยนจริง
        _controller.index = targetIndex;
      }

      await prefs.remove('pending_nav_index');
      await prefs.setBool('force_home_tab', false);
      await prefs.setInt('selectedIndex', targetIndex);
    } catch (_) {}
  }
  @override
  void dispose() {
    _navWatchTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }
  /// ✅ ให้ "หน้า" ตรงกับ "ไอคอน"
  /// 0 = Home icon -> HomePage
  /// 1 = Leaf icon -> SharePage
  /// 2 = Settings icon -> SettingPage
  List<Widget> _screens() => [
        const HomePage(),  // 0 ✅ Home icon = HomePage
        const SharePage(), // 1 ✅ Leaf icon = SharePage
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
          // ✅ เปลี่ยนไอคอนประวัติ -> ไอคอนใบไม้
          icon: const Icon(Icons.eco_rounded),
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

      onItemSelected: (index) {
        _controller.index = index;
        setState(() {});
      },
    );
  }
}
