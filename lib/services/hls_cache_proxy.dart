import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

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
  HlsCacheProxy({this.onLog});

  /// (tag, detail) — يُمرَّر لـ_slog بـwatch_screen لتظهر بسجل التشخيص
  /// الذي يصدّره المستخدم، بنفس تنسيق بقية أحداث المشغّل.
  final void Function(String tag, String detail)? onLog;

  HttpServer? _server;
  http.Client? _client;
  Map<String, String> _upstreamHeaders = const {};

  final Map<String, List<int>> _segmentCache = <String, List<int>>{};
  final List<String> _segmentCacheOrder = <String>[];
  int _segmentCacheBytes = 0;
  static const int _maxCacheBytes = 60 * 1024 * 1024; // 60MB

  final List<String> _segmentSequence = <String>[];
  final Set<String> _prefetching = <String>{};

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
  Future<Uri?> start({
    required String sourceUrl,
    required Map<String, String> headers,
  }) async {
    if (!looksLikeHlsPlaylist(sourceUrl)) return null;
    await stop();
    try {
      _upstreamHeaders = headers;
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
          await stop();
          return null;
        }
        _log('HLS_PROXY_SELFTEST_OK', 'elapsedMs=$elapsedMs bodyLen=${probe.body.length}');
      } catch (e) {
        _log('HLS_PROXY_SELFTEST_FAILED', 'error=$e — falling back to direct URL');
        await stop();
        return null;
      }
      return localUri;
    } catch (e) {
      _log('HLS_PROXY_START_ERROR', 'error=$e');
      await stop();
      return null;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _client?.close();
    _client = null;
    _segmentCache.clear();
    _segmentCacheOrder.clear();
    _segmentCacheBytes = 0;
    _segmentSequence.clear();
    _prefetching.clear();
    _prefetchQueue.clear();
    _activePrefetches = 0;
    _sourceHasKnownEnd = false;
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
      final client = _client;
      if (client == null) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      for (var attempt = 0; attempt < 2 && body == null; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(milliseconds: 300));
        try {
          final resp = await client
              .get(baseUri, headers: _upstreamHeaders)
              .timeout(const Duration(seconds: 12));
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            body = resp.body;
          } else {
            _log('HLS_PROXY_PLAYLIST_HTTP_ERROR',
                'attempt=$attempt status=${resp.statusCode}');
          }
        } catch (e) {
          _log('HLS_PROXY_PLAYLIST_FETCH_ERROR', 'attempt=$attempt error=$e');
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
          pending = <String>[];
        } catch (_) {
          pending.add(line);
          blocks.add(pending);
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
    final effectiveBlocks =
        (isLiveMediaPlaylist && blocks.length > _liveEdgeMarginSegments + 2)
            ? blocks.sublist(0, blocks.length - _liveEdgeMarginSegments)
            : blocks;

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
      for (final url in newSequence) {
        if (!_segmentSequence.contains(url)) _segmentSequence.add(url);
      }
      if (_segmentSequence.length > 500) {
        _segmentSequence.removeRange(0, _segmentSequence.length - 500);
      }
      if (isLiveMediaPlaylist) {
        // نجلب أحدث الشرائح بالخلفية فوراً — بما فيها المخفية عن ExoPlayer
        // بهامش الأمان أعلاه — حتى تكون جاهزة بالكاش قبل ما تُكشَف له
        // بتحديث لاحق للقائمة، بدل ما ينتظرها لحظة الطلب.
        _prefetchNearLiveEdge(newSequence);
      }
    }
    return out.toString();
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
    if (_segmentCache.containsKey(url) ||
        _prefetching.contains(url) ||
        _prefetchQueue.contains(url)) {
      return;
    }
    // نحجز فوراً (قبل حتى ما يبدأ الجلب الفعلي) حتى استدعاء متكرر لنفس
    // الرابط أثناء انتظاره بالطابور لا يُضيفه مرتين.
    _prefetching.add(url);
    _prefetchQueue.add(url);
    _pumpPrefetchQueue();
  }

  void _pumpPrefetchQueue() {
    while (_activePrefetches < _maxConcurrentPrefetch &&
        _prefetchQueue.isNotEmpty) {
      final url = _prefetchQueue.removeAt(0);
      _activePrefetches++;
      unawaited(() async {
        try {
          final bytes = await _fetchSegmentWithRetry(url);
          if (bytes != null) _cacheSegment(url, bytes);
        } finally {
          _prefetching.remove(url);
          _activePrefetches--;
          _pumpPrefetchQueue();
        }
      }());
    }
  }

  Future<void> _handleSegment(HttpRequest request, String originalUrl) async {
    var bytes = _segmentCache[originalUrl];
    if (bytes == null) {
      bytes = await _fetchSegmentWithRetry(originalUrl);
      if (bytes != null) _cacheSegment(originalUrl, bytes);
    }
    if (bytes == null) {
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

  Future<List<int>?> _fetchSegmentWithRetry(String url) async {
    final client = _client;
    if (client == null) return null;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 200 * attempt * attempt));
      }
      try {
        final resp = await client
            .get(Uri.parse(url), headers: _upstreamHeaders)
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return resp.bodyBytes;
        }
        _log('HLS_PROXY_SEGMENT_HTTP_ERROR',
            'attempt=$attempt status=${resp.statusCode}');
      } catch (e) {
        _log('HLS_PROXY_SEGMENT_FETCH_ERROR', 'attempt=$attempt error=$e');
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
    final index = _segmentSequence.indexOf(justRequestedUrl);
    if (index < 0) return;
    for (var i = index + 1; i <= index + _prefetchAhead && i < _segmentSequence.length; i++) {
      _prefetchUrl(_segmentSequence[i]);
    }
  }
}
