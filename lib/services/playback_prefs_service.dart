import 'package:shared_preferences/shared_preferences.dart';

/// تفضيلات عرض يختارها المستخدم مرة واحدة ويتوقّع أن تبقى — لا حالة تشغيل.
///
/// وُجدت لسبب واحد محدَّد: وضع ملء إطار الفيديو (`BoxFit`) كان يعود
/// لـ`contain` بكل حلقة/قناة جديدة. على هاتف بنسبة عرض 20:9 يبقى محتوى
/// 16:9 محاطاً بشريطين جانبيين دائماً، فكان على من يفضّل ملء الشاشة أن
/// يعيد اختيار الوضع يدوياً بكل مرة (بلاغ مباشر: "ليس مغطياً كامل
/// الشاشة"). أي فشل هنا صامت تماماً ويرجع للسلوك الافتراضي.
class PlaybackPrefsService {
  static const _keyFitIndex = 'player_fit_mode_v1';

  static Future<int?> loadFitIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyFitIndex);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveFitIndex(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyFitIndex, index);
    } catch (_) {}
  }
}
