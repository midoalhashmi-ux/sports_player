import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'hls_variant_selector.dart';

/// وكيل HLS محلي (127.0.0.1) يوضع بين المشغّل والمصدر الحقيقي — يجلب
/// الشرائح القادمة مسبقاً ويعيد محاولة الفاشلة منها تلقائياً، لتفادي
/// التقطيع الناتج عن `video_player` التي لا تعرض أي تحكم بحجم التخزين
/// المؤقت الأمامي لـExoPlayer.
///
/// **محاولة ثانية بعد فشل حقيقي مؤكَّد**: أول نسخة من هذا الملف (محذوفة
/// من السجل، راجع commit history) عُلِّقت فعلياً على جهاز حقيقي — سجل
/// تشخيص أظهر NATIVE محاولة تشغيل بلا نجاح ولا فشل مسجَّل لأكثر من 40
/// ثانية. السبب الدقيق لم يُؤكَّد (تحقّقنا أن الكيرت-تكست مسموح عالمياً
/// بـnetwork_security_config.xml، فليس السبب). هذي النسخة تضيف طبقتي أمان
/// لتفادي تكرار نفس الفشل الصامت:
/// 1. اختبار ذاتي فوري بعد بدء الخادم المحلي (جلب /pl من عندنا نحن، قبل
///    تسليم الرابط لـExoPlayer إطلاقاً) — لو فشل، `start()` يرجع null
///    فوراً ويُستخدَم الرابط الأصلي المباشر، فلا يصل ExoPlayer لخادم غير
///    مستجيب إطلاقاً.
/// 2. تسجيل كامل (`onLog`) لكل حدث مهم — لو تعلّق أو فشل شيء رغم هذا، سجل
///    تشخيص التطبيق (`sports_player_debug_log.txt`) يوضّح بالضبط أين ومتى.
/// بالإضافة لحد أقصى عام 15 ثانية على `initialize()` نفسها بـwatch_screen
/// (راجع _playServerQuality) — أي تعليق الآن يتحوّل لفشل واضح خلال 15
/// ثانية كحد أقصى، أياً كان السبب.
class HlsCacheProxy {
  HlsCacheProxy({
    this.onLog,
    this.isWebViewActiveNearby,
    this.onVariantsDiscovered,
  });

  /// (tag, detail) — يُمرَّر لـ_slog بـwatch_screen لتظهر بسجل التشخيص
  /// الذي يصدّره المستخدم، بنفس تنسيق بقية أحداث المشغّل.
  final void Function(String tag, String detail)? onLog;

  /// تشخيص فقط (لا يؤثر على أي منطق جلب/تزامن هنا): يرجع true لو WebView
  /// جلب مورد شبكة فعلي خلال آخر ثوانٍ قليلة — يُستدعى فقط عند تسجيل خطأ
  /// جلب، ليقول السجل مباشرة هل كان WebView نشطاً شبكياً بنفس لحظة فشل
  /// جلبنا (فرضية: اتصالات وكيلنا + WebView المتزامنة قد تتجاوز حد تحمّل
  /// الـCDN المنخفض أصلاً — راجع TECHNICAL.md #47).
  final bool Function()? isWebViewActiveNearby;

  /// يُبلَّغ بكل الجودات المكتشَفة داخل أي قائمة رئيسية تمر بالوكيل —
  /// تُبنى منها أزرار الجودة بشاشة المشاهدة. يُستدعى بالجودات **كاملة**
  /// (قبل تطبيق السقف) حتى يبقى للمستخدم خيار يدوي بكل الدرجات.
  final void Function(List<HlsVariant> variants)? onVariantsDiscovered;

  HttpServer? _server;
  http.Client? _client;
  Map<String, String> _upstreamHeaders = const {};

  /// قفل تسلسل بسيط حول `start()`/`stop()`.
  ///
  /// **خلل حقيقي مؤكَّد بسجل تشخيص**: `start()` يبدأ بـ`await stop()` ثم
  /// `await HttpServer.bind(...)`. أي استدعاءين متزامنين (يحصل فعلياً كل
  /// جلسة تقريباً: تجربة تشغيل أصلي + إنقاذ مانفست + تبديل جودة يدوي قد
  /// تتداخل) يتشابكان عند نقاط الـawait هذي: الثاني يستدعي `stop()` بينما
  /// `_server` لا يزال null (الأول لم ينهِ `bind` بعد) فلا يُغلق شيئاً،
  /// ثم كلاهما يكتب `_server = ...` — فيبقى خادم الأول **شغّالاً للأبد**
  /// بلا مرجع، مع طابور جلب مسبق حيّ يقصف نفس الـCDN بالتوازي مع الجلسة
  /// الجديدة. سجل المستخدم أظهر بالضبط هذا: تسعة `HLS_PROXY_STARTED`
  /// ببورتات مختلفة بجلسة واحدة (اثنان منها بفارق 2 ميلي ثانية)، ثم
  /// `Connection closed while receiving data` لشرائح جودة **سابقة** أثناء
  /// تشغيل جودة جديدة — وهو سبب فشل تبديل الجودة (`initialize()` ينتهي
  /// بمهلة 13 ثانية مرتين) والتقطيع معاً.
  Future<void> _lifecycleLock = Future<void>.value();

  /// يُسلسِل عملية دورة حياة (start/stop) خلف سابقتها — أبسط من mutex
  /// كامل، وكافٍ تماماً هنا لأن كل العمليات على نفس الـisolate.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _lifecycleLock;
    final completer = Completer<void>();
    _lifecycleLock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  /// مفاتيح الجودات التي أثبت مشغّل الموقع تشغيلها فعلاً بهذي الجلسة.
  /// فارغة = سلوك قديم حرفياً بلا أي تعديل على القائمة (راجع
  /// `_applyVariantCeiling`).
  Set<String> _provenVariantKeys = const <String>{};

  final Map<String, List<int>> _segmentCache = <String, List<int>>{};
  final List<String> _segmentCacheOrder = <String>[];
  int _segmentCacheBytes = 0;
  static const int _maxCacheBytes = 60 * 1024 * 1024; // 60MB

  /// ترتيب الشرائح **مفصولاً لكل قائمة تشغيل (جودة) على حدة**.
  ///
  /// **خلل بنيوي مؤكَّد بسجل تشخيص**: كانت قائمة واحدة مشتركة
  /// (`_segmentSequence`) تتراكم فيها شرائح كل الجودات معاً. عند تشغيل
  /// القائمة الرئيسية، يجلب ExoPlayer قوائم عدة جودات عبرنا، فتُلحَق
  /// شرائحها كلها بنفس التسلسل — ثم يصير "الشريحة التالية" بـ
  /// `_schedulePrefetch` شريحةً من **جودة أخرى تماماً**، ويصير أي تبديل
  /// جودة تكيّفي (ABR) يبدو كقفزة هائلة بالترتيب فيمسح
  /// `_dropStalePrefetches` الطابور بأكمله. سجل المستخدم يُظهر النتيجة
  /// حرفياً: `HLS_PREFETCH_DROPPED_STALE: dropped=8 around=181
  /// remaining=0` أثناء تشغيل سليم، أي أن التخزين المسبق أُفرِغ بالكامل
  /// وبقيت كل شريحة تالية تُجلب لحظياً — وهذا بالضبط شكل التقطيع
  /// (`تكسير`) المُبلَّغ عنه.
  final Map<String, List<String>> _playlistSequences =
      <String, List<String>>{};

  /// رابط الشريحة → مفتاح قائمة التشغيل التي تنتمي لها.
  final Map<String, String> _segmentPlaylist = <String, String>{};

  /// رابط الشريحة → ترتيبها **داخل قائمتها هي**. كان الترتيب يُستخرَج
  /// بـ`List.indexOf` (مسح خطي) مرة لكل شريحة يطلبها المشغّل **ومرة لكل
  /// عنصر بالطابور** داخل `_dropStalePrefetches`.
  final Map<String, int> _segmentIndex = <String, int>{};

  /// حد أقصى لعدد قوائم التشغيل المتتبَّعة بنفس الوقت (جودات مختلفة +
  /// انتقالات) — يمنع تضخّم الخرائط أعلاه بجلسة طويلة.
  static const int _maxTrackedPlaylists = 6;
  static const int _maxSegmentsPerPlaylist = 500;
  final Set<String> _prefetching = <String>{};

  /// جلبات جارية فعلاً الآن، مفهرسة بالرابط.
  ///
  /// **خلل حقيقي مؤكَّد بسجل تشخيص**: شريحة يجلبها الطابور بالخلفية ثم
  /// يطلبها ExoPlayer نفسها قبل اكتمالها كانت تُجلَب **مرتين بالتوازي**
  /// (الخلفية + الأمامية) — سجل المستخدم يُظهر سطرَي
  /// `HLS_PROXY_SEGMENT_FETCH_ERROR` لنفس `seg-1-v1-a1.ts` بنفس الطابع
  /// الزمني بالضبط وبـ`elapsedMs` مختلفين (4812 و12818). مضاعفة اتصالات
  /// لنفس الشريحة على CDN يحمي نفسه أصلاً من التزامن = قطع الاتصال لكليهما،
  /// وهو بالضبط ما أفشل تبديل الجودة. الآن الطلب الثاني ينضم لنتيجة الأول
  /// بدل فتح اتصال جديد.
  final Map<String, Future<List<int>?>> _inFlightFetches =
      <String, Future<List<int>?>>{};

  /// طابور الجلب المسبق + عدد الاتصالات الفعلية بالخلفية حالياً — الجذر
  /// الحقيقي لمشكلة تقطيع مؤكَّدة بسجل تشخيص فعلي بعد رفع `_prefetchAheadVod`
  /// لـ12: كل شرائح الهامش كانت تُطلَق دفعة واحدة كـ12 اتصال HTTP متزامن
  /// لنفس خادم CDN (`unawaited` بلا أي حد) — سجلات فعلية أظهرت عشرات
  /// "Connection closed while receiving data"/502/"Connection attempt
  /// cancelled" لعدة شرائح مختلفة **بفارق أقل من 5 ميلي ثانية بينها**، وهو
  /// نمط كلاسيكي لخادم يحمي نفسه من عدد اتصالات متزامنة كبير من نفس
  /// العميل (شائع جداً بمواقع البث المقرصنة) — لا علاقة له بجودة الشبكة.
  /// الحل: نفس مقدار التخزين المسبق (12 شريحة "بالطابور") لكنه يُنفَّذ
  /// بحد أقصى `_maxConcurrentPrefetch` اتصالات فعلية بنفس اللحظة فقط،
  /// والباقي ينتظر دوره — يقلّل ضغط الاتصالات المتزامنة جذرياً بدون
  /// التضحية بحجم التخزين المسبق نفسه.
  final List<String> _prefetchQueue = <String>[];
  int _activePrefetches = 0;
  static const int _maxConcurrentPrefetch = 3;

  /// رقم جيل الجلسة — يزيد بكل `stop()`. مراجعة كود لاحقة كشفت ثغرة حقيقية
  /// بنفس آلية الحد أعلاه: `stop()` يصفّر `_activePrefetches`/الطوابير،
  /// لكن مهام الجلب الفعلية (`unawaited` بـ`_pumpPrefetchQueue`) المُطلَقة
  /// *قبل* `stop()` تبقى شغّالة بالخلفية ولا تُلغى — عند اكتمالها لاحقاً
  /// (بعد `start()` جديد لجلسة تالية بنفس الكائن)، كتلة `finally` الخاصة
  /// بها كانت تُنقِص `_activePrefetches` وتستدعي `_pumpPrefetchQueue()` على
  /// حالة الجلسة *الجديدة* — يدفع العداد لسالب ويُطلق اتصالات إضافية تتجاوز
  /// الحد `_maxConcurrentPrefetch`، فيعيد إنتاج نفس مشكلة قصف الاتصالات
  /// المتزامنة اللي هذا الحد أُضيف أصلاً ليمنعها. كل مهمة جلب تحجز رقم
  /// الجيل وقت إطلاقها، وتتجاهل تحديث الحالة المشتركة لو تغيّر الجيل
  /// (يعني جلسة جديدة بدأت) بحلول وقت اكتمالها.
  int _proxyGeneration = 0;

  /// المصدر معلوماته الحقيقية تُكتشَف فقط بعد أول قائمة تشغيل تُجلب فعلياً
  /// (`_rewritePlaylist` تحدّثها). القيمة الافتراضية `false` قبل ذلك تعني
  /// "نتعامل معه كبث مباشر مؤقتاً" — الأكثر أماناً حتى نتأكد فعلياً.
  bool _sourceHasKnownEnd = false;

  /// مقدار الجلب المسبق (بعدد الشرائح) يختلف فعلياً حسب نوع المصدر — هذا
  /// جوهر طلب "يفرّق المشغّل لو أعطاه نهاية للفيديو": فيديو منتهٍ فعلياً
  /// (`#EXT-X-ENDLIST` موجود) كامل ومعروف الحجم مسبقاً، فلا خطر من التخزين
  /// المسبق الجريء (نفس مبدأ يوتيوب: يخزّن للأمام لدقائق أحياناً)، عكس بث
  /// حي فعلي حيث الشرائح البعيدة غير موجودة أصلاً بعد على الخادم.
  static const int _prefetchAheadLive = 4;
  static const int _prefetchAheadVod = 12;
  int get _prefetchAhead =>
      _sourceHasKnownEnd ? _prefetchAheadVod : _prefetchAheadLive;

  /// هامش أمان خلف الحافة الحقيقية للبث المباشر (بالشرائح) — نفس مبدأ
  /// تأخير البث المباشر المتعمَّد المستخدَم فعلياً بمشغّلات احترافية
  /// (يوتيوب/تويتش) بدل اللحاق بآخر شريحة صدرت من المصدر لحظياً: نخفي عن
  /// ExoPlayer آخر `_liveEdgeMarginSegments` شرائح من قائمة التشغيل، ونجلبها
  /// نحن بالخلفية بالتوازي (`_prefetchNearLiveEdge`) قبل ما تظهر له أصلاً
  /// بتحديث لاحق للقائمة — فبحلول وقت ما ExoPlayer يطلبها فعلياً تكون جاهزة
  /// بالكاش مسبقاً، بدل ما ينتظرها لحظة الطلب (وهذا بالضبط سبب التقطيع
  /// بالبث المباشر: أي شريحة جديدة تحتاج جلبها لحظياً من مصدر قد يكون بطيئاً
  /// أو غير مستقر). لا يُطبَّق على قوائم VOD (فيها #EXT-X-ENDLIST) ولا على
  /// قوائم الجودات الرئيسية (master playlist) — فقط قوائم الشرائح الفعلية
  /// لبث لا يزال مستمراً.
  static const int _liveEdgeMarginSegments = 2;

  void _log(String tag, String detail) {
    try {
      onLog?.call(tag, detail);
    } catch (_) {}
  }

  bool get isRunning => _server != null;

  static bool looksLikeHlsPlaylist(String url) {
    final lower = url.toLowerCase().split('?').first;
    return lower.endsWith('.m3u8') || lower.endsWith('.m3u');
  }

  static bool _looksLikePlaylistUri(Uri uri) {
    final lower = uri.path.toLowerCase();
    return lower.endsWith('.m3u8') || lower.endsWith('.m3u');
  }

  /// يبدأ الوكيل ويعيد رابطاً محلياً بديلاً، بعد التأكد فعلياً أنه
  /// يستجيب (اختبار ذاتي). يعيد null لو لم يكن الرابط HLS، أو لو فشل
  /// تشغيل/استجابة الخادم المحلي لأي سبب — عندها يجب على المستدعي
  /// استخدام الرابط الأصلي كما هو (بلا أي تغيير بالسلوك القديم).
  /// نقطة الدخول العامة — مُسلسَلة خلف أي `start`/`stop` سابق (راجع
  /// `_lifecycleLock`). المنطق الفعلي بـ`_startLocked`، ويستدعي
  /// `_stopLocked` مباشرة بدل `stop()` العامة تفادياً لقفل ذاتي.
  Future<Uri?> start({
    required String sourceUrl,
    required Map<String, String> headers,
    Set<String> provenVariantKeys = const <String>{},
  }) {
    if (!looksLikeHlsPlaylist(sourceUrl)) return Future<Uri?>.value();
    return _serialized(() => _startLocked(
          sourceUrl: sourceUrl,
          headers: headers,
          provenVariantKeys: provenVariantKeys,
        ));
  }

  Future<void> stop() => _serialized(_stopLocked);

  Future<Uri?> _startLocked({
    required String sourceUrl,
    required Map<String, String> headers,
    required Set<String> provenVariantKeys,
  }) async {
    await _stopLocked();
    try {
      _upstreamHeaders = headers;
      _provenVariantKeys = provenVariantKeys;
      // تشخيص فقط: أسماء الهيدرز الفعلية (لا قيمها — قد تحوي كوكيز/توكن
      // جلسة الموقع) المُرسَلة لكل طلب قائمة/شريحة بهذي الجلسة، للمقارنة
      // مع ما يرسله WebView نفسه (راجع مناقشة سبب فشل جلب الشرائح رغم
      // نجاح WebView المتزامن لنفس الرابط بـTECHNICAL.md).
      _log('HLS_PROXY_HEADERS', 'keys=${headers.keys.join(",")}');
      _client = http.Client();
      final server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
      _server = server;
      unawaited(_serve(server));
      final port = server.port;
      final encoded = Uri.encodeComponent(sourceUrl);
      final localUri = Uri.parse('http://127.0.0.1:$port/pl?u=$encoded');
      _log('HLS_PROXY_STARTED', 'port=$port');

      // اختبار ذاتي: تأكيد فعلي أن الخادم المحلي يستجيب فعلاً قبل ما
      // نسلّم الرابط لـExoPlayer إطلاقاً — هذا الفرق الجوهري عن المحاولة
      // السابقة التي عُلِّقت بصمت.
      final selfTestStart = DateTime.now();
      try {
        final probe = await http
            .get(localUri)
            .timeout(const Duration(seconds: 5));
        final elapsedMs = DateTime.now().difference(selfTestStart).inMilliseconds;
        if (probe.statusCode < 200 || probe.statusCode >= 300) {
          _log('HLS_PROXY_SELFTEST_FAILED',
              'status=${probe.statusCode} elapsedMs=$elapsedMs — falling back to direct URL');
          await _stopLocked();
          return null;
        }
        _log('HLS_PROXY_SELFTEST_OK', 'elapsedMs=$elapsedMs bodyLen=${probe.body.length}');
      } catch (e) {
        _log('HLS_PROXY_SELFTEST_FAILED', 'error=$e — falling back to direct URL');
        await _stopLocked();
        return null;
      }
      return localUri;
    } catch (e) {
      _log('HLS_PROXY_START_ERROR', 'error=$e');
      await _stopLocked();
      return null;
    }
  }

  Future<void> _stopLocked() async {
    _proxyGeneration++;
    final server = _server;
    _server = null;
    _client?.close();
    _client = null;
    _segmentCache.clear();
    _segmentCacheOrder.clear();
    _segmentCacheBytes = 0;
    _playlistSequences.clear();
    _segmentPlaylist.clear();
    _segmentIndex.clear();
    _inFlightFetches.clear();
    _prefetching.clear();
    _prefetchQueue.clear();
    _activePrefetches = 0;
    _sourceHasKnownEnd = false;
    _provenVariantKeys = const <String>{};
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      final encodedUrl = request.uri.queryParameters['u'];
      if (encodedUrl == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      final originalUrl = encodedUrl;
      if (path == '/pl') {
        await _handlePlaylist(request, originalUrl);
      } else if (path == '/seg') {
        await _handleSegment(request, originalUrl);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (e) {
      _log('HLS_PROXY_REQUEST_ERROR', 'path=${request.uri.path} error=$e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handlePlaylist(HttpRequest request, String originalUrl) async {
    final baseUri = Uri.parse(originalUrl);
    String? body;

    // منقذ WebView (_relayManifestViaWebView بـwatch_screen.dart) أحياناً
    // يكتب القائمة الرئيسية محلياً كملف (file://) بدل جلبها مباشرة —
    // http.Client لا يدعم file:// إطلاقاً (خطأ "No host specified in URI"
    // مؤكَّد بسجل تشخيص فعلي سابق). قبل هذا الإصلاح كنا نتخطّى الوكيل
    // بالكامل لهذي الحالة، فيفقد الفيديو أي تخزين مؤقت/إعادة محاولة
    // للشرائح البعيدة اللي القائمة نفسها تشير لها — سجل تشخيص فعلي لاحق
    // أظهر تقطيعاً شديداً بالضبط بهذا المسار (لا مؤشر HLS_PROXY_* إطلاقاً
    // أثناء التشغيل، يعني ExoPlayer يجلب كل شريحة مباشرة بلا أي حماية).
    // الحل: نقرأ الملف المحلي مباشرة بدل جلبه عبر HTTP — بقية الوكيل
    // (تخزين/جلب مسبق/إعادة محاولة للشرائح البعيدة الفعلية داخل القائمة)
    // يشتغل بعدها بالضبط كأي مصدر HTTP عادي.
    if (baseUri.scheme == 'file') {
      try {
        body = await File(baseUri.toFilePath()).readAsString();
      } catch (e) {
        _log('HLS_PROXY_PLAYLIST_FETCH_ERROR', 'attempt=0 error=$e (local file)');
      }
    } else {
      // نفس إصلاح `_fetchSegmentWithRetry`: نتحقق من الجيل ونُعيد قراءة
      // `_client` طازجاً بكل محاولة بدل التقاطه مرة واحدة — نفس فئة الخلل
      // (تبديل المرشّح بين محاولتي إعادة الجلب يُغلق الـclient من تحتها).
      final generation = _proxyGeneration;
      for (var attempt = 0; attempt < 2 && body == null; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(milliseconds: 300));
        if (generation != _proxyGeneration) break;
        final client = _client;
        if (client == null) break;
        final attemptStopwatch = Stopwatch()..start();
        try {
          final resp = await client
              .get(baseUri, headers: _upstreamHeaders)
              .timeout(const Duration(seconds: 12));
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            body = resp.body;
          } else {
            _log('HLS_PROXY_PLAYLIST_HTTP_ERROR',
                'attempt=$attempt status=${resp.statusCode} elapsedMs=${attemptStopwatch.elapsedMilliseconds}');
          }
        } catch (e) {
          _log('HLS_PROXY_PLAYLIST_FETCH_ERROR',
              'attempt=$attempt elapsedMs=${attemptStopwatch.elapsedMilliseconds} error=$e');
        }
      }
    }
    if (body == null) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }
    final server = _server;
    final port = server?.port ?? request.connectionInfo?.localPort ?? 0;
    final rewritten = _rewritePlaylist(body, baseUri, port);
    request.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.write(rewritten);
    await request.response.close();
  }

  /// يعيد كتابة قائمة التشغيل مع تطبيق هامش أمان خلف حافة البث المباشر
  /// (راجع `_liveEdgeMarginSegments` أعلاه). يجمع الأسطر بمجموعات لكل
  /// شريحة (وسوم `#EXTINF`/`#EXT-X-DISCONTINUITY`/... التي تسبقها مباشرة +
  /// سطر رابطها) حتى نقدر نحذف آخر مجموعات بأمان دون كسر بنية القائمة —
  /// خلاف قوائم الجودات الرئيسية (master playlist، روابطها قوائم فرعية لا
  /// شرائح) وقوائم VOD المكتملة (فيها `#EXT-X-ENDLIST`)، واللي تبقى بلا أي
  /// حذف إطلاقاً.
  String _rewritePlaylist(String text, Uri baseUri, int port) {
    final hasEndlist = text.contains('#EXT-X-ENDLIST');
    final lines = text.split('\n');
    final newSequence = <String>[];
    final uriAttrPattern = RegExp(r'URI="([^"]+)"');

    String proxify(Uri resolved) {
      final isPlaylist = _looksLikePlaylistUri(resolved);
      final encoded = Uri.encodeComponent(resolved.toString());
      if (!isPlaylist) newSequence.add(resolved.toString());
      return 'http://127.0.0.1:$port/${isPlaylist ? 'pl' : 'seg'}?u=$encoded';
    }

    // كل مجموعة: وسوم سبقت رابطاً + سطر الرابط نفسه (مُعاد كتابته مسبقاً).
    final blocks = <List<String>>[];
    // الرابط **الأصلي** لكل مجموعة قبل تحويله لرابط الوكيل — مطلوب لفحص
    // سقف الجودة أدناه (بعد `proxify` يصبح كل الروابط 127.0.0.1).
    final blockUrls = <String?>[];
    var pending = <String>[];
    var sawSegmentUri = false;
    var sawPlaylistUri = false;

    for (final rawLine in lines) {
      final line = rawLine.replaceAll('\r', '');
      if (line.trim().isEmpty) {
        pending.add('');
        continue;
      }
      if (line.startsWith('#')) {
        if (uriAttrPattern.hasMatch(line)) {
          final replaced = line.replaceAllMapped(uriAttrPattern, (m) {
            try {
              final resolved = baseUri.resolve(m.group(1)!);
              return 'URI="${proxify(resolved)}"';
            } catch (_) {
              return m.group(0)!;
            }
          });
          pending.add(replaced);
        } else {
          pending.add(line);
        }
      } else {
        try {
          final resolved = baseUri.resolve(line.trim());
          final isPlaylist = _looksLikePlaylistUri(resolved);
          if (isPlaylist) {
            sawPlaylistUri = true;
          } else {
            sawSegmentUri = true;
          }
          pending.add(proxify(resolved));
          blocks.add(pending);
          blockUrls.add(resolved.toString());
          pending = <String>[];
        } catch (_) {
          pending.add(line);
          blocks.add(pending);
          blockUrls.add(null);
          pending = <String>[];
        }
      }
    }
    final trailing = pending; // وسوم بلا رابط تالٍ (نادر بقائمة بث مباشر)

    final isLiveMediaPlaylist = sawSegmentUri && !sawPlaylistUri && !hasEndlist;
    // جوهر التفريق المطلوب: قائمة شرائح فعلية (لا قائمة جودات رئيسية) هي
    // المصدر الوحيد اللي يقدر "يعطي نهاية" فعلية — إن وُجد #EXT-X-ENDLIST
    // بها فالمصدر منتهٍ فعلياً ومعروف الحجم بالكامل (نفس فيديو يوتيوب عادي)
    // فنخزّن مسبقاً أبعد وأجرأ (_prefetchAheadVod)، عكس بث مباشر فعلي حيث
    // لا نعرف حتى متى ينتهي أصلاً.
    if (sawSegmentUri && !sawPlaylistUri) {
      _sourceHasKnownEnd = hasEndlist;
      _log('HLS_SOURCE_CLASSIFIED',
          'hasEndlist=$hasEndlist prefetchAhead=${hasEndlist ? _prefetchAheadVod : _prefetchAheadLive}');
    }
    var effectiveBlocks =
        (isLiveMediaPlaylist && blocks.length > _liveEdgeMarginSegments + 2)
            ? blocks.sublist(0, blocks.length - _liveEdgeMarginSegments)
            : blocks;

    // قائمة جودات رئيسية (روابطها قوائم فرعية لا شرائح): نطبّق سقف الجودة.
    if (sawPlaylistUri && !sawSegmentUri) {
      effectiveBlocks = _applyVariantCeiling(effectiveBlocks, blockUrls);
    }

    final out = StringBuffer();
    for (final block in effectiveBlocks) {
      for (final l in block) {
        out.writeln(l);
      }
    }
    for (final l in trailing) {
      out.writeln(l);
    }

    if (newSequence.isNotEmpty) {
      _absorbSequence(baseUri.toString(), newSequence);
      if (isLiveMediaPlaylist) {
        // نجلب أحدث الشرائح بالخلفية فوراً — بما فيها المخفية عن ExoPlayer
        // بهامش الأمان أعلاه — حتى تكون جاهزة بالكاش قبل ما تُكشَف له
        // بتحديث لاحق للقائمة، بدل ما ينتظرها لحظة الطلب.
        _prefetchNearLiveEdge(newSequence);
      }
    }
    return out.toString();
  }

  /// يحذف الجودات الأثقل من القائمة الرئيسية قبل تسليمها لـExoPlayer.
  ///
  /// الترتيب وحده لا يكفي هنا: ExoPlayer يملك آلية تكيّف خاصة به، فيقدر
  /// يبدأ بالأعلى (تقدير نطاق أوّلي متفائل) أو يصعد إليها بمنتصف التشغيل —
  /// وكلاهما مرصود بسجلات فعلية (`_x/seg-1` بالبداية، و`_x/seg-83`
  /// بالمنتصف بعد تشغيل ناجح). القرار نفسه معزول ومُختبَر بوحدة
  /// `HlsVariantSelector` (راجع `test/hls_variant_selector_test.dart`).
  ///
  /// آمن بالكامل: لو رجعت الوحدة `null` (جودة واحدة، أو لا شيء يُحذف)
  /// تُعاد المجموعات كما هي حرفياً بلا أي تعديل.
  List<List<String>> _applyVariantCeiling(
    List<List<String>> blocks,
    List<String?> blockUrls,
  ) {
    final variants = <HlsVariant>[];
    for (var i = 0; i < blocks.length && i < blockUrls.length; i++) {
      final url = blockUrls[i];
      if (url == null) continue;
      final streamInf = blocks[i].firstWhere(
        (line) => line.startsWith('#EXT-X-STREAM-INF'),
        orElse: () => '',
      );
      if (streamInf.isEmpty) continue;
      final bandwidth = int.tryParse(
              RegExp(r'BANDWIDTH=(\d+)').firstMatch(streamInf)?.group(1) ?? '') ??
          0;
      final height =
          RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(streamInf)?.group(1);
      final label = height != null
          ? '${height}p'
          : (bandwidth > 0 ? '${(bandwidth / 1000).round()} كيلوبت/ث' : 'تلقائي');
      variants.add(HlsVariant(bandwidth: bandwidth, label: label, url: url));
    }
    if (variants.length < 2) return blocks;

    // نبلّغ بالقائمة **الكاملة** قبل السقف — أزرار الجودة بالواجهة يجب أن
    // تعرض كل الدرجات، فالسقف تلقائي والمستخدم يبقى سيّد اختياره.
    try {
      onVariantsDiscovered?.call(List<HlsVariant>.unmodifiable(variants));
    } catch (_) {}

    final allowed = HlsVariantSelector.allowedUrls(
      variants,
      provenKeys: _provenVariantKeys,
    );
    if (allowed == null) return blocks;

    final kept = <List<String>>[];
    for (var i = 0; i < blocks.length; i++) {
      final url = i < blockUrls.length ? blockUrls[i] : null;
      // مجموعة بلا رابط (وسوم فقط) تبقى دائماً — لا نكسر بنية القائمة.
      if (url == null || allowed.contains(url)) kept.add(blocks[i]);
    }
    if (kept.isEmpty) return blocks;
    _log('HLS_VARIANT_CEILING',
        'kept=${allowed.length}/${variants.length} proven=${_provenVariantKeys.length}');
    return kept;
  }

  /// يدمج ترتيب شرائح قائمة تشغيل واحدة بخرائط التتبّع، ويقصّ القديم.
  void _absorbSequence(String playlistKey, List<String> newSequence) {
    final sequence =
        _playlistSequences.putIfAbsent(playlistKey, () => <String>[]);
    for (final url in newSequence) {
      if (_segmentPlaylist[url] == playlistKey) continue;
      _segmentPlaylist[url] = playlistKey;
      _segmentIndex[url] = sequence.length;
      sequence.add(url);
    }
    if (sequence.length > _maxSegmentsPerPlaylist) {
      final dropped =
          sequence.sublist(0, sequence.length - _maxSegmentsPerPlaylist);
      sequence.removeRange(0, dropped.length);
      for (final url in dropped) {
        _segmentIndex.remove(url);
        _segmentPlaylist.remove(url);
      }
      for (var i = 0; i < sequence.length; i++) {
        _segmentIndex[sequence[i]] = i;
      }
    }
    // خرائط Dart تحفظ ترتيب الإدراج، فأول مفتاح هو أقدم قائمة تتبّعناها.
    while (_playlistSequences.length > _maxTrackedPlaylists) {
      final oldestKey = _playlistSequences.keys.first;
      final oldest = _playlistSequences.remove(oldestKey) ?? const <String>[];
      for (final url in oldest) {
        _segmentIndex.remove(url);
        _segmentPlaylist.remove(url);
      }
    }
  }

  void _prefetchNearLiveEdge(List<String> sequence) {
    final startIndex =
        (sequence.length - (_prefetchAhead + _liveEdgeMarginSegments))
            .clamp(0, sequence.length);
    for (var i = startIndex; i < sequence.length; i++) {
      _prefetchUrl(sequence[i]);
    }
  }

  void _prefetchUrl(String url) {
    // _prefetchQueue.contains(url) لم يعد يُفحَص هنا: أي رابط بالطابور يكون
    // فعلاً بـ_prefetching دائماً بنفس اللحظة (يُضافان معاً أدناه، ويُزالان
    // معاً فقط عند اكتمال الجلب) — فحص القائمة إضافي بلا فائدة (ومسح خطي
    // O(n) بلا داعٍ لكل رابط مكتشَف).
    if (_segmentCache.containsKey(url) || _prefetching.contains(url)) {
      return;
    }
    // نحجز فوراً (قبل حتى ما يبدأ الجلب الفعلي) حتى استدعاء متكرر لنفس
    // الرابط أثناء انتظاره بالطابور لا يُضيفه مرتين.
    _prefetching.add(url);
    _prefetchQueue.add(url);
    _pumpPrefetchQueue();
  }

  void _pumpPrefetchQueue() {
    // كل مهمة تحجز جيل الجلسة الحالي وقت إطلاقها — لو `stop()` استُدعيت
    // (جيل جديد) قبل ما تكتمل، تتجاهل تحديث الحالة المشتركة بدل ما تُفسد
    // عدّاد/طابور جلسة تالية بالخطأ (راجع تعليق `_proxyGeneration` أعلاه).
    final generation = _proxyGeneration;
    while (_activePrefetches < _maxConcurrentPrefetch &&
        _prefetchQueue.isNotEmpty) {
      final url = _prefetchQueue.removeAt(0);
      _activePrefetches++;
      unawaited(() async {
        try {
          final bytes = await _fetchSegmentShared(url);
          if (bytes != null && generation == _proxyGeneration) {
            _cacheSegment(url, bytes);
          }
        } finally {
          if (generation == _proxyGeneration) {
            _prefetching.remove(url);
            _activePrefetches--;
            _pumpPrefetchQueue();
          }
        }
      }());
    }
  }

  Future<void> _handleSegment(HttpRequest request, String originalUrl) async {
    var bytes = _segmentCache[originalUrl];
    if (bytes == null) {
      _dropStalePrefetches(originalUrl);
      final generation = _proxyGeneration;
      // ننضم لجلب جارٍ لنفس الشريحة إن وُجد (راجع `_inFlightFetches`) بدل
      // فتح اتصال ثانٍ متوازٍ لنفس الرابط.
      final joinedBackgroundFetch = _inFlightFetches.containsKey(originalUrl);
      bytes = await _fetchSegmentShared(originalUrl, foreground: true);
      // الجلب المسبق بالخلفية يأخذ مهلة أقصر (6ث) ومحاولتين فقط. لو كنا
      // انضممنا لواحد منها وفشل، نستحق محاولة أمامية كاملة واحدة قبل ما
      // نردّ 502 — فالمشغّل ينتظر هذي الشريحة الآن فعلاً. الشرط
      // `joinedBackgroundFetch` ضروري: بدونه كان الفشل الأمامي العادي
      // يُضاعَف (3 محاولات × 15ث مرتين = حتى 90 ثانية على شريحة ميتة).
      if (bytes == null &&
          joinedBackgroundFetch &&
          generation == _proxyGeneration) {
        bytes = await _fetchSegmentShared(originalUrl, foreground: true);
      }
      if (bytes != null) _cacheSegment(originalUrl, bytes);
    }
    // جسم فارغ (200 OK بلا بيانات) مصدر فعلي غير نظري — بعض خوادم CDN
    // المتقلقلة تفعلها فعلياً (`_fetchSegmentWithRetry` يقبل أي حالة 2xx
    // بغض النظر عن الحجم). بلا هذا الفحص، `bytes.length - 1` يصير -1
    // و`start.clamp(0, -1)` يرمي ArgumentError لاحقاً (Dart يرفض
    // lowerLimit > upperLimit) — يُعامَل الآن كفشل جلب عادي (502)، بنفس
    // مسار `bytes == null` أعلاه، بدل استثناء غير متوقَّع.
    if (bytes == null || bytes.isEmpty) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }
    _schedulePrefetch(originalUrl);

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = (parts.length > 1 && parts[1].isNotEmpty)
          ? int.tryParse(parts[1]) ?? (bytes.length - 1)
          : bytes.length - 1;
      final safeStart = start.clamp(0, bytes.length - 1);
      final safeEnd = end.clamp(safeStart, bytes.length - 1);
      final slice = bytes.sublist(safeStart, safeEnd + 1);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $safeStart-$safeEnd/${bytes.length}',
      );
      request.response.headers.contentLength = slice.length;
      request.response.add(slice);
      await request.response.close();
      return;
    }

    request.response.headers.contentLength = bytes.length;
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.add(bytes);
    await request.response.close();
  }

  /// يُلغي الجلب المسبق الذي لم يعد له معنى بعد قفزة بالفيديو (seek).
  ///
  /// **سبب وجودها (مؤكَّد بسجل فعلي)**: عند التقديم لدقيقة 8، يطلب ExoPlayer
  /// شريحة بعيدة، بينما طابور الجلب المسبق لا يزال مملوءاً بشرائح البداية
  /// (`seg-2`, `seg-6`, `seg-7`, `seg-24`). تلك الشرائح الميتة كانت تحتجز
  /// **كل** فتحات التزامن الثلاث بمهلة 15 ثانية × 3 محاولات = حتى 45 ثانية
  /// لكل واحدة، فتتضوّر الشريحة التي يحتاجها المشغّل فعلاً الآن → تجمّد →
  /// `Source error` → إعادة اتصال. راجع TECHNICAL.md #53.
  void _dropStalePrefetches(String requestedUrl) {
    if (_prefetchQueue.isEmpty) return;
    final index = _segmentIndex[requestedUrl] ?? -1;
    if (index < 0) return;
    final playlistKey = _segmentPlaylist[requestedUrl];
    final horizon = index + _prefetchAhead + 4;
    final stale = _prefetchQueue
        .where((url) {
          // شريحة من قائمة/جودة أخرى لم يعد لها معنى بعد ما انتقل المشغّل
          // لهذي القائمة — تُسقَط دائماً بغض النظر عن ترتيبها.
          if (_segmentPlaylist[url] != playlistKey) return true;
          final position = _segmentIndex[url] ?? -1;
          return position < index || position > horizon;
        })
        .toList();
    if (stale.isEmpty) return;
    for (final url in stale) {
      _prefetchQueue.remove(url);
      _prefetching.remove(url);
    }
    _log('HLS_PREFETCH_DROPPED_STALE',
        'dropped=${stale.length} around=$index remaining=${_prefetchQueue.length}');
  }

  /// يضمن اتصالاً شبكياً واحداً فقط لكل رابط شريحة بنفس اللحظة: أي طالب
  /// ثانٍ (أمامي أو مسبق) ينتظر نتيجة الأول بدل فتح اتصال موازٍ له.
  ///
  /// لو كان الجلب الجاري مسبقاً (خلفية) وجاء طلب أمامي، نتركه ينتظر نفس
  /// النتيجة — مهلة الخلفية أقصر، لذا `_handleSegment` يعيد المحاولة مرة
  /// واحدة بمهلة أمامية كاملة لو رجعت null.
  Future<List<int>?> _fetchSegmentShared(String url,
      {bool foreground = false}) {
    final existing = _inFlightFetches[url];
    if (existing != null) return existing;
    final future = _fetchSegmentWithRetry(url, foreground: foreground);
    _inFlightFetches[url] = future;
    return future.whenComplete(() {
      if (identical(_inFlightFetches[url], future)) {
        _inFlightFetches.remove(url);
      }
    });
  }

  /// `foreground`: طلب يحتاجه المشغّل الآن (يحجب التشغيل) — يستحق مهلة
  /// كاملة. الجلب المسبق بالخلفية يأخذ مهلة أقصر بكثير: تعليقه الطويل هو
  /// ما كان يخنق فتحات التزامن ويجمّد المشاهدة.
  Future<List<int>?> _fetchSegmentWithRetry(String url,
      {bool foreground = false}) async {
    // ملتقَط الجيل *وليس* الـclient نفسه: قبل الإصلاح كان `client` يُلتقَط
    // مرة واحدة بأول السطر ويُعاد استخدامه بكل محاولات إعادة الجلب الثلاث
    // — لو `stop()` استُدعيت بينهما (تبديل المرشّح لرابط بث آخر أثناء نفس
    // الجلسة، يحصل فعلياً بكل تشغيل تقريباً) كانت المحاولات المتبقية تفشل
    // حتماً بخطأ "Client is already closed" رغم إنه لا علاقة له بالشبكة
    // إطلاقاً — سجل تشخيص فعلي أظهر هذا النمط بالضبط 3 مرات متتالية (محاولة
    // 0 فشل اتصال حقيقي، محاولتا 1 و2 "already closed") مع كل بورت وكيل
    // جديد، فيضيع أي فرصة نجاح فعلية للشريحة ويُعلَّق المشغّل بلا نهاية.
    // الحل: نتحقق من الجيل ونُعيد قراءة `_client` طازجاً *قبل كل محاولة*،
    // ونتوقف فوراً لو تغيّر الجيل بدل تضييع وقت بمحاولات فاشلة حتماً — هذا
    // فعلياً يُسرّع تحرّر فتحات الجلب المتوازي (`_maxConcurrentPrefetch`)
    // لصالح الجلسة الجديدة بدل حجزها بمحاولات ميتة.
    final generation = _proxyGeneration;
    final maxAttempts = foreground ? 3 : 2;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 200 * attempt * attempt));
      }
      if (generation != _proxyGeneration) return null;
      final client = _client;
      if (client == null) return null;
      // elapsedMs تشخيص فقط (Stopwatch لا يغيّر أي توقيت/مهلة فعلية):
      // فشل فوري (<500ms) يرجّح رفضاً نشطاً من الـCDN لهذا العميل تحديداً
      // (بصمة/هيدرز/توقيع)، بينما اقتراب من حد الـ15 ثانية يرجّح تعليق
      // شبكة فعلي — يفرّق بين فرضيتين مختلفتين تماماً بسطر سجل واحد.
      final attemptStopwatch = Stopwatch()..start();
      try {
        final resp = await client
            .get(Uri.parse(url), headers: _upstreamHeaders)
            .timeout(Duration(seconds: foreground ? 15 : 6));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return resp.bodyBytes;
        }
        _log('HLS_PROXY_SEGMENT_HTTP_ERROR',
            'attempt=$attempt status=${resp.statusCode} elapsedMs=${attemptStopwatch.elapsedMilliseconds} webViewActiveNearby=${isWebViewActiveNearby?.call()}');
      } catch (e) {
        _log('HLS_PROXY_SEGMENT_FETCH_ERROR',
            'attempt=$attempt elapsedMs=${attemptStopwatch.elapsedMilliseconds} webViewActiveNearby=${isWebViewActiveNearby?.call()} error=$e');
      }
    }
    return null;
  }

  void _cacheSegment(String url, List<int> bytes) {
    if (_segmentCache.containsKey(url)) return;
    _segmentCache[url] = bytes;
    _segmentCacheOrder.add(url);
    _segmentCacheBytes += bytes.length;
    while (_segmentCacheBytes > _maxCacheBytes && _segmentCacheOrder.isNotEmpty) {
      final oldest = _segmentCacheOrder.removeAt(0);
      final removed = _segmentCache.remove(oldest);
      if (removed != null) _segmentCacheBytes -= removed.length;
    }
  }

  void _schedulePrefetch(String justRequestedUrl) {
    final index = _segmentIndex[justRequestedUrl] ?? -1;
    if (index < 0) return;
    final sequence = _playlistSequences[_segmentPlaylist[justRequestedUrl]];
    if (sequence == null) return;
    for (var i = index + 1;
        i <= index + _prefetchAhead && i < sequence.length;
        i++) {
      _prefetchUrl(sequence[i]);
    }
  }
}
