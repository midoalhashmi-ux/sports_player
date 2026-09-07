import 'package:flutter/material.dart';

class AppTheme {
  /// ثيم افتراضي يُستخدم قبل وصول إعدادات Firestore أو عند فشل الاتصال
  static ThemeData get fallback {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      primaryColor: const Color(0xFF00C853),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00C853),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
  }

  /// يبني ThemeData ديناميكياً من بيانات Firestore
  static ThemeData fromDynamicSettings({
    required Color primaryColor,
    required Color backgroundColor,
  }) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      primaryColor: primaryColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
  }
}
