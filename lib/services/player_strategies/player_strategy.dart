import '../candidate_scoring.dart';

/// كل نوع مشغّل ويب معروف (video.js، JWPlayer/vidmoly، ...) له استراتيجية
/// معزولة فيزيائياً لتقييم/استبعاد مرشّحي التشغيل — بدل دالة تقييم واحدة
/// مشتركة تُطبَّق على كل الأنواع دفعة واحدة كما كان الحال سابقاً.
///
/// **سبب وجود هذا الملف**: 3 أخطاء حقيقية متتالية (سجل #39، #40، #41ب
/// بـTECHNICAL.md) كانت كلها من نفس الجذر — قاعدة تقييم واحدة مشتركة بين
/// كل الأنواع، فأي تعديل/إصلاح خاص بحالة اكتُشفت لنوع معيّن (مثل بونص
/// "مسجَّل من إطار عمل معروف" اللي سبَّب #40 لـJWPlayer تحديداً) كان يقدر
/// يأثر على أنواع أخرى بلا قصد. الحل البنيوي: كل نوع يملك استراتيجيته
/// الخاصة، تبدأ من نفس القاعدة الآمنة المشتركة (`CandidateScoring`) ثم
/// تُضيف/تُعدِّل فوقها فقط ما يخصها — إصلاح مستقبلي لـJWPlayer يلمس ملفه
/// فقط، فمن المستحيل بنيوياً يؤثر على video.js أو vidmoly بالخطأ.
///
/// **لا علاقة لهذا الملف بسرعة الاكتشاف** — اكتشاف نوع المشغّل نفسه (أي
/// استراتيجية تُستخدَم) يبقى بنفس الآلية السريعة الموجودة أصلاً
/// بـwatch_screen_discovery.dart (جافاسكربت مُحقَن + مطابقة دومين، أقل من
/// نصف ثانية فعلياً حسب كل سجلات التشخيص). هذا الملف يتدخّل فقط *بعد*
/// الاكتشاف، بمرحلة تقييم/استبعاد الروابط المرشَّحة.
abstract class PlayerStrategy {
  const PlayerStrategy();

  /// معرّف قصير للتسجيل/التشخيص فقط (لا يُستخدَم بأي منطق).
  String get id;

  /// نقاط إضافية لمرشّح مسجَّل مسبقاً بالسجل (`_webCandidateRegistry`) كـHLS
  /// مؤكَّد. القيمة الافتراضية (85) مطابقة تماماً للسلوك المشترك القديم —
  /// إدخال هذا الملف أول مرة لا يغيّر أي سلوك حالي.
  int registeredHlsBonus() => 85;

  /// نقاط إضافية لمرشّح ظهر عبر استخراج إطار العمل الخاص بالمشغّل نفسه
  /// (`_detectPlayerFrameworkSources` — قائمة تشغيل JWPlayer الداخلية،
  /// سجل مشغّلات video.js، إلخ). القيمة الافتراضية (85) نفس السلوك القديم.
  int frameworkEvidenceBonus() => 85;

  /// استبعاد أولي قبل أي حساب نقاط — القاعدة المشتركة (`CandidateScoring
  /// .isNonMediaAsset`) تكفي لكل الأنواع حتى الآن (تغطي بالفعل امتدادي
  /// `.key`/`.ts` من إصلاحي #39/#40). أي استثناء مستقبلي يخص نوعاً واحداً
  /// فقط (مثلاً نمط مسار خاص بموقع يستخدم JWPlayer) يُضاف هنا بملف ذلك
  /// النوع تحديداً، لا بالقاعدة المشتركة.
  bool isNonMediaAsset(String url) => CandidateScoring.isNonMediaAsset(url);

  /// النتيجة النهائية لمرشّح — القاعدة المشتركة + بونص هذا النوع تحديداً.
  int scoreCandidate(
    String url, {
    required bool isFrameworkSource,
    required bool registeredAsHls,
  }) {
    var score = CandidateScoring.scoreDetectedSource(url);
    if (registeredAsHls) score += registeredHlsBonus();
    if (isFrameworkSource) score += frameworkEvidenceBonus();
    return score;
  }
}

/// المصادر المجهولة (لا video.js ولا JWPlayer/vidmoly مكتشَف) — الأغلبية
/// العددية الفعلية من المواقع المستورَدة. نفس السلوك القديم بالضبط، صفر
/// خطر تراجع لأكبر شريحة استخدام.
class GenericPlayerStrategy extends PlayerStrategy {
  const GenericPlayerStrategy();
  @override
  String get id => 'generic';
}

class VideoJsPlayerStrategy extends PlayerStrategy {
  const VideoJsPlayerStrategy();
  @override
  String get id => 'video_js';
}

/// JWPlayer نفسه ومواقع vidmoly (اللي تستخدم JWPlayer داخلياً — راجع تعليق
/// `_webVidmolyPlayerMode` بـwatch_screen_discovery.dart لسبب تشارك العلم).
/// **صاحب سابقتي الخطأ الحقيقيتين المسجَّلتين** (#39 مفتاح تشفير، #40
/// شريحة .ts) — كلاهما مُصلَح فعلياً بالقاعدة المشتركة أصلاً (`.key`/`.ts`
/// بـisNonMediaAsset)، لكن أي إصلاح *مستقبلي* خاص بنمط ظاهرة فقط عند
/// JWPlayer (مثل قائمة تشغيله الداخلية اللي كانت سبب تجاوز #40 للحد)
/// مكانه هنا من الآن فصاعداً، لا القاعدة المشتركة.
class JwPlayerStrategy extends PlayerStrategy {
  const JwPlayerStrategy();
  @override
  String get id => 'jwplayer';
}

/// يختار الاستراتيجية المناسبة حسب حالة الجلسة المكتشَفة فعلياً (نفس
/// الأعلام الموجودة أصلاً بـwatch_screen_discovery.dart) — بلا أي منطق
/// اكتشاف جديد هنا.
class PlayerStrategyRegistry {
  PlayerStrategyRegistry._();

  static const generic = GenericPlayerStrategy();
  static const videoJs = VideoJsPlayerStrategy();
  static const jwplayer = JwPlayerStrategy();

  static PlayerStrategy select({
    required bool isVideoJsMode,
    required bool isJwPlayerLikeMode,
  }) {
    if (isJwPlayerLikeMode) return jwplayer;
    if (isVideoJsMode) return videoJs;
    return generic;
  }
}
