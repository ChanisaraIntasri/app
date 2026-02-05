import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import 'home.dart';
import 'scan_page.dart';
import 'share.dart';
import 'setting.dart';

// สีหลักต่าง ๆ ของ nav bar
const kNavBg = Colors.white;            // พื้นแถบเมนู (pill สีขาว)
const kNavIconActive = Colors.black87;  // ไอคอนที่เลือกอยู่
const kNavIconInactive = Colors.black45;

class MainNav extends StatefulWidget {
  const MainNav({
    super.key,
    required this.initialUsername,

    /// ✅ index แบบเดิมของระบบ (ภายนอก)
    /// 0 = Home, 1 = Share, 2 = Settings
    /// (ไม่มีกล้องใน index นี้)
    this.initialIndex = 0,
  });

  final String initialUsername;
  final int initialIndex;

  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> {
  late final PersistentTabController _controller;
  late String _username;
  Timer? _navWatchTimer;

  // ✅ จำแท็บล่าสุดที่ "ไม่ใช่" กล้อง (index ภายใน)
  int _lastRealTabInternal = 0;

  // =========================
  // ✅ map index แบบ "ภายนอก" (เดิมของระบบ)
  // 0=Home, 1=Share, 2=Settings
  //
  // ✅ map index แบบ "ภายใน" (ใหม่)
  // 0=Home, 1=Camera(action), 2=Share, 3=Settings
  // =========================
  int _externalToInternal(int ext) {
    if (ext <= 0) return 0; // home
    if (ext == 1) return 2; // share
    if (ext == 2) return 3; // settings
    return 0;
  }

  int _internalToExternal(int internal) {
    if (internal == 0) return 0; // home
    if (internal == 2) return 1; // share
    if (internal == 3) return 2; // settings
    return 0;
  }

  @override
  void initState() {
    super.initState();

    final safeExt = (widget.initialIndex < 0 || widget.initialIndex > 2)
        ? 0
        : widget.initialIndex;
    final initialInternal = _externalToInternal(safeExt);

    _controller = PersistentTabController(initialIndex: initialInternal);
    _username = widget.initialUsername;
    _lastRealTabInternal = initialInternal;

    // ✅ เฝ้าดู flag ที่ถูก set จากหน้าอื่น ๆ เพื่อสลับแท็บกลับ Home/Share/Settings
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
      final pendingExt = prefs.getInt('pending_nav_index'); // ภายนอก: 0..2

      if (!forceHome && pendingExt == null) return;

      final targetExt = forceHome ? 0 : pendingExt!;
      if (targetExt < 0 || targetExt > 2) {
        await prefs.remove('pending_nav_index');
        await prefs.setBool('force_home_tab', false);
        return;
      }

      final targetInternal = _externalToInternal(targetExt); // ภายใน: 0,2,3

      if (_controller.index != targetInternal) {
        setState(() {
          _controller.index = targetInternal;
        });
      } else {
        _controller.index = targetInternal;
      }

      // ✅ อัปเดต last tab
      _lastRealTabInternal = targetInternal;

      await prefs.remove('pending_nav_index');
      await prefs.setBool('force_home_tab', false);

      // เก็บค่าเป็นแบบเดิม (ภายนอก) เพื่อไม่ให้ส่วนอื่นพัง
      await prefs.setInt('selectedIndex', targetExt);
    } catch (_) {}
  }

  @override
  void dispose() {
    _navWatchTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // =========================
  // ✅ หน้าตามแท็บ (มี placeholder ให้แท็บกล้อง)
  // 0=Home, 1=Camera(placeholder), 2=Share, 3=Settings
  // =========================
  List<Widget> _screens() => [
        const HomePage(),
        const SizedBox.shrink(), // placeholder (จะไม่ถูกแสดงจริง เพราะเราจะ push ไปหน้า Scan)
        const SharePage(),
        SettingPage(initialUsername: _username),
      ];

  // =========================
  // ✅ ไอคอนตามแท็บ (กล้องอยู่หลัง Home)
  // =========================
  List<PersistentBottomNavBarItem> _items() => [
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.home_rounded),
          activeColorPrimary: kNavIconActive,
          inactiveColorPrimary: kNavIconInactive,
        ),
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.camera_alt_rounded),
          activeColorPrimary: kNavIconActive,
          inactiveColorPrimary: kNavIconInactive,
        ),
        PersistentBottomNavBarItem(
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

  void _openScanPage() {
    // ✅ push ไปหน้า Scan โดยตรง
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanPage(quickResultOnly: true)),
    );
  }

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
        // ✅ index ภายใน: 0=Home, 1=Camera(action), 2=Share, 3=Settings
        if (index == 1) {
          // กล้อง: ไม่เปลี่ยนแท็บจริง ให้เด้งกลับแท็บเดิม แล้ว push หน้า Scan
          final prev = _lastRealTabInternal;
          if (_controller.index != prev) {
            setState(() => _controller.index = prev);
          } else {
            setState(() {}); // ensure UI stays
          }

          // push หลังเฟรม เพื่อกัน context เปลี่ยนระหว่าง build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _openScanPage();
          });
          return;
        }

        _controller.index = index;
        _lastRealTabInternal = index;
        setState(() {});

        // ✅ เซฟ selectedIndex เป็น "แบบเดิมภายนอก" (0..2)
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('selectedIndex', _internalToExternal(index));
        } catch (_) {}
      },
    );
  }
}
