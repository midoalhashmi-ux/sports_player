/// اختيار جودة HLS المناسبة للتشغيل الأصلي (ExoPlayer).
///
/// **الخلفية (سبب وجود هذا الملف أصلاً)**: تحليل 7 سجلات تشخيص حقيقية أظهر
/// نمطاً لا يتخلّف: كل فشل جلب شريحة بالوكيل المحلي كان على الجودة الأعلى
/// (`_x`) أو العالية (`_h`)، **ولا فشل واحد** على المتوسطة/المنخفضة
/// (`_n`/`_l`). والمصدران الوحيدان اللذان نجحا نظيفَين هما اللذان لا
/// يملكان جودة ثقيلة أصلاً (`,n,l,` فقط). بنفس اللحظة كان مشغّل الموقع
/// داخل WebView يشغّل `_n`/`_l` بنجاح — أي أن **آلية التكيّف (ABR) الخاصة
/// بالموقع قرّرت أن الشبكة لا تتحمّل الجودة الأعلى**، بينما كان كودنا
/// يطلبها: الفرز كان تنازلياً دائماً (`الأعلى أولاً`) ثم يؤخذ العنصر
/// الأول. النتيجة: شريحة بعدة ميغابايت تزحف 11-13 ثانية ثم يُقطع الاتصال
/// (`Connection closed while receiving data`)، فتُحسب "فشل تشغيل أصلي"
/// رغم أن المصدر سليم تماماً.
///
/// **المبدأ**: مشغّل الموقع نفسه هو أفضل مقياس متاح لقدرة الشبكة الفعلية —
/// فهو يعمل بنفس اللحظة وبنفس الاتصال وبآلية تكيّف ناضجة. فبدل تخمين رقم
/// ثابت لعرض النطاق (يشيخ مع تغيّر الشبكات والمواقع)، نتتبّع أي جودة
/// **أثبت WebView فعلياً** أنه يجلب شرائحها، ونقدّمها.
///
/// المطابقة تتم بـ**مجلد** الرابط لا باسم/رمز الجودة — فلا تعتمد على أي
/// نمط تسمية خاص بمزوّد بعينه (`_x`/`_720p`/`/hi/`...)، وتعمل مع أي CDN.
library;

/// جودة واحدة من قائمة تشغيل رئيسية (master playlist).
class HlsVariant {
  const HlsVariant({
    required this.bandwidth,
    required this.label,
    required this.url,
  });

  /// من `BANDWIDTH=` بوسم `#EXT-X-STREAM-INF` (موجود دائماً بالمواصفة،
  /// خلاف `RESOLUTION` الاختياري) — 0 لو غاب.
  final int bandwidth;

  /// تسمية معروضة للمستخدم ("720p" أو "1280 kbps").
  final String label;

  final String url;
}

class HlsVariantSelector {
  HlsVariantSelector._();

  /// عدد الجودات الذي يبدأ عنده اعتبار الأعلى "طبقة إضافية" يُتحفَّظ منها
  /// عند غياب أي إثبات. مصدره السجلات: المصادر ذات جودتين (`,n,l,`) نجحت
  /// بالأعلى فعلياً، بينما ذات الأربع (`,l,n,h,x,`) فشلت عليها دائماً.
  static const int _extraTierThreshold = 3;

  /// "مفتاح الجودة" = مجلد الرابط (بلا اسم الملف ولا معاملات الاستعلام).
  ///
  /// شريحة `.../uyjeu9vq4p2b_n/seg-1-v1-a1.ts?t=...` وقائمتها
  /// `.../uyjeu9vq4p2b_n/index-v1-a1.m3u8` تشتركان بنفس المجلد، فتكفي
  /// لربط ما شغّله WebView فعلياً بما نختاره نحن — دون أي افتراض عن
  /// تسمية الجودات.
  static String? variantKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    final segments = uri.pathSegments;
    if (segments.length < 2) return null;
    final directory = segments.sublist(0, segments.length - 1).join('/');
    if (directory.isEmpty) return null;
    final host = uri.host.toLowerCase();
    return host.isEmpty ? directory : '$host/$directory';
  }

  /// يرتّب الجودات بالأفضلية الفعلية للتشغيل الأصلي (الأنسب أولاً).
  ///
  /// - أي جودة أثبت WebView تشغيلها (`provenKeys`) تتقدّم الجميع، والأعلى
  ///   بين المُثبَتات أولاً (إثباتها يعني أن الشبكة تحمّلتها فعلاً).
  /// - بلا أي إثبات: يبقى الترتيب تنازلياً، **إلا** أن الأعلى يُؤخَّر
  ///   للآخر حين تكون الجودات 3 فأكثر (طبقة "إضافية" أثبتت السجلات فشلها
  ///   المتكرر) — فتبقى متاحة لاختيار المستخدم اليدوي، لكنها ليست البداية
  ///   التلقائية.
  /// - لا تُحذف أي جودة إطلاقاً: الترتيب فقط.
  static List<HlsVariant> prioritize(
    List<HlsVariant> variants, {
    Set<String> provenKeys = const <String>{},
  }) {
    if (variants.length < 2) return List<HlsVariant>.unmodifiable(variants);

    final sorted = [...variants]
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

    if (provenKeys.isNotEmpty) {
      final proven = <HlsVariant>[];
      final rest = <HlsVariant>[];
      for (final variant in sorted) {
        final key = variantKey(variant.url);
        (key != null && provenKeys.contains(key) ? proven : rest).add(variant);
      }
      if (proven.isNotEmpty) {
        return List<HlsVariant>.unmodifiable([...proven, ...rest]);
      }
    }

    if (sorted.length < _extraTierThreshold) {
      return List<HlsVariant>.unmodifiable(sorted);
    }
    return List<HlsVariant>.unmodifiable([...sorted.skip(1), sorted.first]);
  }

  /// روابط الجودات المسموح لـExoPlayer التكيّف بينها داخل قائمة رئيسية.
  ///
  /// الترتيب وحده لا يكفي للقائمة الرئيسية: ExoPlayer يملك آلية تكيّف
  /// خاصة به، وقد يبدأ بالأعلى (تقدير نطاق أوّلي متفائل) أو يصعد إليها
  /// بمنتصف التشغيل — وهذا مرصود فعلياً بسجلَّين نجح فيهما التشغيل ثم
  /// تعثّر عند `_x/seg-83` و`_x/seg-3`. فنحذف الطبقة الأعلى من القائمة
  /// التي نسلّمها له (بالوكيل المحلي) بنفس منطق `prioritize`.
  ///
  /// تُبقي دائماً جودة واحدة على الأقل، وتُرجع `null` حين لا يوجد ما
  /// يُحذف — إشارة صريحة للمستدعي بأن يترك القائمة كما هي بلا أي تعديل.
  static Set<String>? allowedUrls(
    List<HlsVariant> variants, {
    Set<String> provenKeys = const <String>{},
  }) {
    if (variants.length < 2) return null;

    if (provenKeys.isNotEmpty) {
      // **سقف لا مطابقة**: نسمح بكل جودة ≤ أعلى جودة مُثبَتة، لا بالمُثبَتة
      // وحدها. مشغّل الموقع يبدأ عادةً من أدنى درجة ثم يصعد، فلو التقطنا
      // أول إثبات (الأدنى) وحصرنا القائمة به لحبسنا المشاهدة على 480p طوال
      // الحلقة — وهذا ما حصل فعلاً بسجل `HLS_VARIANT_CEILING: kept=1/2`.
      // السقف يُبقي مجال التكيّف كاملاً تحت المُثبَت، ويمنع فقط الطبقات
      // الأثقل التي لم يُثبِت أحد أن الشبكة تتحمّلها.
      var ceiling = -1;
      for (final variant in variants) {
        final key = variantKey(variant.url);
        if (key != null && provenKeys.contains(key) && variant.bandwidth > ceiling) {
          ceiling = variant.bandwidth;
        }
      }
      if (ceiling >= 0) {
        final allowed = <String>{
          for (final variant in variants)
            if (variant.bandwidth <= ceiling) variant.url,
        };
        if (allowed.isNotEmpty && allowed.length < variants.length) return allowed;
        return null;
      }
    }

    if (variants.length < _extraTierThreshold) return null;
    final sorted = [...variants]
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    return {for (final variant in sorted.skip(1)) variant.url};
  }
}
