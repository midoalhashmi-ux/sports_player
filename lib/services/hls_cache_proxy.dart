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
  static const int _prefetchAhead = 4;

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
    final client = _client;
    if (client == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    final baseUri = Uri.parse(originalUrl);
    String? body;
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

  String _rewritePlaylist(String text, Uri baseUri, int port) {
    final lines = text.split('\n');
    final out = StringBuffer();
    final newSequence = <String>[];
    final uriAttrPattern = RegExp(r'URI="([^"]+)"');

    String proxify(Uri resolved) {
      final isPlaylist = _looksLikePlaylistUri(resolved);
      final encoded = Uri.encodeComponent(resolved.toString());
      if (!isPlaylist) newSequence.add(resolved.toString());
      return 'http://127.0.0.1:$port/${isPlaylist ? 'pl' : 'seg'}?u=$encoded';
    }

    for (final rawLine in lines) {
      final line = rawLine.replaceAll('\r', '');
      if (line.trim().isEmpty) {
        out.writeln();
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
          out.writeln(replaced);
        } else {
          out.writeln(line);
        }
      } else {
        try {
          final resolved = baseUri.resolve(line.trim());
          out.writeln(proxify(resolved));
        } catch (_) {
          out.writeln(line);
        }
      }
    }

    if (newSequence.isNotEmpty) {
      for (final url in newSequence) {
        if (!_segmentSequence.contains(url)) _segmentSequence.add(url);
      }
      if (_segmentSequence.length > 500) {
        _segmentSequence.removeRange(0, _segmentSequence.length - 500);
      }
    }
    return out.toString();
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
      final url = _segmentSequence[i];
      if (_segmentCache.containsKey(url) || _prefetching.contains(url)) continue;
      _prefetching.add(url);
      unawaited(() async {
        try {
          final bytes = await _fetchSegmentWithRetry(url);
          if (bytes != null) _cacheSegment(url, bytes);
        } finally {
          _prefetching.remove(url);
        }
      }());
    }
  }
}
