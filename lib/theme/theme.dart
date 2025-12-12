import 'package:flutter/material.dart';

// สีหลักของแบรนด์ (ตอนนี้เป็นเขียว #005E33 + ขาว)
const kOrange = Color(0xFF005E33); // เดิม 0xFFFF7A00

final ThemeData lightMode = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kOrange,
    brightness: Brightness.light,
  ).copyWith(
    primary: kOrange,
    onPrimary: Colors.white,
  ),

  // ✅ AppBar เขียว
  appBarTheme: const AppBarTheme(
    backgroundColor: kOrange,
    foregroundColor: Colors.white,
    centerTitle: true,
    elevation: 0,
  ),

  // ปุ่มทึบ (เช่น Sign in)
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kOrange,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      padding: const EdgeInsets.symmetric(vertical: 16),
      elevation: 2,
    ),
  ),

  // ปุ่มขอบ
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      side: const BorderSide(color: Color(0xFFCBCBCB)),
      padding: const EdgeInsets.symmetric(vertical: 16),
      foregroundColor: kOrange, // ตัวหนังสือเขียวบนพื้นขาว
    ),
  ),

  // TextField โฟกัสเป็นเขียว
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kOrange, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),

  // Checkbox ติ๊กแล้วเป็นเขียว
  checkboxTheme: CheckboxThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    fillColor: MaterialStateProperty.resolveWith(
      (states) => states.contains(MaterialState.selected) ? kOrange : null,
    ),
    checkColor: const MaterialStatePropertyAll(Colors.white),
  ),
);

final ThemeData darkMode = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kOrange,
    brightness: Brightness.dark,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kOrange,
    foregroundColor: Colors.white,
    centerTitle: true,
    elevation: 0,
  ),
);
