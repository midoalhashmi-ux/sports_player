import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// يتذكّر، لكل حلقة/قناة بعينها، **صفحة المشغّل** (iframe التضمين) التي
/// انتهى إليها الاكتشاف ونجح التشغيل بعدها فعلاً.
///
/// **لماذا هذا تحديداً وليس رابط الوسائط**: روابط m3u8 بهذي المصادر موقّعة
/// بتوكن قصير الأجل (`?t=...&s=...&e=86400`) وأحياناً مربوطة بالجلسة، فلا
/// تصلح للحفظ. أما رابط صفحة التضمين
/// (`https://down.vidtube.one/embed-2vez650srfbx.html`) فليس فيه توكن ولا
/// انتهاء — هو معرّف الحلقة عند مزوّد الاستضافة، ثابت.
///
/// **المكسب المقاس من سجل المستخدم**: الجلسة العادية تمضي أول 23 ثانية
/// كاملةً على صفحة الموقع (تنتظر نطاقات إعلانات ميتة: `ERR_NAME_NOT_RESOLVED`
/// ثم `ERR_TOO_MANY_REDIRECTS`)، ثم 2.5 ثانية أخرى لاكتشاف الـiframe
/// وترقيته. فتح صفحة المشغّل مباشرةً يتخطّى ذلك كله.
///
/// يختلف عن [SiteRecipeService] الذي يحفظ **المضيف** لكل دومين موقع (يشمل
/// كل حلقاته): هذا يحفظ **الرابط الكامل لحلقة واحدة**.
class EpisodeEmbed {
  final String embedUrl;
  final String playerMode; // 'vidmoly' | 'videojs' | 'generic'
  final DateTime savedAt;

  const EpisodeEmbed({
    required this.embedUrl,
    required this.playerMode,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'embedUrl': embedUrl,
        'playerMode': playerMode,
        'savedAt': savedAt.toIso8601String(),
      };

  static EpisodeEmbed? fromJson(Map<String, dynamic> json) {
    final url = json['embedUrl'] as String?;
    if (url == null || !url.startsWith('http')) return null;
    final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '');
    if (savedAt == null) return null;
    return EpisodeEmbed(
      embedUrl: url,
      playerMode: (json['playerMode'] as String?) ?? 'generic',
      savedAt: savedAt,
    );
  }
}

class EpisodeEmbedService {
  static const _keyPrefix = 'episode_embed_v1_';

  /// مزوّدو الاستضافة يبدّلون نطاقاتهم دورياً (شوهد فعلياً:
  /// `vidmoly.net` ← `vidmoly.biz` بنفس الجلسة)، وقد تُحذف الحلقة من
  /// المزوّد. أسبوع هامش معقول: طويل بما يكفي ليخدم إعادة المشاهدة، وقصير
  /// بما يكفي ألّا نتشبّث برابط ميت.
  static const Duration _maxAge = Duration(days: 7);

  static Future<EpisodeEmbed?> load(String channelId) async {
    if (channelId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_keyPrefix$channelId');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final embed = EpisodeEmbed.fromJson(decoded);
      if (embed == null) return null;
      if (DateTime.now().difference(embed.savedAt) > _maxAge) {
        await prefs.remove('$_keyPrefix$channelId');
        return null;
      }
      return embed;
    } catch (_) {
      return null;
    }
  }

  static Future<void> remember(
    String channelId, {
    required String embedUrl,
    required String playerMode,
  }) async {
    if (channelId.isEmpty || !embedUrl.startsWith('http')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_keyPrefix$channelId',
        jsonEncode(EpisodeEmbed(
          embedUrl: embedUrl,
          playerMode: playerMode,
          savedAt: DateTime.now(),
        ).toJson()),
      );
    } catch (_) {}
  }

  /// الاختصار لم يوصل لأي مصدر — نحذفه فوراً بدل أن يعطّل نفس الحلقة كل مرة.
  static Future<void> invalidate(String channelId) async {
    if (channelId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$channelId');
    } catch (_) {}
  }
}
