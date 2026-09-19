import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads the optional player-page visibility switch from settings/player.
///
/// الحقل اختياري بلوحة التحكم. **الافتراضي الآن `false` (إخفاء)** بعد أن
/// أثبتت ثلاثة سجلات تشخيص أن إظهار صفحة المصدر يبطّئ الالتقاط فعلياً:
/// مشغّل الصفحة الظاهر يواصل سحب نفس الفيديو بالتوازي مع محاولة التشغيل
/// الأصلي، فتتقاسمان الوصلة وتُقطع شريحتنا بعد ~12 ثانية. إظهارها يبقى
/// ممكناً من اللوحة للتشخيص فقط.
class PlayerVisibilityService {
  PlayerVisibilityService._();

  static Future<bool> loadShowSourcePage() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('player')
          .get();
      final value = snapshot.data()?['showSourcePage'];
      return value is bool ? value : false;
    } catch (_) {
      return false;
    }
  }

  /// Reads the optional hidden diagnostic-log button switch from
  /// settings/player.diagnosticLogEnabled. Defaults to false so the button
  /// stays invisible for every user unless explicitly turned on from the
  /// dashboard.
  static Future<bool> loadDiagnosticLogEnabled() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('player')
          .get();
      final value = snapshot.data()?['diagnosticLogEnabled'];
      return value is bool ? value : false;
    } catch (_) {
      return false;
    }
  }
}