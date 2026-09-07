import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class DynamicThemeSettings {
  final Color primaryColor;
  final Color backgroundColor;
  final String? backgroundImageUrl;

  const DynamicThemeSettings({
    required this.primaryColor,
    required this.backgroundColor,
    this.backgroundImageUrl,
  });

  ThemeData toThemeData() {
    return AppTheme.fromDynamicSettings(
      primaryColor: primaryColor,
      backgroundColor: backgroundColor,
    );
  }
}

class DynamicThemeService {
  /// مستند Firestore المتوقع: settings/theme
  /// الحقول: primaryColor (hex string "#00C853"), backgroundColor (hex string), backgroundImageUrl
  static Stream<DynamicThemeSettings> watchTheme() {
    return FirebaseFirestore.instance
        .collection('settings')
        .doc('theme')
        .snapshots()
        .map((doc) {
      final data = doc.data();
      return DynamicThemeSettings(
        primaryColor: _hexToColor(data?['primaryColor'], const Color(0xFF00C853)),
        backgroundColor:
            _hexToColor(data?['backgroundColor'], const Color(0xFF0D0D0D)),
        backgroundImageUrl: data?['backgroundImageUrl'],
      );
    });
  }

  static Color _hexToColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    final cleaned = hex.replaceAll('#', '');
    final value = int.tryParse('FF$cleaned', radix: 16);
    return value != null ? Color(value) : fallback;
  }
}
