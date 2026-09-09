import 'package:flutter/services.dart';

/// يقرأ الكوكيز المخزَّنة فعلياً داخل محرك WebView لرابط معيّن، عبر
/// android.webkit.CookieManager الأصلي — بما فيها الكوكيز المعلَّمة
/// HttpOnly التي لا يقدر جافاسكربت (document.cookie) يراها إطلاقاً.
///
/// السبب: بعض مواقع البث تحمي روابط الفيديو بكوكيز جلسة HttpOnly.
/// المتصفح (WebView) يرسلها تلقائياً مع كل طلباته لأنها محفوظة بذاكرته
/// الداخلية، لكن محاولة تشغيل نفس الرابط مباشرة من مشغل الفيديو الأصلي
/// (ExoPlayer) خارج WebView لا تحمل هذه الكوكيز أبداً ما لم تُقرأ وتُمرَّر
/// يدوياً — وهذا سبب رئيسي لفشل التشغيل الأصلي بخطأ "Source error" رغم
/// أن نفس الرابط يعمل بلا مشاكل داخل صفحة الويب.
class NativeCookieService {
  NativeCookieService._();

  static const _channel = MethodChannel('sports_player/cookies');

  /// يرجع سلسلة الكوكيز لهذا الرابط (بصيغة "a=1; b=2")، أو null لو تعذّرت
  /// القراءة (منصة غير مدعومة، أو لا توجد كوكيز أصلاً لهذا الدومين).
  static Future<String?> getCookie(String url) async {
    try {
      final result =
          await _channel.invokeMethod<String>('getCookie', {'url': url});
      return (result == null || result.isEmpty) ? null : result;
    } catch (_) {
      return null;
    }
  }
}
