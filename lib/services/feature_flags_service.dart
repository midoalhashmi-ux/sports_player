import 'package:cloud_firestore/cloud_firestore.dart';

/// يقرأ خانات تفعيل/تعطيل ميزات من Firestore (المستند settings/features)
/// حتى تقدر توقف ميزة معينة من لوحة التحكم فوراً بدون تحديث التطبيق —
/// أول استخدام: youtubeEnabled (تشغيل يوتيوب عبر المشغل الرسمي).
///
/// شكل المستند المتوقع في Firestore:
/// settings/features {
///   youtubeEnabled: true,
/// }
///
/// إذا لم يوجد المستند أو الحقل، الافتراضي true (مفعّل) حتى لا يتعطل شيء
/// قبل ما تضبط لوحة التحكم. لو صار مشكلة (شكوى/رفض من يوتيوب مستقبلاً)،
/// يكفي ضبط الحقل false من لوحة التحكم لإيقافه فوراً لكل المستخدمين.
class FeatureFlagsService {
  FeatureFlagsService._();
  static final FeatureFlagsService instance = FeatureFlagsService._();

  bool _fetched = false;
  bool _youtubeEnabled = true;

  bool get youtubeEnabled => _youtubeEnabled;

  /// يجلب الإعدادات مرة واحدة ويخزّنها بالذاكرة لبقية الجلسة. استدعِها
  /// قبل أول تحقق من youtubeEnabled (مثلاً عند فتح شاشة المشاهدة).
  Future<void> ensureLoaded() async {
    if (_fetched) return;
    _fetched = true;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('features')
          .get();
      final data = snapshot.data();
      if (data == null) return;
      _youtubeEnabled = data['youtubeEnabled'] as bool? ?? true;
    } catch (_) {
      // تعذر الجلب (بدون إنترنت مثلاً) — نبقى على الافتراضي (مفعّل)
      // بدل تعطيل الميزة بالخطأ.
    }
  }
}
