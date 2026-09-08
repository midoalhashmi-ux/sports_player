import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// نتيجة فحص التحديث الإجباري — تُنشأ فقط لو التحديث مطلوب فعلاً.
class ForceUpdateInfo {
  final String requiredVersion;
  final String currentVersion;
  final String updateUrl;
  const ForceUpdateInfo({
    required this.requiredVersion,
    required this.currentVersion,
    required this.updateUrl,
  });
}

/// يقارن إصدار التطبيق المثبّت فعلياً على الجهاز بأقل إصدار مسموح مضبوط
/// من لوحة التحكم (settings/player -> minVersion). لو المثبَّت أقل،
/// يرجع [ForceUpdateInfo] ليعرض التطبيق شاشة تحديث إجباري قبل أي شيء
/// آخر. لو الحقل فارغ/غير موجود، أو تعذّر الجلب (بدون إنترنت مثلاً)،
/// يرجع null ويكمل التطبيق عادي — التحديث الإجباري ميزة اختيارية تماماً
/// من لوحة التحكم، وليست شرطاً لعمل التطبيق.
class VersionCheckService {
  static Future<ForceUpdateInfo?> checkForceUpdate() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('player')
          .get();
      final data = snapshot.data();
      final minVersion = (data?['minVersion'] as String?)?.trim();
      if (minVersion == null || minVersion.isEmpty) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (_compareVersions(currentVersion, minVersion) >= 0) return null;

      // كل حقل مستقل بغرضه: updateUrl فقط هو المستخدم هنا، بدون أي
      // اعتماد ضمني على storeUrl (الذي له غرض مختلف تماماً — رابط
      // فتح صفحة المتجر لتطبيق المحتوى عند تعذّر تشغيل المشغل). لو
      // updateUrl غير مضبوط، لا يوجد رابط فعّال لعرضه، فنكمل التطبيق
      // عادي بدل تعليقه بشاشة تحديث بدون زر فعّال.
      final updateUrl = (data?['updateUrl'] as String?)?.trim() ?? '';
      if (updateUrl.isEmpty) {
        return null;
      }

      return ForceUpdateInfo(
        requiredVersion: minVersion,
        currentVersion: currentVersion,
        updateUrl: updateUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// يقارن رقمي إصدار بصيغة "1.2.3" جزءاً بجزء (وليس كنص). يرجع سالب لو
  /// [a] أقل من [b]، صفر لو متساويين، موجب لو [a] أكبر. أي جزء غير رقمي
  /// يُعامل كصفر بدل رمي استثناء يوقف التحقق كاملاً.
  static int _compareVersions(String a, String b) {
    final partsA = a.split('.');
    final partsB = b.split('.');
    final length = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < length; i++) {
      final numA = i < partsA.length ? int.tryParse(partsA[i]) ?? 0 : 0;
      final numB = i < partsB.length ? int.tryParse(partsB[i]) ?? 0 : 0;
      if (numA != numB) return numA - numB;
    }
    return 0;
  }
}
