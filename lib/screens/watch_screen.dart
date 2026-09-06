import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math'; // للـ XOR

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

import '../services/ad_service.dart';
import '../services/channel_source_resolver.dart';
import '../services/stream_models.dart';
import '../services/api_source_resolver.dart';

enum _LoadState { loading, error, ready }

class _ResolvedPublicUrl {
  final String url;
  final Map<String, String> headers;
  const _ResolvedPublicUrl(this.url, this.headers);
}

class _DecodedPayload {
  final String text;
  final String method;
  const _DecodedPayload(this.text, this.method);

  @override
  bool operator ==(Object other) => other is _DecodedPayload && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// One authoritative state machine for a WebView -> Native detection session.
/// It replaces the fragile combination of overlapping booleans/timers.
enum _WebSessionState {
  idle,
  loadingPage,
  webReady,
  interacting,
  discovering,
  candidateTrial,
  nativePlaying,
  nativeFailed,
  drmWebOnly,
  webFallback,
  // A Cloudflare/hCaptcha/reCAPTCHA-style human-verification challenge was
  // detected on the page. We never attempt to solve, click through, or
  // otherwise bypass it — we only detect it, pause automatic discovery, and
  // let the real page (with the real challenge) become visible so the
  // actual person watching can clear it themselves, exactly like in a
  // normal browser.
  humanVerificationRequired,
  stopped,
}

class WatchScreen extends StatefulWidget {
  final String? channelId;
  final String? externalUrl;
  final String? externalUserAgent;

  const WatchScreen({
    super.key,
    this.channelId,
    this.externalUrl,
    this.externalUserAgent,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  WebViewController? _webController;
  bool _isWebSource = false;
  final GlobalKey _videoBoundaryKey = GlobalKey();

  _LoadState _state = _LoadState.loading;
  String _errorMessage = '';
  StreamSession? _session;
  StreamServerOption? _activeServer;
  StreamQuality? _activeQuality;
  Map<String, String>? _headers;
  Map<String, String>? _resolvedStreamHeaders;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Timer? _slowConnectionTimer;
  bool _slowConnectionHint = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100;
  bool _muted = false;
  bool _fullscreen = false;

  bool _locked = false;
  BoxFit _fit = BoxFit.contain;
  String? _seekFeedback;
  Timer? _seekFeedbackTimer;

  // speed / screenshot
  double _playbackSpeed = 1.0;
  bool _savingScreenshot = false;
  bool _showSpeedSheet = false;

  // swipe
  Offset? _swipeStart;
  bool _seekingFromSwipe = false;

  static const _swipeThreshold = 28.0;
  static const _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  // ---------------------------------------------------------------------
  // إصلاح جذري لمشكلة "صوت البث خلف الإعلان"
  static _WatchScreenState? _activeInstance;

  Future<void> _stopBeforeInterstitial() async {
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.setVolume(0);
        await controller.pause();
      } catch (_) {}
    }
  }

  Future<void> _prepareAndStartPlayback() async {
    final previous = _activeInstance;
    if (previous != null && !identical(previous, this)) {
      await previous._stopBeforeInterstitial();
    }
    if (!mounted) return;

    _activeInstance = this;
    WidgetsBinding.instance.addObserver(this);
    _scheduleHide();

    await AdService.instance.showInterstitialThenProceed(() {
      if (mounted && identical(_activeInstance, this)) _startSession();
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_prepareAndStartPlayback());
  }

  // ---------------------- player listener ----------------------
  void _videoListener() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'تعذر تشغيل رابط البث. جرّب مرة أخرى أو غيّر السيرفر.';
      });
      return;
    }
    final wasBuffering = _isBuffering;
    setState(() {
      _isPlaying = value.isPlaying;
      _isBuffering = value.isBuffering;
      _position = value.position;
      _duration = value.duration;
    });
    if (_isBuffering && !wasBuffering) {
      _startSlowConnectionTimer();
    } else if (!_isBuffering && wasBuffering) {
      _cancelSlowConnectionTimer();
    }
  }

  void _startSlowConnectionTimer() {
    _cancelSlowConnectionTimer();
    _slowConnectionTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _isBuffering) {
        setState(() => _slowConnectionHint = true);
      }
    });
  }

  void _cancelSlowConnectionTimer() {
    _slowConnectionTimer?.cancel();
    _slowConnectionTimer = null;
    if (_slowConnectionHint) setState(() => _slowConnectionHint = false);
  }

  // ---------------------- دوال المعالجة المتسلسلة (المضافة حديثاً) ----------------------
  
  /// نقطة الدخول لمعالجة رابط القناة حسب الشجرة المطلوبة.
  Future<StreamSession?> _resolveChannelUrl(String initialUrl) async {
    try {
      // SPA/hash routes (e.g. https://site.example/#/live/some-channel) are
      // client-side-only routes: a normal HTTP GET never sends the URL
      // fragment to the server, so any attempt to "resolve" them as a plain
      // server URL silently loses the actual route and produces a false
      // "تعذر حل رابط البث". This check is intentionally generic (any
      // non-empty URI fragment), not tied to a specific site/domain — the
      // fragment simply cannot be resolved over HTTP for ANY site, so the
      // only architecturally correct move is to hand the complete, unmodified
      // URL to WebView and let the page's own JavaScript route/render it.
      final parsedInitial = Uri.tryParse(initialUrl);
      final isSpaRoute = parsedInitial != null && parsedInitial.fragment.isNotEmpty;
      if (isSpaRoute) {
        return StreamSession.success(
          kind: StreamKind.web,
          isLive: true,
          servers: [
            StreamServerOption(
              label: 'صفحة البث',
              qualities: [StreamQuality(label: 'صفحة البث', url: initialUrl)],
            ),
          ],
        );
      }

      // First use the bounded API resolver so nested JSON/payload endpoints
      // are explored without relying on one specific response shape.
      final apiCandidates = await ApiSourceResolver.resolve(
        initialUrl,
        headers: _headers,
        maxDepth: 3,
      );
      for (final candidate in apiCandidates.take(5)) {
        if (!_isDirectPlayable(candidate.url)) continue;
        _resolvedStreamHeaders = candidate.headers;
        final lower = candidate.url.toLowerCase();
        final kind = lower.contains('.m3u8') ? StreamKind.hls
            : lower.contains('.mpd') ? StreamKind.dash
            : StreamKind.progressive;
        // video_player_android (ExoPlayer) has supported DASH natively since
        // well before the version pinned in pubspec.yaml, so DASH candidates
        // are played the same as HLS/MP4 — see _playServerQuality's
        // formatHint, which is what actually tells ExoPlayer to use its DASH
        // extractor instead of guessing from the URL alone.
        return StreamSession.success(
          kind: kind,
          isLive: true,
          servers: [
            StreamServerOption(
              label: 'المصدر المُستخرج تلقائياً',
              qualities: [StreamQuality(label: 'تلقائي', url: candidate.url)],
            ),
          ],
        );
      }

      final resolvedUrl = await _resolveStreamUrl(initialUrl);
      if (resolvedUrl == null) {
        return StreamSession.failure('تعذر حل رابط البث.');
      }

      final lower = resolvedUrl.toLowerCase();
      final isHls = lower.contains('.m3u8') || lower.contains('m3u8');
      final isDash = lower.contains('.mpd');
      final isProgressive = lower.contains('.mp4') || lower.contains('.webm') || lower.contains('.mov');
      final isWeb = !(isHls || isDash || isProgressive);

      StreamKind kind;
      if (isHls) kind = StreamKind.hls;
      else if (isDash) kind = StreamKind.dash;
      else if (isProgressive) kind = StreamKind.progressive;
      else kind = StreamKind.web;

      return StreamSession.success(
        kind: kind,
        isLive: true,
        servers: [
          StreamServerOption(
            label: 'المصدر المُستخرج',
            qualities: [StreamQuality(label: 'تلقائي', url: resolvedUrl)],
          ),
        ],
      );
    } catch (e) {
      return StreamSession.failure(e.toString());
    }
  }

  /// Universal public-source resolver.
  /// It follows redirects explicitly, decodes common payload wrappers, and
  /// extracts playable URLs without attempting to bypass DRM/authentication.
  Future<String?> _resolveStreamUrl(String url, {int maxDepth = 8}) async {
    final visited = <String>{};
    var currentUrl = url.trim();
    var depth = 0;

    while (currentUrl.isNotEmpty && depth++ < maxDepth) {
      final normalized = _normalizeCandidate(currentUrl);
      if (!visited.add(normalized)) return null;

      final result = await _fetchAndAnalyzePublicUrl(currentUrl);
      if (result == null) return null;
      if (result.url == currentUrl || _isDirectPlayable(result.url)) {
        _resolvedStreamHeaders = result.headers.isEmpty ? _resolvedStreamHeaders : result.headers;
        return result.url;
      }
      currentUrl = result.url;
      if (result.headers.isNotEmpty) _resolvedStreamHeaders = result.headers;
    }
    return null;
  }

  Future<_ResolvedPublicUrl?> _fetchAndAnalyzePublicUrl(String currentUrl) async {
    final uri = Uri.tryParse(currentUrl);
    if (uri == null || !uri.hasScheme) return null;

    final headers = <String, String>{
      'accept': 'application/json, text/plain, */*',
      'accept-encoding': 'gzip',
      'user-agent': _headers?['user-agent'] ??
          'okhttp/4.12.0',
      ...?_headers,
    };

    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..maxRedirects = 0;
      request.headers.addAll(headers);
      final streamed = await client.send(request).timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';

      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) return null;
        final next = uri.resolve(location).toString();
        return _ResolvedPublicUrl(next, headers);
      }

      if (response.statusCode < 200 || response.statusCode >= 400) return null;

      final responseHeaders = <String, String>{...headers};
      final body = response.body;

      if (contentType.contains('mpegurl') || contentType.contains('dash+xml') ||
          _isDirectPlayable(currentUrl) || _containsMediaMarker(body)) {
        return _ResolvedPublicUrl(currentUrl, responseHeaders);
      }

      final candidates = <_DecodedPayload>{};
      _collectPayloadCandidates(body, candidates, currentUrl: currentUrl);

      for (final candidate in candidates) {
        final direct = _extractBestUrl(candidate.text, currentUrl);
        if (direct != null) {
          final resolved = _resolveRelativeUrl(direct, currentUrl);
          if (_isDirectPlayable(resolved)) {
            return _ResolvedPublicUrl(resolved, responseHeaders);
          }
          if (resolved.startsWith('http')) {
            return _ResolvedPublicUrl(resolved, responseHeaders);
          }
        }
      }

      return _ResolvedPublicUrl(currentUrl, responseHeaders);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  void _collectPayloadCandidates(
    String input,
    Set<_DecodedPayload> out, {
    required String currentUrl,
    int depth = 0,
  }) {
    if (depth > 4 || input.trim().isEmpty) return;
    final normalized = input.trim();
    final key = normalized.length > 4096 ? normalized.substring(0, 4096) : normalized;

    void add(String? text, String method) {
      if (text == null) return;
      final value = _normalizeDecodedText(text);
      if (value == null || value.isEmpty || value == normalized) return;
      if (_isUsefulDecodedPayload(value)) {
        out.add(_DecodedPayload(value, method));
        if (depth < 4) _collectPayloadCandidates(value, out, currentUrl: currentUrl, depth: depth + 1);
      }
    }

    // Percent encoding / JSON string wrappers.
    try { add(Uri.decodeFull(normalized), 'percent'); } catch (_) {}
    try {
      if (normalized.startsWith('"') && normalized.endsWith('"')) {
        final decoded = jsonDecode(normalized);
        if (decoded is String) add(decoded, 'json-string');
      }
    } catch (_) {}

    // Base64 and Base64URL. We decode to bytes first so compressed payloads
    // can be recognized before UTF-8 conversion.
    for (final bytes in _base64BytesCandidates(normalized)) {
      add(_decodeEncodedBytesToText(bytes), 'base64');
      try { add(utf8.decode(gzip.decode(bytes)), 'base64+gzip'); } catch (_) {}
      try { add(utf8.decode(ZLibCodec().decode(bytes)), 'base64+zlib'); } catch (_) {}
    }

    // Hex wrapper.
    final hexBytes = _hexBytes(normalized);
    if (hexBytes != null) add(_decodeEncodedBytesToText(hexBytes), 'hex');

    // XOR is intentionally conservative: use an explicit key supplied by
    // the caller/header, not blind cracking of unknown encryption.
    final configuredKey = _headers?['x-xor-key'] ?? _headers?['xor-key'];
    if (configuredKey != null && configuredKey.isNotEmpty) {
      add(_xorBytesToText(utf8.encode(normalized), utf8.encode(configuredKey)), 'xor-key');
      for (final bytes in _base64BytesCandidates(normalized)) {
        add(_xorBytesToText(bytes, utf8.encode(configuredKey)), 'base64+xor-key');
      }
    }

    // Keep the original body as a candidate when it already contains a URL,
    // JSON, HTML, or an HLS marker.
    if (_isUsefulDecodedPayload(key)) out.add(_DecodedPayload(normalized, 'raw'));
  }

  List<List<int>> _base64BytesCandidates(String input) {
    final compact = input.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 12 || compact.length % 4 == 1) return const [];
    if (!RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(compact)) return const [];
    final normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
    try {
      final bytes = base64Decode(padded);
      if (bytes.length < 4) return const [];
      return [bytes];
    } catch (_) {
      return const [];
    }
  }

  List<int>? _hexBytes(String input) {
    final compact = input.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 8 || compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact)) return null;
    try {
      return [for (var i = 0; i < compact.length; i += 2) int.parse(compact.substring(i, i + 2), radix: 16)];
    } catch (_) {
      return null;
    }
  }

  String? _decodeEncodedBytesToText(List<int> bytes) {
    try {
      return _normalizeDecodedText(utf8.decode(bytes, allowMalformed: false));
    } catch (_) {
      return null;
    }
  }

  String? _xorBytesToText(List<int> bytes, List<int> key) {
    if (key.isEmpty || bytes.isEmpty) return null;
    try {
      final decoded = List<int>.generate(bytes.length, (i) => bytes[i] ^ key[i % key.length]);
      return _normalizeDecodedText(utf8.decode(decoded, allowMalformed: false));
    } catch (_) {
      return null;
    }
  }

  String? _normalizeDecodedText(String text) {
    var value = text.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is String) value = decoded.trim();
      } catch (_) {}
    }
    return value;
  }

  bool _isUsefulDecodedPayload(String text) {
    final lower = text.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://') ||
        _looksLikeJson(text) || lower.contains('.m3u8') || lower.contains('.mpd') ||
        lower.contains('#extm3u') || lower.contains('"url"') ||
        lower.contains('"stream"') || lower.contains('"source"') ||
        lower.contains('<video') || lower.contains('<iframe');
  }

  bool _containsMediaMarker(String text) {
    final lower = text.toLowerCase();
    return lower.contains('#extm3u') || lower.contains('.m3u8') ||
        lower.contains('.mpd') || lower.contains('<video');
  }

  String? _extractBestUrl(String text, String baseUrl) {
    dynamic parsed;
    try { parsed = jsonDecode(text); } catch (_) {}
    final fromJson = _extractUrlDeep(parsed, baseUrl);
    if (fromJson != null) return fromJson;

    final regex = RegExp(r"""https?://[^\s"'<>\)\]\}]+""", caseSensitive: false);
    final matches = regex.allMatches(text);
    String? best;
    var bestScore = -999999;
    for (final match in matches) {
      var candidate = match.group(0)?.trim() ?? '';
      candidate = candidate.replaceAll(RegExp(r"""["'<>),;]+$"""), '');
      if (candidate.isEmpty) continue;
      final score = _scoreDetectedSource(candidate);
      if (score > bestScore) { best = candidate; bestScore = score; }
    }
    return best;
  }

  String? _extractUrlDeep(dynamic value, String baseUrl) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.startsWith('/')) {
        return _resolveRelativeUrl(trimmed, baseUrl);
      }
      return null;
    }
    if (value is Map) {
      final preferred = ['url','uri','link','src','source','stream','streamUrl','playUrl','play','hls','m3u8','manifest','playlist','file','video','media','redirect','location','endpoint','data','result','payload'];
      for (final key in preferred) {
        if (value.containsKey(key)) {
          final found = _extractUrlDeep(value[key], baseUrl);
          if (found != null) return found;
        }
      }
      for (final entry in value.entries) {
        final found = _extractUrlDeep(entry.value, baseUrl);
        if (found != null) return found;
      }
    }
    if (value is List) {
      for (final item in value) {
        final found = _extractUrlDeep(item, baseUrl);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// استخراج رابط من كائن JSON (يبحث في الحقول الشائعة).
  String? _extractUrlFromJson(Map<String, dynamic> json) {
    final candidates = ['url', 'link', 'src', 'source', 'playlist', 'stream', 'hls', 'dash', 'progressive', 'video', 'file', 'play', 'watch'];
    for (final key in candidates) {
      if (json.containsKey(key) && json[key] is String) {
        final val = json[key].toString().trim();
        if (val.isNotEmpty && (val.startsWith('http') || val.startsWith('/'))) {
          return val;
        }
      }
    }
    // البحث في الحقول المتداخلة
    for (final key in ['data', 'result', 'response', 'body']) {
      if (json.containsKey(key) && json[key] is Map<String, dynamic>) {
        final nested = _extractUrlFromJson(json[key] as Map<String, dynamic>);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  /// استخراج رابط من HTML (يبحث عن video, source, iframe).
  String? _extractUrlFromHtml(String html) {
    final regex = RegExp(r'(?:src|data-src|href)\s*=\s*"([^"]+)"', caseSensitive: false);
    final matches = regex.allMatches(html);
    for (final match in matches) {
      final url = match.group(1);
      if (url != null && url.isNotEmpty && (url.startsWith('http') || url.startsWith('/'))) {
        if (url.contains('.m3u8') || url.contains('.mp4') || url.contains('.webm') || url.contains('.mpd')) {
          return url;
        }
      }
    }
    // البحث عن روابط تشغيلية في النص
    final fallbackRegex = RegExp(r"""https?://[^\s<>"'\)]+(?:\.m3u8|\.mpd|\.mp4|\.webm|\.m4v|/live/|/stream/)""", caseSensitive: false);
    final fallbackMatch = fallbackRegex.firstMatch(html);
    if (fallbackMatch != null) {
      return fallbackMatch.group(0);
    }
    return null;
  }

  /// تحويل الرابط النسبي إلى مطلق.
  String _resolveRelativeUrl(String url, String baseUrl) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.isAbsolute) return url;
    final base = Uri.parse(baseUrl);
    return base.resolveUri(uri).toString();
  }

  /// التحقق من أن الرابط قابل للتشغيل مباشرة.
  bool _isDirectPlayable(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('.mpd') ||
        lower.contains('.mp4') || lower.contains('.webm') ||
        lower.contains('.m4v') || lower.contains('.mov');
  }

  /// محاولة تحليل JSON مع تجاهل الأخطاء.
  dynamic _tryParseJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeJson(String text) {
    final trimmed = text.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  // ---------------------- web source (بقيت كما هي) ----------------------
  String? _webSourceOrigin;
  Timer? _webDetectorTimer;
  _WebSessionState _webSessionState = _WebSessionState.idle;
  int _webSessionGeneration = 0;
  bool _webDetectionInFlight = false;
  int _webNativeAttempts = 0;
  static const int _webMaxNativeAttempts = 2;
  DateTime? _webLastNativeTrialAt;
  final Set<String> _webSeenSources = <String>{};
  final Set<String> _webFailedNativeSources = <String>{};
  final Map<String, int> _webCandidateEvidence = <String, int>{};
  final Map<String, String> _webCandidateLastReason = <String, String>{};
  Map<String, String>? _webContextHeaders;
  bool _webDrmDetected = false;
  String? _webDrmSystem;
  int _webInteractionAttempts = 0;
  static const int _webMaxInteractionAttempts = 3;
  DateTime? _webLastInteractionAt;
  Timer? _webStartupTimeoutTimer;
  bool _webPlaybackReady = false;
  bool _webPlayerFocusApplied = false;
  String? _webOriginalUrl;
  DateTime? _webStartupDeadline;
  DateTime? _webStartupHardDeadline;
  Timer? _webPromotionFallbackTimer;
  bool _webIframePromotionInFlight = false;
  bool _webPromotedPlayerMode = false;
  int _webIframePromotionAttempts = 0;
  String? _webLastPromotedIframeUrl;
  int _webMediaEvidenceScore = 0;
  int _webMediaResourceHits = 0;
  DateTime? _webLastMediaEvidenceAt;
  // Set once the channel's own page has finished loading successfully. Any
  // *main-frame* navigation to a different host after that point is not
  // normal player behaviour (players resolve their stream via background
  // requests/iframes, not by replacing the whole page) — it is the "forced
  // redirect" pattern ad/popup scripts use to hijack the page entirely (fake
  // prize pages, app-store redirects, etc.), so it gets blocked to keep the
  // original channel page intact.
  bool _webInitialLoadCompleted = false;
  // Mirrors _webDrmDetected's pattern: a flag + a dedicated state, never an
  // attempt to defeat the check itself.
  bool _webHumanVerificationDetected = false;
  bool _webVerificationCheckInFlight = false;

  void _setWebSessionState(_WebSessionState next) {
    if (_webSessionState == next) return;
    _webSessionState = next;
  }

  bool _webSessionIsActive(int generation) =>
      mounted && generation == _webSessionGeneration &&
      _webSessionState != _WebSessionState.stopped;

  String _normalizeCandidate(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return url.trim();
    return uri.replace(fragment: '').toString();
  }

  bool _canTrialNative(String source) {
    if (_webDrmDetected) return false;
    if (_webNativeAttempts >= _webMaxNativeAttempts) return false;
    if (_webFailedNativeSources.contains(source)) return false;
    if (_webSessionState == _WebSessionState.candidateTrial ||
        _webSessionState == _WebSessionState.nativePlaying) return false;
    final last = _webLastNativeTrialAt;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 2)) {
      return false;
    }
    return true;
  }

  bool _isAllowedWebNavigation(String target) {
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.hasScheme) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return !RegExp(
      r'(doubleclick|googlesyndication|googleadservices|adservice|adnxs|popads|popcash|propellerads|onclick|exoclick|juicyads|trafficjunky|adsterra|outbrain|taboola|mgid|criteo|scorecardresearch|popup|popunder|interstitial|clickunder)',
      caseSensitive: false,
    ).hasMatch(host);
  }

  void _handleWebIntelligenceMessage(WebViewController controller, Map<dynamic, dynamic> decoded) {
    final type = decoded['type']?.toString() ?? '';
    if (type == 'drm_detected') {
      if (!mounted) return;
      setState(() {
        _webDrmDetected = true;
        _webDrmSystem = decoded['system']?.toString();
      });
      _webDetectorTimer?.cancel();
      _setWebSessionState(_WebSessionState.drmWebOnly);
      return;
    }
    if (type == 'media_resource') {
      _webMediaResourceHits++;
      _webMediaEvidenceScore = (_webMediaEvidenceScore + 12).clamp(0, 100).toInt();
      _webLastMediaEvidenceAt = DateTime.now();
      _extendWebStartupDeadline(const Duration(seconds: 5));
      return;
    }
    if (type != 'iframe_candidate') return;
    final rawUrl = decoded['url']?.toString().trim() ?? '';
    final score = int.tryParse(decoded['score']?.toString() ?? '') ?? 0;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    if (rawUrl == _webLastPromotedIframeUrl || _webIframePromotionInFlight || _webIframePromotionAttempts >= 2) return;
    if (_webPlaybackReady || _webDrmDetected) return;
    final shouldPromote = score >= 88 || (_webInteractionAttempts > 0 && score >= 70);
    if (!shouldPromote) return;
    unawaited(_promoteIframeToPlayerDocument(controller, rawUrl, score));
  }

  Future<void> _promoteIframeToPlayerDocument(
      WebViewController controller, String iframeUrl, int score) async {
    if (!mounted || _webIframePromotionInFlight || _webIframePromotionAttempts >= 2 || _webPlaybackReady || _webDrmDetected) return;
    _webIframePromotionInFlight = true;
    _webIframePromotionAttempts++;
    _webLastPromotedIframeUrl = iframeUrl;
    _extendWebStartupDeadline(const Duration(seconds: 20));
    _webPromotedPlayerMode = true;
    _setWebSessionState(_WebSessionState.discovering);
    final parentUrl = _webOriginalUrl;
    final parentHeaders = <String, String>{..._effectiveStreamHeaders()};
    if (parentUrl != null && parentUrl.startsWith('http')) parentHeaders['referer'] = parentUrl;
    try {
      _webSourceOrigin = Uri.parse(iframeUrl).host;
      _webPromotionFallbackTimer?.cancel();
      _webPromotionFallbackTimer = Timer(const Duration(seconds: 18), () async {
        if (!mounted || _webPlaybackReady || !_webPromotedPlayerMode) return;
        final current = _webController;
        if (current == null) return;
        final proof = await _webPlaybackSentinel(current);
        if (proof || _webMediaEvidenceScore >= 60) return;
        if (_webIframePromotionAttempts < 2 && parentUrl != null && parentUrl.isNotEmpty) {
          _webPromotedPlayerMode = false;
          _webSourceOrigin = Uri.tryParse(parentUrl)?.host;
          try {
            await current.loadRequest(Uri.parse(parentUrl), headers: _effectiveStreamHeaders());
          } catch (_) {}
        }
      });
      await controller.loadRequest(Uri.parse(iframeUrl), headers: parentHeaders);
    } catch (_) {
      _webPromotedPlayerMode = false;
    } finally {
      _webIframePromotionInFlight = false;
    }
  }

  Future<void> _installWebProtection(WebViewController controller) async {
    await controller.runJavaScript(r'''(() => {
      try {
        if (window.__sportsPlayerProtectionInstalled) return;
        window.__sportsPlayerProtectionInstalled = true;
        const blocked = (url) => {
          try {
            const u = new URL(url, location.href);
            const h = (u.hostname || '').toLowerCase();
            const p = (u.pathname || '').toLowerCase();
            return /(doubleclick|googlesyndication|googleadservices|adservice|adnxs|popads|popcash|propellerads|onclick|exoclick|juicyads|trafficjunky|adsterra|outbrain|taboola|mgid|criteo|scorecardresearch)/i.test(h) ||
              /(popup|popunder|clickunder|interstitial|advertisement|ads?\b)/i.test(p);
          } catch (_) { return false; }
        };
        const report = (payload) => {
          try {
            if (window.SportsPlayerSource && window.SportsPlayerSource.postMessage) {
              window.SportsPlayerSource.postMessage(JSON.stringify(payload));
            }
          } catch (_) {}
        };
        const addCandidate = (value) => {
          try {
            if (!value || typeof value !== 'string') return;
            const v = value.trim();
            if (!/^https?:\/\//i.test(v)) return;
            window.__sportsPlayerMediaCandidates = window.__sportsPlayerMediaCandidates || [];
            if (window.__sportsPlayerMediaCandidates.indexOf(v) === -1) {
              window.__sportsPlayerMediaCandidates.push(v);
            }
          } catch (_) {}
        };
        window.open = function(url) {
          if (!url || blocked(url)) return null;
          // Never let a page-created secondary window steal the playback session.
          return null;
        };
        // Some ad-laden pages spam a native "Allow notifications?" prompt on
        // load or on first tap purely to farm push-subscriptions for later
        // spam/ad campaigns — it has nothing to do with playing the channel.
        // Answer it silently as denied instead of letting it interrupt the
        // viewer or, on some WebView builds, open a system permission sheet.
        try {
          if (window.Notification) {
            const deniedPromise = () => Promise.resolve('denied');
            try {
              Object.defineProperty(Notification, 'permission', { get: () => 'denied', configurable: true });
            } catch (_) {}
            Notification.requestPermission = function(cb) {
              if (typeof cb === 'function') { try { cb('denied'); } catch (_) {} }
              return deniedPromise();
            };
            const NoopNotification = function() { /* swallow: never actually shown */ };
            NoopNotification.permission = 'denied';
            NoopNotification.requestPermission = Notification.requestPermission;
            window.Notification = NoopNotification;
          }
        } catch (_) {}
        const markUserInteraction = (el) => {
          try {
            const r = el && el.getBoundingClientRect ? el.getBoundingClientRect() : null;
            window.__sportsPlayerLastClick = {
              at: Date.now(),
              x: r ? r.left + r.width / 2 : 0,
              y: r ? r.top + r.height / 2 : 0,
              text: ((el && (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title'))) || '').slice(0,120)
            };
          } catch (_) {}
        };
        document.addEventListener('click', (e) => {
          let el = e.target;
          if (el && el.nodeType === 3) el = el.parentElement;
          markUserInteraction(el);
          let link = el;
          while (link && link.tagName !== 'A') link = link.parentElement;
          if (!link) return;
          const href = link.getAttribute('href') || '';
          const target = (link.getAttribute('target') || '').toLowerCase();
          if (target === '_blank' || target === '_new' || blocked(href)) {
            e.preventDefault(); e.stopPropagation();
          }
        }, true);
        const style = document.createElement('style');
        style.id = 'sports-player-ad-cleanup';
        style.textContent = `[id*=\"popup\" i],[class*=\"popup\" i],[id*=\"popunder\" i],[class*=\"popunder\" i],[id*=\"advert\" i],[class*=\"advert\" i],[id*=\"adsbox\" i],[class*=\"adsbox\" i],[class*=\"overlay-ad\" i],[class*=\"interstitial\" i]{display:none!important;visibility:hidden!important;}`;
        (document.head || document.documentElement).appendChild(style);

        // Universal player intelligence: iframe URLs can appear/change only after Play.
        const iframeKey = (f) => { try { return `${f.src || ''}|${f.id || ''}|${f.className || ''}`; } catch (_) { return ''; } };
        const iframeSeen = new Set();
        const inspectIframes = () => {
          try {
            document.querySelectorAll('iframe').forEach((f) => {
              const src = (f.src || f.getAttribute('src') || '').trim();
              if (!/^https?:\/\//i.test(src)) return;
              const r = f.getBoundingClientRect();
              const st = getComputedStyle(f);
              if (r.width < 180 || r.height < 100 || st.display === 'none' || st.visibility === 'hidden') return;
              const text = `${src} ${f.id || ''} ${f.className || ''}`.toLowerCase();
              if (/(doubleclick|googlesyndication|adservice|adnxs|popads|popcash|propellerads|exoclick|juicyads|trafficjunky|adsterra|popup|popunder|clickunder|interstitial)/i.test(text)) return;
              let score = 10;
              if (r.width >= 320 && r.height >= 180) score += 25;
              else if (r.width >= 250 && r.height >= 140) score += 15;
              if (r.bottom >= 0 && r.top <= innerHeight) score += 15;
              if (/(embed|shell|player|video|watch|stream|play|live)/i.test(text)) score += 30;
              if (/(player|video|stream|embed)/i.test(`${f.id || ''} ${f.className || ''}`)) score += 20;
              try { if (new URL(src, location.href).hostname !== location.hostname) score += 10; } catch (_) {}
              const key = iframeKey(f);
              if (!key || iframeSeen.has(key)) return;
              iframeSeen.add(key);
              report({type:'iframe_candidate', url:src, score, width:Math.round(r.width), height:Math.round(r.height)});
            });
          } catch (_) {}
        };
        inspectIframes();
        try { new MutationObserver(() => inspectIframes()).observe(document.documentElement || document, {subtree:true, childList:true, attributes:true, attributeFilter:['src','id','class','style']}); } catch (_) {}
        try { setInterval(inspectIframes, 1200); } catch (_) {}

        const mediaResourceSeen = new Set();
        const mediaResourceLike = (url) => {
          try {
            const u = new URL(url, location.href);
            const h = `${u.hostname} ${u.pathname} ${u.search}`.toLowerCase();
            if (/(doubleclick|googlesyndication|google-analytics|mc\.yandex|scorecardresearch|adservice|ads\b|beacon|telemetry|metrics|pixel|collect)/i.test(h)) return false;
            return /\.(m3u8|mpd|mp4|m4v|webm|mov|m4s|ts)(?:$|[?#])/i.test(h) || /(manifest|playlist|master|stream|video|media|segment|seg-|chunk|hls2|dash|\/v\/)/i.test(h);
          } catch (_) { return false; }
        };
        const reportMediaResources = () => {
          try { performance.getEntriesByType('resource').forEach((e) => { const name = e && e.name ? String(e.name) : ''; if (mediaResourceLike(name)) report({type:'media_resource', url:name}); }); } catch (_) {}
        };
        reportMediaResources();
        try { setInterval(reportMediaResources, 1800); } catch (_) {}

        try {
          const originalRequestMediaKeySystemAccess = navigator.requestMediaKeySystemAccess;
          if (typeof originalRequestMediaKeySystemAccess === 'function' && !navigator.__sportsPlayerEmeHooked) {
            navigator.__sportsPlayerEmeHooked = true;
            navigator.requestMediaKeySystemAccess = function(keySystem, supportedConfigurations) {
              report({type:'drm_detected', system:String(keySystem || 'unknown')});
              return originalRequestMediaKeySystemAccess.apply(this, arguments);
            };
          }
        } catch (_) {}

        try {
          if (window.fetch && !window.__sportsPlayerFetchHooked) {
            window.__sportsPlayerFetchHooked = true;
            const originalFetch = window.fetch;
            window.fetch = function(input, init) {
              try { addCandidate(typeof input === 'string' ? input : (input && input.url)); } catch (_) {}
              return originalFetch.apply(this, arguments).then((response) => {
                try { addCandidate(response && response.url); } catch (_) {}
                return response;
              });
            };
          }
        } catch (_) {}
        try {
          if (window.XMLHttpRequest && !window.__sportsPlayerXhrHooked) {
            window.__sportsPlayerXhrHooked = true;
            const OriginalXHR = window.XMLHttpRequest;
            const originalOpen = OriginalXHR.prototype.open;
            OriginalXHR.prototype.open = function(method, url) {
              try { addCandidate(url); } catch (_) {}
              return originalOpen.apply(this, arguments);
            };
          }
        } catch (_) {}
      } catch (_) {}
    })();''');
  }

  Future<List<String>> _detectPublicMediaSources(WebViewController controller) async {
    try {
      const js = r"""(() => {
        const out = new Set();
        const add = (value) => {
          if (!value || typeof value !== 'string') return;
          const v = value.trim();
          if (!/^https?:\/\//i.test(v)) return;
          const l = v.toLowerCase();
          if (/\.(m3u8|mpd|mp4|m4v|webm|mov)(?:$|[?#])/i.test(v) ||
              /(?:m3u8|manifest|playlist|master|stream|live|hls)(?:[?&=\/]|$)/i.test(l)) out.add(v);
        };
        document.querySelectorAll('video').forEach(v => {
          add(v.currentSrc); add(v.src);
          v.querySelectorAll('source').forEach(s => add(s.src));
        });
        document.querySelectorAll('source').forEach(s => add(s.src));
        document.querySelectorAll('iframe').forEach(f => add(f.src));
        try { performance.getEntriesByType('resource').forEach(e => add(e.name)); } catch (_) {}
        try {
          const html = document.documentElement ? document.documentElement.innerHTML : '';
          const urls = html.match(/https?:\/\/[^\s\"'<>]+/gi) || [];
          urls.forEach(add);
        } catch (_) {}
        try { (window.__sportsPlayerMediaCandidates || []).forEach(add); } catch (_) {}
        return JSON.stringify(Array.from(out));
      })();""";
      final result = await controller.runJavaScriptReturningResult(js);
      if (result is! String) return const [];
      var text = result;
      if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
        text = text.substring(1, text.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
      }
      final matches = RegExp(r'https?://[^"\s\]]+').allMatches(text);
      return matches.map((m) => m.group(0)!).toList();
    } catch (_) {
      return const [];
    }
  }

  int _scoreDetectedSource(String url) {
    final lower = url.toLowerCase();
    var score = 0;
    if (lower.contains('.m3u8')) score += 100;
    else if (lower.contains('.mpd')) score += 85;
    else if (lower.contains('.mp4') || lower.contains('.m4v') || lower.contains('.webm') || lower.contains('.mov')) score += 55;
    if (lower.contains('live')) score += 35;
    if (lower.contains('stream')) score += 25;
    if (lower.contains('channel')) score += 20;
    if (lower.contains('master')) score += 15;
    if (lower.contains('playlist')) score += 10;
    if (lower.contains('segment') || lower.contains('.ts')) score -= 100;
    if (lower.contains('ads') || lower.contains('advert') || lower.contains('vast') || lower.contains('doubleclick')) score -= 100;
    return score;
  }

  bool _looksLikeHls(String url) => RegExp(r'\.m3u8(?:$|[?#])', caseSensitive: false).hasMatch(url);
  bool _looksLikeProgressiveVideo(String url) => RegExp(r'\.(mp4|m4v|webm|mov)(?:$|[?#])', caseSensitive: false).hasMatch(url);

  Future<bool> _validatePublicMediaSource(String url) async {
    try {
      final uri = Uri.parse(url);
      final headers = <String, String>{
        'user-agent': _headers?['user-agent'] ?? 'Mozilla/5.0 (Android) AppleWebKit/537.36 Chrome/131 Mobile Safari/537.36',
        'accept': '*/*',
        ...?_webContextHeaders,
        ...?_resolvedStreamHeaders,
      };
      if (_looksLikeHls(url)) {
        final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) return false;
        final body = response.body;
        return RegExp(r'#EXTM3U', caseSensitive: false).hasMatch(body) ||
            RegExp(r'#EXT-X-(STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE)', caseSensitive: false).hasMatch(body);
      }
      if (_looksLikeProgressiveVideo(url)) {
        try {
          final response = await http.head(uri, headers: headers).timeout(const Duration(seconds: 6));
          if (response.statusCode >= 200 && response.statusCode < 400) {
            final type = (response.headers['content-type'] ?? '').toLowerCase();
            if (type.isEmpty || type.startsWith('video/') || type.contains('octet-stream')) return true;
          }
        } catch (_) {}
        // Some CDNs reject HEAD (405) while allowing normal media requests.
        try {
          final rangeHeaders = <String, String>{...headers, 'range': 'bytes=0-1023'};
          final response = await http.get(uri, headers: rangeHeaders).timeout(const Duration(seconds: 8));
          if (response.statusCode >= 200 && response.statusCode < 400) {
            final type = (response.headers['content-type'] ?? '').toLowerCase();
            return type.isEmpty || type.startsWith('video/') || type.contains('octet-stream') ||
                response.headers.containsKey('content-range');
          }
        } catch (_) {}
        return false;
      }
      // Frameworks sometimes expose signed media URLs without a file extension.
      // Probe the response headers/body rather than requiring .m3u8/.mp4 in the URL.
      try {
        final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 && response.statusCode < 400) {
          final type = (response.headers['content-type'] ?? '').toLowerCase();
          if (type.contains('mpegurl') || type.contains('dash+xml') || type.startsWith('video/')) return true;
          final bodyStart = response.body.length > 4096 ? response.body.substring(0, 4096) : response.body;
          if (RegExp(r'#EXTM3U|#EXT-X-(STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE)', caseSensitive: false).hasMatch(bodyStart)) return true;
        }
      } catch (_) {}
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _captureWebContext(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(r'''(() => JSON.stringify({
        referer: document.referrer || location.href,
        origin: location.origin || '',
        cookie: document.cookie || '',
        userAgent: navigator.userAgent || ''
      }))();''');
      if (result is! String) return;
      var text = result;
      if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
        text = text.substring(1, text.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
      }
      final data = jsonDecode(text);
      if (data is! Map) return;
      final headers = <String, String>{};
      final ua = data['userAgent']?.toString() ?? '';
      final referer = data['referer']?.toString() ?? '';
      final origin = data['origin']?.toString() ?? '';
      final cookie = data['cookie']?.toString() ?? '';
      if (ua.isNotEmpty) headers['user-agent'] = ua;
      if (referer.startsWith('http')) headers['referer'] = referer;
      if (origin.startsWith('http')) headers['origin'] = origin;
      if (cookie.isNotEmpty) headers['cookie'] = cookie;
      if (mounted && headers.isNotEmpty) _webContextHeaders = headers;
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _webPlaybackSnapshot(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(r'''(() => {
        const videos = Array.from(document.querySelectorAll('video'));
        let best = null;
        for (const v of videos) {
          try {
            const r = v.getBoundingClientRect();
            const score = (r.width * r.height) + (v.readyState >= 2 ? 1000000 : 0) + (!v.paused ? 500000 : 0);
            if (!best || score > best.score) best = {v, score};
          } catch (_) {}
        }
        const v = best ? best.v : null;
        let seekable = false;
        if (v) { try { seekable = v.seekable && v.seekable.length > 0 && (v.seekable.end(v.seekable.length - 1) - v.seekable.start(0)) > 1; } catch (_) {} }
        const duration = v && Number.isFinite(v.duration) ? (v.duration || 0) : 0;
        let mediaHits = 0;
        let lastMedia = '';
        try {
          performance.getEntriesByType('resource').forEach((e) => {
            const n = String(e.name || '').toLowerCase();
            if (/\.(m3u8|mpd|mp4|m4v|webm|mov|m4s|ts)(?:$|[?#])/.test(n) || /(manifest|playlist|master|stream|video|media|segment|seg-|chunk|hls2|dash|\/v\/)/.test(n)) {
              if (!/(doubleclick|googlesyndication|google-analytics|mc\.yandex|adservice|beacon|telemetry|metrics|pixel|collect)/.test(n)) { mediaHits++; lastMedia = e.name; }
            }
          });
        } catch (_) {}
        return JSON.stringify({found:!!v, playing:!!(v && !v.paused && v.readyState >= 2), time:Number(v && v.currentTime || 0), duration, seekable, src:v ? (v.currentSrc || v.src || '') : '', mediaHits, lastMedia});
      })();''');
      final text = result is String ? result : result?.toString() ?? '';
      if (text.isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<bool> _webPlaybackSentinel(WebViewController controller) async {
    try {
      final first = await _webPlaybackSnapshot(controller);
      if (first == null) return false;
      final firstHits = (first['mediaHits'] as num?)?.toInt() ?? 0;
      final firstTime = (first['time'] as num?)?.toDouble() ?? 0;
      if (first['playing'] == true) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!mounted || _webDrmDetected) return false;
        final second = await _webPlaybackSnapshot(controller);
        if (second == null || second['playing'] != true) return false;
        final secondTime = (second['time'] as num?)?.toDouble() ?? 0;
        if (secondTime > firstTime + 0.05 || secondTime > 0.3) return true;
      }
      final second = await _webPlaybackSnapshot(controller);
      final secondHits = (second?['mediaHits'] as num?)?.toInt() ?? 0;
      if (secondHits >= firstHits + 2 || secondHits >= 5) {
        _webMediaEvidenceScore = (_webMediaEvidenceScore + 20).clamp(0, 100).toInt();
        return true;
      }
      return _webMediaEvidenceScore >= 70 && _webMediaResourceHits >= 4;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _findBestIframeCandidate(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(r'''(() => {
        const bad = /(doubleclick|googlesyndication|googleadservices|adservice|adnxs|popads|popcash|propellerads|exoclick|juicyads|trafficjunky|adsterra|outbrain|taboola|mgid|criteo|scorecardresearch|popup|popunder|clickunder|interstitial)/i;
        const out = [];
        document.querySelectorAll('iframe').forEach((f) => {
          const src = (f.src || f.getAttribute('src') || '').trim();
          if (!/^https?:\/\//i.test(src) || bad.test(src)) return;
          const r = f.getBoundingClientRect();
          const s = getComputedStyle(f);
          if (r.width < 220 || r.height < 120 || s.display === 'none' || s.visibility === 'hidden') return;
          const text = `${src} ${f.id || ''} ${f.className || ''}`;
          let score = 10;
          if (r.width >= 320 && r.height >= 180) score += 25;
          if (/(embed|shell|player|video|watch|stream|play|live)/i.test(text)) score += 35;
          if (/(player|video|stream|embed)/i.test(`${f.id || ''} ${f.className || ''}`)) score += 20;
          if (r.bottom >= 0 && r.top <= innerHeight) score += 15;
          out.push({src,score,area:r.width*r.height});
        });
        out.sort((a,b) => (b.score-a.score) || (b.area-a.area));
        return JSON.stringify(out[0] || null);
      })();''');
      final text = result is String ? result : result?.toString() ?? '';
      if (text.isEmpty || text == 'null') return null;
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded['src']?.toString();
    } catch (_) {}
    return null;
  }

  Future<bool> _runSmartInteraction(WebViewController controller) async {
    if (_webDrmDetected || _webInteractionAttempts >= _webMaxInteractionAttempts) {
      return false;
    }
    final last = _webLastInteractionAt;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 2)) {
      return false;
    }
    _webInteractionAttempts++;
    _webLastInteractionAt = DateTime.now();
    _setWebSessionState(_WebSessionState.interacting);

    try {
      final result = await controller.runJavaScriptReturningResult(r'''(() => {
        const normalize = (s) => (s || '').toString().trim().replace(/\s+/g, ' ').toLowerCase();
        const blockedText = /(login|sign[ -]?in|subscribe|subscription|purchase|buy|download|advert|ads|privacy|cookie|close|share|facebook|twitter|telegram|whatsapp|notification|allow)/i;
        const playText = /(play|watch|live|watch live|start|start stream|watch now|تشغيل|مشاهدة|بث مباشر|مشاهدة مباشرة|ابدأ|ابدأ البث|شاهد الآن)/i;
        const playerSelector = 'video,iframe,.jwplayer,.jw-wrapper,.video-js,.plyr,.shaka-video-container,[class*="player" i],[id*="player" i]';
        const enabled = (el) => !!el && !el.disabled && el.getAttribute('aria-disabled') !== 'true';
        const labelOf = (el) => normalize([
          el.getAttribute('aria-label'), el.getAttribute('title'), el.innerText,
          el.textContent, el.getAttribute('data-testid'), el.id, el.className,
          el.getAttribute('data-action'), el.getAttribute('data-play')
        ].join(' '));

        // Layer 0: locate the real player even when it starts below the fold.
        let media = Array.from(document.querySelectorAll(playerSelector)).filter((el) => {
          if (!el || !el.isConnected) return false;
          const r = el.getBoundingClientRect();
          return r.width >= 160 && r.height >= 90;
        });
        media.sort((a,b) => {
          const ar=a.getBoundingClientRect(), br=b.getBoundingClientRect();
          return (br.width*br.height)-(ar.width*ar.height);
        });
        const player = media[0] || null;
        if (player) {
          try { player.scrollIntoView({block:'center', inline:'center', behavior:'instant'}); } catch (_) {}
        }

        // Layers 1/2: known player controls and text-labelled controls.
        const candidates = [];
        const seen = new Set();
        const selectors = 'button,[role="button"],a,[aria-label],[title],[onclick],[tabindex],input[type="button"],input[type="submit"],.jw-icon-play,.jw-icon-display,.vjs-big-play-button,.plyr__control--overlaid,.ytp-large-play-button,[data-play],[data-action*="play" i],[class*="play-btn" i],[class*="playbtn" i],[id*="play-btn" i],[id*="playbtn" i]';
        const addCandidate = (el, base) => {
          if (!el || !el.isConnected || !enabled(el)) return;
          const label = labelOf(el);
          if (blockedText.test(label)) return;
          const r = el.getBoundingClientRect();
          if (r.width < 18 || r.height < 18) return;
          const st = getComputedStyle(el);
          if (st.display === 'none' || st.visibility === 'hidden' || st.opacity === '0') return;
          if (r.right < 0 || r.bottom < 0 || r.left > innerWidth || r.top > innerHeight) return;
          let score = base || 0;
          if (playText.test(label)) score += 35;
          if (/play|player|video|watch|live/.test(label)) score += 20;
          if (el.matches && el.matches('.jw-icon-play,.jw-icon-display,.vjs-big-play-button,.plyr__control--overlaid,.ytp-large-play-button,[data-play],[class*="play-btn" i],[class*="playbtn" i],[id*="play-btn" i],[id*="playbtn" i]')) score += 60;
          if (el.hasAttribute('aria-label')) score += 15;
          if (el.hasAttribute('title')) score += 10;
          if (player) {
            const pr = player.getBoundingClientRect();
            const cx=r.left+r.width/2, cy=r.top+r.height/2;
            const px=pr.left+pr.width/2, py=pr.top+pr.height/2;
            const d=Math.hypot(cx-px,cy-py);
            if (d < 120) score += 55;
            else if (d < 250) score += 25;
            if (cx >= pr.left-30 && cx <= pr.right+30 && cy >= pr.top-30 && cy <= pr.bottom+30) score += 35;
          }
          const adAncestor = el.closest('[id*="ad" i],[class*="ad" i],[id*="popup" i],[class*="popup" i],[id*="overlay-ad" i]');
          if (adAncestor) score -= 150;
          const key = `${el.tagName}|${label}|${Math.round(r.left)}|${Math.round(r.top)}`;
          if (!seen.has(key)) { seen.add(key); candidates.push({el,score,label}); }
        };
        document.querySelectorAll(selectors).forEach((el) => addCandidate(el, 0));
        candidates.sort((a,b) => b.score-a.score);
        const best = candidates[0];
        if (best && best.score >= 55) {
          try {
            best.el.scrollIntoView({block:'center', inline:'center', behavior:'instant'});
            best.el.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,view:window}));
            best.el.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,cancelable:true,view:window}));
            best.el.click();
            return JSON.stringify({clicked:true, layer:1, score:best.score, label:best.label.slice(0,160)});
          } catch (_) {}
        }

        // Layer 3: geometric fallback around the player's center. This covers
        // custom icon-only buttons such as the yellow circular button in the
        // supplied screenshot, without clicking arbitrary page links.
        if (player) {
          const pr = player.getBoundingClientRect();
          const cx = pr.left + pr.width/2, cy = pr.top + pr.height/2;
          let el = document.elementFromPoint(cx, cy);
          const chain = [];
          for (let i=0; el && i<6; i++, el=el.parentElement) chain.push(el);
          for (const candidate of chain) {
            const label = labelOf(candidate);
            if (!enabled(candidate) || blockedText.test(label)) continue;
            if (candidate.tagName === 'A' && !playText.test(label)) continue;
            const r=candidate.getBoundingClientRect();
            if (r.width < 24 || r.height < 24 || r.width > pr.width*0.95 || r.height > pr.height*0.95) continue;
            const adAncestor = candidate.closest('[id*="ad" i],[class*="ad" i],[id*="popup" i],[class*="popup" i],[class*="overlay-ad" i]');
            if (adAncestor) continue;
            try {
              candidate.click();
              return JSON.stringify({clicked:true, layer:3, score:40, label:label.slice(0,160)});
            } catch (_) {}
          }
        }

        // Layer 4: HTML5 fallback. The browser still enforces its own gesture,
        // DRM and authentication rules; we do not bypass them.
        const v = document.querySelector('video');
        if (v && typeof v.play === 'function') {
          try {
            const p = v.play();
            if (p && typeof p.catch === 'function') p.catch(() => {});
            return JSON.stringify({clicked:true, layer:4, score:30, label:'video.play()'});
          } catch (_) {}
        }
        return JSON.stringify({clicked:false, reason:'no-safe-play-control'});
      })();''');
      final text = result is String ? result : result?.toString() ?? '';
      if (text.contains('clicked') && text.contains('true')) {
        _extendWebStartupDeadline(const Duration(seconds: 15));
        await Future<void>.delayed(const Duration(milliseconds: 1800));
        if (!mounted || _webDrmDetected) return false;
        final snapshot = await _webPlaybackSnapshot(controller);
        if (snapshot?['playing'] == true) return true;
        final iframe = await _findBestIframeCandidate(controller);
        if (iframe != null) return true;
        return _webMediaResourceHits > 0 || _webMediaEvidenceScore >= 20;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      if (mounted && _webSessionState == _WebSessionState.interacting) {
        _setWebSessionState(_WebSessionState.webReady);
      }
    }
  }

  /// Detect common web-player frameworks and inspect their public player configuration.
  /// This is discovery only; it does not bypass DRM, authentication, or access controls.
  Future<List<String>> _detectPlayerFrameworkSources(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(r'''(() => {
        const out = new Set();
        const add = (value) => {
          if (!value || typeof value !== 'string') return;
          let v = value.trim();
          if (!v) return;
          try { v = new URL(v, location.href).toString(); } catch (_) { return; }
          if (/^https?:\/\//i.test(v)) out.add(v);
        };
        const addDeep = (value, depth=0) => {
          if (depth > 5 || value == null) return;
          if (typeof value === 'string') {
            if (/^https?:\/\//i.test(value.trim()) || /\.(m3u8|mpd|mp4|m4v|webm|mov)(?:$|[?#])/i.test(value)) add(value);
            return;
          }
          if (Array.isArray(value)) { value.slice(0,40).forEach(v => addDeep(v, depth+1)); return; }
          if (typeof value === 'object') {
            Object.keys(value).slice(0,80).forEach(k => {
              const v = value[k];
              if (/^(file|src|source|url|uri|stream|streamUrl|playUrl|hls|dash|mpd|m3u8|playlist|media|sources)$/i.test(k)) addDeep(v, depth+1);
              else if (depth < 2) addDeep(v, depth+1);
            });
          }
        };
        document.querySelectorAll('video,audio').forEach(v => {
          add(v.currentSrc); add(v.src);
          v.querySelectorAll('source').forEach(s => add(s.src || s.getAttribute('src')));
        });
        try {
          if (window.jwplayer) {
            document.querySelectorAll('[id],[class]').forEach(el => {
              const id = el.id || '';
              const cls = typeof el.className === 'string' ? el.className : '';
              if (!/jwplayer|jw-video|jw-wrapper/i.test(id + ' ' + cls)) return;
              try {
                const p = window.jwplayer(id || el);
                if (p) {
                  try { addDeep(p.getPlaylist ? p.getPlaylist() : null); } catch (_) {}
                  try { addDeep(p.getConfig ? p.getConfig() : null); } catch (_) {}
                  try { addDeep(p.getPlaylistItem ? p.getPlaylistItem() : null); } catch (_) {}
                }
              } catch (_) {}
            });
          }
        } catch (_) {}
        try {
          if (window.videojs) {
            document.querySelectorAll('.video-js, video[id]').forEach(el => {
              try { addDeep(window.videojs.getPlayer ? window.videojs.getPlayer(el.id || el) : window.videojs(el.id || el)); } catch (_) {}
            });
          }
        } catch (_) {}
        try {
          if (window.player && typeof window.player === 'object') addDeep(window.player);
          if (window.__INITIAL_STATE__) addDeep(window.__INITIAL_STATE__);
          if (window.__NEXT_DATA__) addDeep(window.__NEXT_DATA__);
          if (window.__NUXT__) addDeep(window.__NUXT__);
        } catch (_) {}
        try {
          document.querySelectorAll('[data-src],[data-url],[data-file],[data-stream],[data-playlist],[data-config],[data-source]').forEach(el => {
            ['data-src','data-url','data-file','data-stream','data-playlist','data-config','data-source'].forEach(a => addDeep(el.getAttribute(a)));
          });
          document.querySelectorAll('script').forEach(script => {
            const text = script.textContent || '';
            if (/jwplayer|videojs|playlist|m3u8|\.mpd|\.mp4|streamUrl|playUrl/i.test(text)) {
              (text.match(/https?:\/\/[^\s"'<>]+/gi) || []).forEach(add);
              (text.match(/['"]([^'"]+\.(?:m3u8|mpd|mp4|m4v|webm|mov)(?:\?[^'"]*)?)['"]/gi) || []).forEach(x => add(x.replace(/^['"]|['"]$/g,'')));
            }
          });
        } catch (_) {}
        return JSON.stringify(Array.from(out));
      })();''');
      final text = result is String ? result : result?.toString() ?? '';
      final matches = RegExp(r'https?://[^"\s\]]+').allMatches(text);
      return matches.map((m) => m.group(0)!).toList();
    } catch (_) {
      return const [];
    }
  }

  /// كشف وجود تحقق بشري معروف (Cloudflare Turnstile / hCaptcha / reCAPTCHA
  /// أو نص عام مثل "Verify you are human") — للكشف فقط، لا محاولة حل أو
  /// تجاوز على الإطلاق. القرار الوحيد المبني على هذا الكشف هو إظهار الصفحة
  /// الحقيقية للمستخدم ليكملها بنفسه.
  Future<bool> _detectHumanVerification(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(r'''(() => {
        try {
          const iframeHosts = /challenges\.cloudflare\.com|hcaptcha\.com|google\.com\/recaptcha|recaptcha\.net/i;
          const hasChallengeIframe = Array.from(document.querySelectorAll('iframe')).some((f) => {
            try { return iframeHosts.test(f.src || ''); } catch (_) { return false; }
          });
          const hasChallengeWidget = !!document.querySelector('.cf-turnstile,#cf-chl-widget,#challenge-form,#challenge-running,.g-recaptcha,.h-captcha');
          const bodyText = ((document.body && document.body.innerText) || '').slice(0, 4000).toLowerCase();
          const hasChallengeText = /verify you are human|checking your browser|attention required|complete the security check|verifying you are human|i'?m not a robot|prove you'?re human/.test(bodyText);
          return JSON.stringify({ detected: !!(hasChallengeIframe || hasChallengeWidget || hasChallengeText) });
        } catch (_) {
          return JSON.stringify({ detected: false });
        }
      })();''');
      final text = result is String ? result : result?.toString() ?? '';
      return text.contains('"detected":true');
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyPlayerFocus(WebViewController controller) async {
    if (_webPlayerFocusApplied) return;
    try {
      final result = await controller.runJavaScriptReturningResult(r'''(() => {
        const visible = (el) => {
          if (!el) return false;
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          return r.width >= 160 && r.height >= 90 && s.display !== 'none' && s.visibility !== 'hidden' && s.opacity !== '0';
        };
        const candidates = Array.from(document.querySelectorAll('video,iframe,.jwplayer,.jw-wrapper,.video-js,.plyr,.shaka-video-container'))
          .filter(visible);
        if (!candidates.length) return JSON.stringify({ok:false});
        const media = candidates.sort((a,b) => {
          const ar=a.getBoundingClientRect(), br=b.getBoundingClientRect();
          return (br.width*br.height)-(ar.width*ar.height);
        })[0];
        let root = media;
        const mediaRect = media.getBoundingClientRect();
        for (let i=0;i<4 && root.parentElement;i++) {
          const p=root.parentElement;
          const r=p.getBoundingClientRect();
          if (r.width >= mediaRect.width*0.9 && r.height >= mediaRect.height*0.9) root=p;
          else break;
        }
        document.querySelectorAll('*').forEach(el => {
          el.setAttribute('data-sports-player-focus-hidden','1');
          el.style.setProperty('visibility','hidden','important');
        });
        const reveal = (el) => {
          if (!el) return;
          el.style.setProperty('visibility','visible','important');
        };
        reveal(document.documentElement);
        reveal(document.body);
        let n=root;
        while(n){ reveal(n); n=n.parentElement; }
        root.querySelectorAll('*').forEach(reveal);
        root.style.setProperty('max-width','100vw','important');
        root.style.setProperty('box-sizing','border-box','important');
        try { root.scrollIntoView({block:'center', inline:'center', behavior:'instant'}); } catch (_) {}
        return JSON.stringify({ok:true});
      })();''');
      if (result is String && result.contains('"ok":true')) {
        _webPlayerFocusApplied = true;
      }
    } catch (_) {}
  }

  Future<void> _showWebPlaybackReady(WebViewController controller) async {
    if (!mounted || _webPlaybackReady) return;
    _webPlaybackReady = true;
    _webStartupTimeoutTimer?.cancel();
    await _applyPlayerFocus(controller);
    if (!mounted) return;
    setState(() {
      _state = _LoadState.ready;
      _isWebSource = true;
      _errorMessage = '';
    });
  }

  void _extendWebStartupDeadline(Duration extension) {
    if (_webStartupDeadline == null || _webStartupHardDeadline == null) return;
    final now = DateTime.now();
    final current = _webStartupDeadline!;
    final proposed = (current.isAfter(now) ? current : now).add(extension);
    final hard = _webStartupHardDeadline!;
    _webStartupDeadline = proposed.isAfter(hard) ? hard : proposed;
  }

  void _startWebStartupTimeout(WebViewController controller, int generation) {
    _webStartupTimeoutTimer?.cancel();
    void arm() {
      if (!mounted || generation != _webSessionGeneration || _webPlaybackReady) return;
      final deadline = _webStartupDeadline ?? DateTime.now().add(const Duration(seconds: 20));
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        final state = _webSessionState;
        // A trial that is still actively proving playback gets one immediate
        // proof check rather than being killed mid-initialization. Genuine
        // progress may extend the deadline, but never beyond 90 seconds.
        if (state == _WebSessionState.candidateTrial) {
          _webStartupTimeoutTimer = Timer(const Duration(milliseconds: 250), arm);
          return;
        }
        _webDetectorTimer?.cancel();
        setState(() {
          _state = _LoadState.error;
          _isWebSource = false;
          _errorMessage = 'تعذر تشغيل المحتوى. لم يبدأ التشغيل خلال المهلة المحددة.';
        });
        _setWebSessionState(_WebSessionState.stopped);
        return;
      }
      _webStartupTimeoutTimer = Timer(remaining, arm);
    }
    arm();
  }

  Future<void> _autoDetectWebSource(WebViewController controller) async {
    _webDetectorTimer?.cancel();
    final generation = _webSessionGeneration;
    var attempts = 0;
    _setWebSessionState(_WebSessionState.discovering);

    _webDetectorTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_webSessionIsActive(generation)) {
        timer.cancel();
        return;
      }

      // Human verification is checked first, on every tick, and is
      // deliberately exempted from the attempt budget below: solving it is
      // entirely up to the real person watching and can take as long as it
      // takes. We never solve it, click it, or otherwise interact with it —
      // we only detect it, reveal the real page (see build()'s handling of
      // _WebSessionState.humanVerificationRequired) and, once it is gone
      // (cleared by the person themselves), resume automatic discovery
      // exactly as if it had never appeared.
      if (!_webVerificationCheckInFlight) {
        _webVerificationCheckInFlight = true;
        bool verifying = false;
        try {
          verifying = await _detectHumanVerification(controller);
        } catch (_) {
          verifying = false;
        } finally {
          _webVerificationCheckInFlight = false;
        }
        if (!_webSessionIsActive(generation)) {
          timer.cancel();
          return;
        }
        if (verifying) {
          if (_webSessionState != _WebSessionState.humanVerificationRequired) {
            _webHumanVerificationDetected = true;
            _setWebSessionState(_WebSessionState.humanVerificationRequired);
            if (mounted) setState(() {});
          }
          return;
        }
        if (_webHumanVerificationDetected) {
          _webHumanVerificationDetected = false;
          _setWebSessionState(_WebSessionState.discovering);
          if (mounted) setState(() {});
        }
      }

      if (attempts++ >= 15) {
        timer.cancel();
        if (_webSessionIsActive(generation) && _webSessionState == _WebSessionState.discovering) {
          _setWebSessionState(_WebSessionState.webReady);
        }
        return;
      }
      if (_webDetectionInFlight || _webSessionState == _WebSessionState.candidateTrial) return;
      if (_webDrmDetected) {
        _setWebSessionState(_WebSessionState.drmWebOnly);
        timer.cancel();
        return;
      }
      if (_webNativeAttempts >= _webMaxNativeAttempts) {
        _setWebSessionState(_WebSessionState.webReady);
        timer.cancel();
        return;
      }

      _webDetectionInFlight = true;
      try {
        if (await _webPlaybackSentinel(controller)) {
          if (_webSessionIsActive(generation)) {
            await _showWebPlaybackReady(controller);
            _setWebSessionState(_WebSessionState.webReady);
            timer.cancel();
            _webDetectorTimer = null;
          }
          return;
        }

        final iframeCandidate = await _findBestIframeCandidate(controller);
        if (iframeCandidate != null && !_webIframePromotionInFlight && !_webPlaybackReady) {
          final candidateUri = Uri.tryParse(iframeCandidate);
          final candidateHost = candidateUri?.host.toLowerCase() ?? '';
          final currentHost = _webSourceOrigin?.toLowerCase() ?? '';
          final playerish = RegExp(r'(embed|shell|player|video|watch|stream|play|live)', caseSensitive: false).hasMatch(iframeCandidate);
          if (playerish || candidateHost != currentHost) {
            await _promoteIframeToPlayerDocument(controller, iframeCandidate, 80);
            return;
          }
        }

        if (_webMediaEvidenceScore >= 70 && _webMediaResourceHits >= 4) {
          if (_webSessionIsActive(generation)) {
            await _showWebPlaybackReady(controller);
            _setWebSessionState(_WebSessionState.webReady);
            timer.cancel();
            _webDetectorTimer = null;
          }
          return;
        }

        final frameworkSources = await _detectPlayerFrameworkSources(controller);
        final genericSources = await _detectPublicMediaSources(controller);
        final sources = <String>{...frameworkSources, ...genericSources}.toList();
        if (!_webSessionIsActive(generation)) return;

        if (_webInteractionAttempts < _webMaxInteractionAttempts && !await _webPlaybackSentinel(controller)) {
          final interacted = await _runSmartInteraction(controller);
          if (interacted) {
            timer.cancel();
            _webDetectorTimer = null;
            _setWebSessionState(_WebSessionState.discovering);
            unawaited(_autoDetectWebSource(controller));
            return;
          }
        }

        for (final sourceRaw in sources) {
          final source = _normalizeCandidate(sourceRaw);
          final score = _scoreDetectedSource(source) + (frameworkSources.contains(sourceRaw) ? 85 : 0);
          _webCandidateEvidence[source] = (_webCandidateEvidence[source] ?? 0) + 1;
          if (score < 80) continue;
          final uri = Uri.tryParse(source);
          if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) continue;
          if (!_canTrialNative(source)) continue;

          final evidence = _webCandidateEvidence[source] ?? 0;
          final strongHls = _looksLikeHls(source) && score >= 100;
          final strongFramework = frameworkSources.contains(sourceRaw) && score >= 80;
          if (evidence < 2 && !strongHls && !strongFramework) continue;

          // Best-effort validation. A negative validation is not fatal when
          // the browser has already supplied strong evidence (for example a
          // stream requiring Referer/Origin/cookies).
          final validated = await _validatePublicMediaSource(source);
          if (!validated && evidence < 3 && !strongHls && !strongFramework) continue;

          _setWebSessionState(_WebSessionState.candidateTrial);
          _webNativeAttempts++;
          _webLastNativeTrialAt = DateTime.now();
          _extendWebStartupDeadline(const Duration(seconds: 12));
          _webSeenSources.add(source);
          _webCandidateLastReason[source] = 'validated candidate, evidence=$evidence, score=$score';
          timer.cancel();

          final quality = StreamQuality(label: 'المصدر المكتشف تلقائياً', url: source);
          await _playServerQuality(
            StreamServerOption(label: 'المصدر المكتشف تلقائياً', qualities: [quality]),
            quality,
            fallbackToWeb: true,
          );
          return;
        }
      } finally {
        _webDetectionInFlight = false;
      }
    });
  }

  Future<void> _openWebSource(String url) async {
    _webDetectorTimer?.cancel();
    _webSessionGeneration++;
    _webSessionState = _WebSessionState.loadingPage;
    _webDetectionInFlight = false;
    _webNativeAttempts = 0;
    _webLastNativeTrialAt = null;
    _webInteractionAttempts = 0;
    _webLastInteractionAt = null;
    _webPlaybackReady = false;
    _webPlayerFocusApplied = false;
    _webOriginalUrl = url;
    _webInitialLoadCompleted = false;
    _webHumanVerificationDetected = false;
    _webVerificationCheckInFlight = false;
    final webStartupNow = DateTime.now();
    _webStartupDeadline = webStartupNow.add(const Duration(seconds: 20));
    _webStartupHardDeadline = webStartupNow.add(const Duration(seconds: 90));
    _webPromotionFallbackTimer?.cancel();
    _webIframePromotionInFlight = false;
    _webPromotedPlayerMode = false;
    _webIframePromotionAttempts = 0;
    _webLastPromotedIframeUrl = null;
    _webMediaEvidenceScore = 0;
    _webMediaResourceHits = 0;
    _webLastMediaEvidenceAt = null;
    _webStartupTimeoutTimer?.cancel();
    _webSeenSources.clear();
    _webFailedNativeSources.clear();
    _webCandidateEvidence.clear();
    _webCandidateLastReason.clear();
    setState(() {
      _state = _LoadState.loading;
      _isWebSource = true;
      _webContextHeaders = null;
      _webDrmDetected = false;
      _webDrmSystem = null;
    });
    try {
      final sourceUri = Uri.parse(url);
      _webSourceOrigin = sourceUri.host;
      late final WebViewController controller;
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..addJavaScriptChannel(
          'SportsPlayerSource',
          onMessageReceived: (message) {
            try {
              final decoded = jsonDecode(message.message);
              if (decoded is Map) _handleWebIntelligenceMessage(controller, decoded);
            } catch (_) {}
          },
        )
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            if (!_isAllowedWebNavigation(request.url)) {
              return NavigationDecision.prevent;
            }
            if (_webInitialLoadCompleted) {
              final requestHost = Uri.tryParse(request.url)?.host.toLowerCase() ?? '';
              final originHost = _webSourceOrigin?.toLowerCase() ?? '';
              if (requestHost.isNotEmpty && originHost.isNotEmpty && requestHost != originHost) {
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (finishedUrl) async {
            _webInitialLoadCompleted = true;
            if (_webPromotedPlayerMode) {
              _webMediaEvidenceScore = 0;
              _webMediaResourceHits = 0;
              _webLastMediaEvidenceAt = null;
              _extendWebStartupDeadline(const Duration(seconds: 15));
            }
            await _installWebProtection(controller);
            await _captureWebContext(controller);
            if (!mounted) return;
            // Keep the real webpage hidden behind our own loading screen until
            // playback is proven. The WebView remains mounted so its JS/player
            // lifecycle continues normally.
            setState(() => _state = _LoadState.loading);
            if (!_webDrmDetected) {
              _setWebSessionState(_WebSessionState.webReady);
              unawaited(_autoDetectWebSource(controller));
            }
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true && _webSessionState != _WebSessionState.candidateTrial && _webSessionState != _WebSessionState.nativePlaying) {
              setState(() {
                _state = _LoadState.error;
                _errorMessage = 'تعذر فتح صفحة البث. تحقق من الرابط والاتصال بالإنترنت ثم حاول مرة أخرى.';
              });
            }
          },
        ));
      _webController = controller;
      _startWebStartupTimeout(controller, _webSessionGeneration);
      await controller.loadRequest(sourceUri, headers: _effectiveStreamHeaders());
      if (!mounted) return;
      setState(() => _state = _LoadState.loading);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'تعذر فتح صفحة المصدر. تحقق من الرابط وحاول مرة أخرى.';
      });
    }
  }

  // ---------------------- play ----------------------
  Future<void> _proveNativePlayback(VideoPlayerController controller) async {
    final start = controller.value.position;
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!controller.value.isInitialized) {
      throw StateError('Native player did not remain initialized.');
    }
    final value = controller.value;
    final advanced = value.position > start || value.position.inMilliseconds > 300;
    if (!value.isPlaying || value.hasError || !advanced) {
      throw StateError('Native playback proof failed.');
    }
  }

  Map<String, String> _effectiveStreamHeaders() {
    return {
      ..._headers ?? {},
      ...?_webContextHeaders,
      ...?_resolvedStreamHeaders,
    };
  }

  Future<void> _playServerQuality(
      StreamServerOption server, StreamQuality quality, {bool fallbackToWeb = false}) async {
    if (fallbackToWeb) {
      _setWebSessionState(_WebSessionState.candidateTrial);
    }
    setState(() {
      _state = _LoadState.loading;
      _isWebSource = false;
      _activeServer = server;
      _activeQuality = quality;
    });
    try {
      final oldController = _controller;
      oldController?.removeListener(_videoListener);
      await oldController?.dispose();

      // Explicit formatHint so ExoPlayer picks its DASH/HLS extractor
      // directly instead of guessing from the URL — needed for DASH sources
      // in particular, since a signed/extension-less .mpd URL would
      // otherwise not be auto-detected correctly.
      final lowerQualityUrl = quality.url.toLowerCase();
      final formatHint = lowerQualityUrl.contains('.mpd')
          ? VideoFormat.dash
          : lowerQualityUrl.contains('.m3u8')
              ? VideoFormat.hls
              : null;

      final newController = VideoPlayerController.networkUrl(
        Uri.parse(quality.url),
        formatHint: formatHint,
        httpHeaders: {
          ..._effectiveStreamHeaders(),
        },
      );
      _controller = newController;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isPlaying = false;
      newController.addListener(_videoListener);
      await newController.initialize();
      await newController.setPlaybackSpeed(_playbackSpeed);
      await newController.setVolume(_muted ? 0 : _volume / 100);
      await newController.play();
      if (fallbackToWeb) {
        await _proveNativePlayback(newController);
      }
      await WakelockPlus.enable();
      _webStartupTimeoutTimer?.cancel();
      if (!mounted) return;
      if (fallbackToWeb) _setWebSessionState(_WebSessionState.nativePlaying);
      setState(() => _state = _LoadState.ready);
    } catch (error) {
      if (!mounted) return;
      if (fallbackToWeb) {
        final failedController = _controller;
        _controller = null;
        try {
          await failedController?.dispose();
        } catch (_) {}
        final failedUrl = _normalizeCandidate(quality.url);
        _webFailedNativeSources.add(failedUrl);
        _webSeenSources.add(failedUrl);
        _webCandidateLastReason[failedUrl] = 'native playback failed: ${_describePlaybackError(error)}';
        _extendWebStartupDeadline(const Duration(seconds: 8));
        _setWebSessionState(_WebSessionState.nativeFailed);
        setState(() {
          _isWebSource = true;
          _state = _LoadState.loading;
          _errorMessage = '';
        });
        final web = _webController;
        if (web != null && _webNativeAttempts < _webMaxNativeAttempts && !_webDrmDetected) {
          _startWebStartupTimeout(web, _webSessionGeneration);
          _setWebSessionState(_WebSessionState.webFallback);
          Future<void>.delayed(const Duration(milliseconds: 1200), () {
            if (mounted && _isWebSource && !_webDrmDetected &&
                _webSessionState == _WebSessionState.webFallback) {
              unawaited(_autoDetectWebSource(web));
            }
          });
        } else {
          _setWebSessionState(_webDrmDetected
              ? _WebSessionState.drmWebOnly
              : _WebSessionState.webReady);
        }
        return;
      }
      setState(() {
        _state = _LoadState.error;
        _errorMessage = _describePlaybackError(error);
      });
    }
  }

  String _describePlaybackError(Object error) {
    final text = error.toString().toLowerCase();

    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('unable to connect') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('no route to host')) {
      return 'لا يوجد اتصال بالخادم. تحقق من الإنترنت ثم حاول مرة أخرى.';
    }
    if (text.contains('timeout') || text.contains('timed out')) {
      return 'انتهت مهلة الاتصال بالخادم. قد يكون الخادم بطيئًا أو الاتصال غير مستقر.';
    }
    if (text.contains('404') || text.contains('410') || text.contains('not found') || text.contains('gone')) {
      return 'المصدر غير موجود أو انتهت صلاحيته. جرّب سيرفرًا آخر.';
    }
    if (text.contains('403') || text.contains('401') || text.contains('forbidden') || text.contains('unauthorized')) {
      return 'الخادم رفض الوصول إلى هذا المصدر. جرّب سيرفرًا أو جودة أخرى.';
    }
    if (text.contains('unrecognized') || text.contains('unsupported') || text.contains('source error') ||
        text.contains('parsererror') || text.contains('decoder') || text.contains('mime') || text.contains('format')) {
      return 'صيغة هذا المصدر غير مدعومة على جهازك. جرّب سيرفرًا أو جودة أخرى.';
    }
    if (text.contains('behind live window') || text.contains('live window') || text.contains('behindlivewindow')) {
      return 'تعذر الوصول إلى نقطة البث المباشر الحالية. أعد المحاولة أو جرّب سيرفرًا آخر.';
    }
    if (text.contains('drm') || text.contains('widevine') || text.contains('encrypted')) {
      return 'هذا المصدر يستخدم حماية DRM ولا يمكن تشغيله بالمشغل الأصلي.';
    }
    return 'حدث خطأ أثناء تشغيل المصدر. جرّب مرة أخرى أو اختر سيرفرًا آخر.';
  }

  bool get _contentIsSeekable => _duration > Duration.zero;

  // ---------------------- controls ----------------------
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_locked) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (_locked) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    _isPlaying ? controller.pause() : controller.play();
    _scheduleHide();
  }

  void _seekBy(Duration delta) {
    final controller = _controller;
    if (controller == null) return;
    final target = _position + delta;
    controller.seekTo(target < Duration.zero ? Duration.zero : target);
    _cancelSlowConnectionTimer();
    if (_isBuffering) _startSlowConnectionTimer();
    _scheduleHide();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : _volume / 100);
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      _muted = value == 0;
    });
    _controller?.setVolume(_muted ? 0 : value / 100);
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  void _exit() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      SystemNavigator.pop();
    }
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    if (!_locked) {
      setState(() => _controlsVisible = true);
      _scheduleHide();
    }
  }

  void _toggleFit() {
    setState(
        () => _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain);
  }

  void _jumpToLive() {
    final controller = _controller;
    if (controller == null) return;
    if (_duration > Duration.zero) {
      controller.seekTo(_duration);
    }
    if (!_isPlaying) controller.play();
    _scheduleHide();
  }

  Future<void> _changeSpeed(double speed) async {
    await _controller?.setPlaybackSpeed(speed);
    setState(() {
      _playbackSpeed = speed;
      _showSpeedSheet = false;
    });
    _scheduleHide();
  }

  void _openSpeedSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('سرعة التشغيل',
                    style: TextStyle(color: Colors.white70)),
              ),
              ..._speedOptions.map((speed) {
                final selected = speed == _playbackSpeed;
                return ListTile(
                  title: Text(
                    '${speed}x',
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check, color: Colors.greenAccent)
                      : null,
                  onTap: () => _changeSpeed(speed),
                );
              }),
            ],
          ),
        );
      },
    ).then((_) {
      if (mounted) setState(() => _showSpeedSheet = false);
    });
  }

  // ---------------------- screenshot ----------------------
  Future<void> _takeScreenshot() async {
    if (_savingScreenshot || _state != _LoadState.ready) return;
    setState(() => _savingScreenshot = true);
    try {
      final boundaryContext = _videoBoundaryKey.currentContext;
      if (boundaryContext == null) throw Exception('فشل التقاط الصورة.');
      final boundary =
          boundaryContext.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('فشل التقاط الصورة.');
      final bytes = byteData.buffer.asUint8List();
      if (Platform.isAndroid || Platform.isIOS) {
        final result = await ImageGallerySaverPlus.saveImage(bytes,
            quality: 100, name: 'sports_player_${DateTime.now().millisecondsSinceEpoch}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    result['isSuccess'] == true ? 'تم حفظ الصورة.' : 'تعذر حفظ الصورة.')),
          );
        }
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final saved = File('${dir.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png');
        await saved.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم حفظ الصورة في:\n${saved.path}')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر التقاط صورة.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingScreenshot = false);
    }
  }

  // ---------------------- gestures ----------------------
  void _handleDoubleTapDown(TapDownDetails details) {
    if (_locked || _state != _LoadState.ready) return;
    if (!_contentIsSeekable) return;
    final width = MediaQuery.of(context).size.width;
    final isRight = details.globalPosition.dx > width / 2;
    _seekBy(Duration(seconds: isRight ? 10 : -10));
    _seekFeedbackTimer?.cancel();
    setState(() => _seekFeedback = isRight ? 'right' : 'left');
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_locked || _state != _LoadState.ready) return;
    if (!_contentIsSeekable) return;
    _swipeStart = details.globalPosition;
    _seekingFromSwipe = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_swipeStart == null || _seekingFromSwipe) return;
    final delta = details.globalPosition.dx - _swipeStart!.dx;
    if (delta.abs() > _swipeThreshold) {
      _seekingFromSwipe = true;
      final seconds = (delta / _swipeThreshold).round() * 5;
      _seekBy(Duration(seconds: seconds));
      _seekFeedbackTimer?.cancel();
      setState(() => _seekFeedback = delta > 0 ? 'right' : 'left');
      _seekFeedbackTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _seekFeedback = null);
      });
      _swipeStart = details.globalPosition;
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _swipeStart = null;
    _seekingFromSwipe = false;
  }

  double _dragStartVolume = 0;

  void _onVerticalDragStart(DragStartDetails details) {
    if (_locked || _state != _LoadState.ready) return;
    _swipeStart = details.globalPosition;
    _dragStartVolume = _muted ? 0 : _volume;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_swipeStart == null) return;
    final height = MediaQuery.of(context).size.height;
    final delta = (_swipeStart!.dy - details.globalPosition.dy) / height;
    final newVolume = (_dragStartVolume + delta * 100).clamp(0.0, 100.0);
    _setVolume(newVolume);
    _scheduleHide();
  }

  // ---------------------- sheets ----------------------
  void _openQualitySheet() {
    final session = _session;
    if (session == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (session.hasMultipleServers) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child:
                      Text('السيرفر', style: TextStyle(color: Colors.white70)),
                ),
                ...session.servers.map((server) => ListTile(
                      title: Text(server.label,
                          style: const TextStyle(color: Colors.white)),
                      trailing: server.label == _activeServer?.label
                          ? const Icon(Icons.check, color: Colors.greenAccent)
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _playServerQuality(server, server.qualities.first);
                      },
                    )),
              ],
              if (_activeServer != null &&
                  _activeServer!.qualities.length > 1) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child:
                      Text('الجودة', style: TextStyle(color: Colors.white70)),
                ),
                ..._activeServer!.qualities.map((quality) => ListTile(
                      title: Text(quality.label,
                          style: const TextStyle(color: Colors.white)),
                      trailing: quality.label == _activeQuality?.label
                          ? const Icon(Icons.check, color: Colors.greenAccent)
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _playServerQuality(_activeServer!, quality);
                      },
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---------------------- lifecycle ----------------------
  bool _wasPlayingBeforeBackground = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (controller.value.isPlaying) {
          _wasPlayingBeforeBackground = true;
          controller.pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforeBackground) {
          _wasPlayingBeforeBackground = false;
          controller.play();
        }
        break;
    }
  }

  @override
  void dispose() {
    _webDetectorTimer?.cancel();
    _webStartupTimeoutTimer?.cancel();
    _webPromotionFallbackTimer?.cancel();
    if (identical(_activeInstance, this)) _activeInstance = null;
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _slowConnectionTimer?.cancel();
    _controller?.removeListener(_videoListener);
    WakelockPlus.disable();
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ---------------------- تعديل _startSession (استخدام المعالجة الجديدة) ----------------------
  Future<void> _startSession() async {
    setState(() => _state = _LoadState.loading);

    _resolvedStreamHeaders = null;

    // تحسين الهيدرز لمحاكاة مستخدم حقيقي
    _headers = {
      'user-agent': widget.externalUserAgent ??
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.119 Mobile Safari/537.36',
      'accept-language': 'ar,en-US;q=0.9,en;q=0.8',
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin',
      ...?(_headers ?? {}),
    };

    StreamSession? session;

    if (widget.externalUrl != null && widget.externalUrl!.isNotEmpty) {
      final external = widget.externalUrl!.trim();
      final lower = external.toLowerCase();
      final looksLikeVideo = lower.contains('.m3u8') ||
          lower.contains('.mp4') ||
          lower.contains('.m4v') ||
          lower.contains('.mov') ||
          lower.contains('.webm');
      session = StreamSession.success(
        kind: looksLikeVideo ? StreamKind.hls : StreamKind.web,
        isLive: !looksLikeVideo,
        servers: [
          StreamServerOption(
            label: looksLikeVideo ? 'الرابط المُدخل' : 'صفحة البث',
            qualities: [
              StreamQuality(label: looksLikeVideo ? 'تلقائي' : 'صفحة البث', url: external)
            ],
          ),
        ],
      );
    } else if (widget.channelId != null) {
      final channelId = widget.channelId!;

      // The dashboard/CMS is the source of truth for a channel's
      // sourceType/sourceUrl (see ChannelSourceResolver — it was previously
      // defined but never actually called from here, which is the real
      // reason a dashboard-configured "Source Type: WEB" page such as
      // Rotana never reached WebView: this screen was instead always
      // guessing a legacy API host from the raw id below and running HTTP
      // resolution on it). Try the CMS resolver first so a "web" source is
      // sent to WebView exactly as configured, hash route included, with no
      // HTTP resolution attempted on it at all.
      StreamSession? cmsSession;
      var cmsResolverAvailable = true;
      try {
        cmsSession = await ChannelSourceResolver.resolve(channelId);
      } catch (_) {
        cmsResolverAvailable = false;
      }

      if (cmsResolverAvailable && cmsSession != null) {
        session = cmsSession;
        if (cmsSession.headers.isNotEmpty) {
          // Dashboard-configured Referer/User-Agent, when present, ride
          // alongside whatever the resolver/WebView discover on their own
          // (see _effectiveStreamHeaders) — they never replace defaults
          // when left empty in the dashboard.
          _headers = {...?_headers, ...cmsSession.headers};
        }
      } else {
        // Legacy fallback — preserved as-is for ids that are not real
        // Firestore channel documents (e.g. the CMS/Firestore plugin itself
        // is unavailable), so nothing that currently works this way breaks.
        String apiUrl = channelId;
        if (!apiUrl.startsWith('http')) {
          apiUrl = 'https://def.ycnapi.com' + (apiUrl.startsWith('/') ? '' : '/') + apiUrl;
        }
        session = await _resolveChannelUrl(apiUrl);
      }
    } else {
      session = StreamSession.failure('لا يوجد مصدر بث لتشغيله.');
    }

    if (!mounted) return;

    if (session == null || !session.ok || session.servers.isEmpty) {
      setState(() {
        _state = _LoadState.error;
        _errorMessage = session?.errorMessage ?? 'تعذر تشغيل البث.';
      });
      return;
    }

    _session = session;
    if (session.kind == StreamKind.web) {
      await _openWebSource(session.servers.first.qualities.first.url);
      return;
    }
    await _playServerQuality(
      session.servers.first,
      session.servers.first.qualities.first,
    );
  }

  // ---------------------- build ----------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: _toggleControls,
          onDoubleTapDown: _handleDoubleTapDown,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_isWebSource && _webController != null)
                WebViewWidget(controller: _webController!),
              if (_state == _LoadState.ready && !_isWebSource) Center(child: _buildVideo()),
              if (_state == _LoadState.loading &&
                  _webSessionState != _WebSessionState.humanVerificationRequired)
                _buildLoading(),
              if (_webSessionState == _WebSessionState.humanVerificationRequired)
                _buildHumanVerificationBanner(),
              if (_state == _LoadState.error) _buildError(),
              if (_state == _LoadState.ready && !_isWebSource && _isBuffering)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (_state == _LoadState.ready &&
                  !_isWebSource &&
                  _isBuffering &&
                  _slowConnectionHint)
                Positioned(
                  bottom: 88,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.signal_wifi_statusbar_connected_no_internet_4,
                            color: Colors.white70, size: 13),
                        SizedBox(width: 4),
                        Text('اتصال بطيء',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              if (_seekFeedback != null)
                Align(
                  alignment: Alignment(_seekFeedback == 'right' ? 0.78 : -0.78, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _seekFeedback == 'right'
                          ? Icons.forward_10
                          : Icons.replay_10,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              if (_state == _LoadState.ready && !_isWebSource && !_locked)
                AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: _buildControls(),
                  ),
                ),
              if (_state == _LoadState.ready && !_isWebSource)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _circleIconButton(
                    icon: _locked ? Icons.lock : Icons.lock_open,
                    tooltip: _locked ? 'إلغاء القفل' : 'قفل الشاشة',
                    onPressed: _toggleLock,
                  ),
                ),
              if (_state == _LoadState.ready && !_isWebSource && _playbackSpeed != 1.0)
                Positioned(
                  top: 12,
                  left: 56,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideo() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final size = controller.value.size;
    final double width = size.width == 0 ? 16.0 : size.width;
    final double height = size.height == 0 ? 9.0 : size.height;
    return RepaintBoundary(
      key: _videoBoundaryKey,
      child: FittedBox(
        fit: _fit,
        child: SizedBox(
          width: width,
          height: height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3.2,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'جاري تشغيل المحتوى…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 2)),
                Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// شريط توضيحي غير تفاعلي (IgnorePointer) يظهر أعلى الشاشة فقط أثناء
  /// انتظار تحقق بشري حقيقي (Cloudflare/hCaptcha/reCAPTCHA). لا يحجب أي
  /// جزء آخر من الصفحة ولا يعترض أي لمسة إطلاقاً — الصفحة الحقيقية تحتها
  /// تبقى قابلة للتفاعل بالكامل، والمستخدم يحل التحقق بنفسه من داخلها.
  Widget _buildHumanVerificationBanner() {
    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: SafeArea(
          bottom: false,
          child: Container(
            margin: const EdgeInsets.only(top: 12, left: 16, right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.78),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user_outlined, color: Colors.amberAccent, size: 20),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'يرجى إكمال التحقق أدناه للمتابعة — سيستأنف التشغيل تلقائياً بعد ذلك.',
                    style: TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: _startSession,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
                if (_session != null && _session!.hasMultipleServers) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openQualitySheet,
                    icon: const Icon(Icons.dns),
                    label: const Text('تغيير السيرفر'),
                  ),
                ],
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _exit,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('رجوع'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    double size = 40,
    double iconSize = 20,
    Widget? child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withOpacity(0.35),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: child ??
                    Icon(icon, color: Colors.white, size: iconSize),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final isLive = _session?.isLive ?? false;
    final canSeek = _contentIsSeekable;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent, Colors.black87],
          stops: [0, 0.45, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  _circleIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'رجوع',
                    onPressed: _exit,
                  ),
                  const SizedBox(width: 6),
                  if (isLive && !canSeek)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.circle, color: Colors.white, size: 8),
                          SizedBox(width: 5),
                          Text('مباشر',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )
                  else if (_activeQuality != null)
                    Text(
                      _activeQuality!.label,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  const Spacer(),
                  if (isLive && !canSeek)
                    _circleIconButton(
                      icon: Icons.live_tv,
                      tooltip: 'القفز للبث المباشر',
                      onPressed: _jumpToLive,
                    ),
                  _circleIconButton(
                    icon: _muted ? Icons.volume_off : Icons.volume_up,
                    tooltip: _muted ? 'إلغاء كتم الصوت' : 'كتم الصوت',
                    onPressed: _toggleMute,
                  ),
                  SizedBox(
                    width: 78,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: _muted ? 0 : _volume,
                        min: 0,
                        max: 100,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white30,
                        onChanged: _setVolume,
                      ),
                    ),
                  ),
                  _circleIconButton(
                    icon: Icons.more_vert,
                    tooltip: 'المزيد من الخيارات',
                    onPressed: _openMoreOptionsSheet,
                  ),
                ],
              ),
            ),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canSeek)
                    _circleIconButton(
                      icon: Icons.replay_10,
                      tooltip: 'تراجع 10 ثواني',
                      size: 52,
                      iconSize: 28,
                      onPressed: () => _seekBy(const Duration(seconds: -10)),
                    ),
                  const SizedBox(width: 22),
                  _circleIconButton(
                    icon: _isPlaying ? Icons.pause : Icons.play_arrow,
                    tooltip: _isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
                    size: 72,
                    iconSize: 40,
                    onPressed: _togglePlay,
                  ),
                  const SizedBox(width: 22),
                  if (canSeek)
                    _circleIconButton(
                      icon: Icons.forward_10,
                      tooltip: 'تقديم 10 ثواني',
                      size: 52,
                      iconSize: 28,
                      onPressed: () => _seekBy(const Duration(seconds: 10)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 6, 4),
              child: Row(
                children: [
                  if (canSeek) ...[
                    Text(_formatDuration(_position),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14),
                        ),
                        child: Slider(
                          value: _position.inMilliseconds
                              .clamp(
                                  0,
                                  _duration.inMilliseconds == 0
                                      ? 1
                                      : _duration.inMilliseconds)
                              .toDouble(),
                          min: 0,
                          max: _duration.inMilliseconds == 0
                              ? 1
                              : _duration.inMilliseconds.toDouble(),
                          activeColor: Colors.redAccent,
                          inactiveColor: Colors.white30,
                          onChanged: (value) => _controller
                              ?.seekTo(Duration(milliseconds: value.toInt())),
                        ),
                      ),
                    ),
                    Text(_formatDuration(_duration),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ] else
                    const Spacer(),
                  _circleIconButton(
                    icon: _fullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    tooltip:
                        _fullscreen ? 'الخروج من ملء الشاشة' : 'ملء الشاشة',
                    onPressed: _toggleFullscreen,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMoreOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.aspect_ratio, color: Colors.white),
                title: const Text('وضع العرض',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _fit == BoxFit.contain ? 'ملائم للشاشة' : 'تعبئة الشاشة',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _toggleFit();
                },
              ),
              if (_session != null &&
                  (_session!.hasMultipleServers ||
                      _session!.hasMultipleQualities))
                ListTile(
                  leading: const Icon(Icons.hd, color: Colors.white),
                  title: const Text('الجودة والسيرفر',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openQualitySheet();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.speed, color: Colors.white),
                title: const Text('سرعة التشغيل',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text('${_playbackSpeed}x',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSpeedSheet();
                },
              ),
              ListTile(
                leading: _savingScreenshot
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.camera_alt, color: Colors.white),
                title: const Text('التقاط صورة',
                    style: TextStyle(color: Colors.white)),
                onTap: _savingScreenshot
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _takeScreenshot();
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}