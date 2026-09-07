import 'package:cloud_firestore/cloud_firestore.dart';

/// إعدادات عامة عن التطبيق نفسه (وليس المشغل) — تُقرأ من settings/app
/// في Firestore حتى يتحكم المالك بها من لوحة التحكم بدون تحديث التطبيق.
class AppSettings {
  final String appStoreUrl;
  final String shareMessage;

  const AppSettings({
    required this.appStoreUrl,
    required this.shareMessage,
  });

  factory AppSettings.fromMap(Map<String, dynamic>? map) {
    return AppSettings(
      appStoreUrl: (map?['appStoreUrl'] ?? map?['storeUrl'] ?? '').toString(),
      shareMessage: (map?['shareMessage'] as String?)?.trim().isNotEmpty == true
          ? map!['shareMessage']
          : 'جرّب تطبيق BinSheikh!',
    );
  }
}

class AppSettingsService {
  static Future<AppSettings> fetchSettings() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('settings').doc('app').get();
      return AppSettings.fromMap(snapshot.data());
    } catch (_) {
      return AppSettings.fromMap(null);
    }
  }
}
