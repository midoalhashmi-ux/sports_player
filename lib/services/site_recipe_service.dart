import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// وصفة موقع متعلّمة: مضيف iframe الفعلي الذي أثبت نجاحه سابقاً لدومين
/// مصدر معيّن، ونوع المشغّل المكتشَف فيه.
class SiteRecipe {
  final String targetHost;
  final String playerMode; // 'vidmoly' | 'videojs' | 'generic'

  const SiteRecipe({required this.targetHost, required this.playerMode});

  Map<String, dynamic> toJson() => {
        'targetHost': targetHost,
        'playerMode': playerMode,
      };

  static SiteRecipe? fromJson(Map<String, dynamic> json) {
    final host = json['targetHost'] as String?;
    final mode = json['playerMode'] as String?;
    if (host == null || host.isEmpty || mode == null || mode.isEmpty) {
      return null;
    }
    return SiteRecipe(targetHost: host, playerMode: mode);
  }
}

/// يسجّل، لكل دومين مصدر (أول صفحة يفتحها WatchScreen قبل أي ترقية iframe)،
/// مضيف iframe الذي رُقِّي إليه سابقاً ونجح فعلياً (شوهد تشغيل حقيقي بعده) —
/// حتى تُرقّى الزيارة القادمة لنفس الدومين مرشحاً مطابقاً لنفس المضيف فوراً،
/// بدل انتظار دورة اكتشاف كاملة تعيد نفس النتيجة من الصفر في كل مرة. راجع
/// افكار_مهمة.md قسم 3 لخلفية الفكرة الكاملة.
///
/// عكس [PreferredServerService] (مربوط بقناة/حلقة واحدة، لاختيار مرشّح
/// التشغيل الأصلي النهائي): هذا مربوط بدومين الموقع نفسه (يشمل كل حلقات
/// نفس الموقع)، ويتدخّل بمرحلة أبكر — أي iframe يُرقَّى ليصبح المستند
/// الرئيسي قبل أي بحث عن رابط وسائط.
class SiteRecipeService {
  static const _keyPrefix = 'site_recipe_v1_';

  static Future<SiteRecipe?> load(String entryHost) async {
    if (entryHost.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_keyPrefix$entryHost');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return SiteRecipe.fromJson(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> remember(String entryHost, SiteRecipe recipe) async {
    if (entryHost.isEmpty || recipe.targetHost.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix$entryHost', jsonEncode(recipe.toJson()));
    } catch (_) {}
  }

  /// فشل الوصفة المحفوظة (الموقع غيّر بنيته) — إزالتها فوراً بدل تركها
  /// تعيد تعطيل نفس المسار في كل زيارة قادمة.
  static Future<void> invalidate(String entryHost) async {
    if (entryHost.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$entryHost');
    } catch (_) {}
  }
}
