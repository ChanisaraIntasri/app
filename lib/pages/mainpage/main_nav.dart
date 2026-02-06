import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import 'home.dart';
import 'scan_page.dart';
import 'share.dart';
import 'setting.dart'; // import ไว้เหมือนเดิมเผื่อใช้ในอนาคต หรือลบออกก็ได้ถ้าไม่ได้ใช้ในไฟล์นี้แล้ว

// สีหลักต่าง ๆ ของ nav bar
const kNavBg = Colors.white; // พื้นแถบเมนู (pill สีขาว)
const kNavIconActive = Colors.black87; // ไอคอนที่เลือกอยู่
const kNavIconInactive = Colors.black45;

class MainNav extends StatefulWidget {
  const MainNav({
    super.key,
    required this.initialUsername,

    /// ✅ index แบบเดิมของระบบ (ภายนอก)
    /// 0 = Home, 1 = Share
    /// (Settings ถูกย้ายออกไปแล้ว)
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
  // ✅ ปรับปรุงการ map index ใหม่ (ตัด Settings ออก)
  // ภายนอก: 0=Home, 1=Share
  // ภายใน:  0=Home, 1=Share, 2=Camera(action)
  // =========================
  int _externalToInternal(int ext) {
    if (ext <= 0) return 0; // home
    if (ext == 1) return 1; // share
    // ถ้าเคยเป็น 2 (Settings) ให้กลับไป Home เพราะไม่มีแท็บ Settings แล้ว
    return 0;
  }

  int _internalToExternal(int internal) {
    if (internal == 0) return 0; // home
    if (internal == 1) return 1; // share
    return 0;
  }

  @override
  void initState() {
    super.initState();

    // ปรับ range ให้เหลือแค่ 0-1 (Home, Share)
    final safeExt =
        (widget.initialIndex < 0 || widget.initialIndex > 1) ? 0 : widget.initialIndex;
    final initialInternal = _externalToInternal(safeExt);

    _controller = PersistentTabController(initialIndex: initialInternal);
    _username = widget.initialUsername;
    _lastRealTabInternal = initialInternal;

    // ✅ เฝ้าดู flag ที่ถูก set จากหน้าอื่น ๆ เพื่อสลับแท็บกลับ Home/Share
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
      final pendingExt = prefs.getInt('pending_nav_index'); // ภายนอก

      if (!forceHome && pendingExt == null) return;

      final targetExt = forceHome ? 0 : pendingExt!;
      // เช็ค range ใหม่ (เหลือแค่ 0 กับ 1)
      if (targetExt < 0 || targetExt > 1) {
        await prefs.remove('pending_nav_index');
        await prefs.setBool('force_home_tab', false);
        return;
      }

      final targetInternal = _externalToInternal(targetExt); // ภายใน: 0,1

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
  // ✅ หน้าตามแท็บ (เอา SettingPage ออก และส่ง username ไป Home)
  // 0=Home, 1=Share, 2=Camera(placeholder)
  // =========================
  List<Widget> _screens() => [
        // ส่ง username ไปให้ HomePage ใช้เปิดหน้า Setting
        HomePage(username: _username),
        const SharePage(),
        const SizedBox.shrink(), // placeholder
        // SettingPage ถูกเอาออกแล้ว
      ];

  // =========================
  // ✅ ไอคอนตามแท็บ (เอาไอคอน Settings ออก)
  // ✅ สลับเป็น Home - Share - Scan(กล้อง)
  // =========================
  List<PersistentBottomNavBarItem> _items() => [
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.home_rounded),
          activeColorPrimary: kNavIconActive,
          inactiveColorPrimary: kNavIconInactive,
        ),
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.eco_rounded),
          activeColorPrimary: kNavIconActive,
          inactiveColorPrimary: kNavIconInactive,
        ),
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.camera_alt_rounded),
          activeColorPrimary: kNavIconActive,
          inactiveColorPrimary: kNavIconInactive,
        ),
        // ไอคอน Settings ถูกเอาออกแล้ว
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
        // ✅ index ภายใน: 0=Home, 1=Share, 2=Camera(action)
        if (index == 2) {
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

        // ✅ เซฟ selectedIndex เป็น "แบบเดิมภายนอก"
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('selectedIndex', _internalToExternal(index));
        } catch (_) {}
      },
    );
  }
}
