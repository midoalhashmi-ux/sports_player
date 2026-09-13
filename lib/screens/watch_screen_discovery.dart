part of 'watch_screen.dart';

// ============================================================================
// محرك اكتشاف مصدر البث (WebView -> Native)
// ============================================================================
// mixin منفصل فيزيائياً عن watch_screen.dart (part of نفس الـlibrary، فيه
// وصول تلقائي لكل الأنواع الخاصة المشتركة: _LoadState، _WebSessionState،
// _CandidateProbe، _WebNetworkCandidate، _RelayedManifest). يحوي كل حقول/دوال
// اكتشاف المصدر (حقن جافاسكربت، تسجيل مرشحين، تقييم أدلة، آلة حالة الجلسة،
// محاولات التشغيل الأصلي...) اللي كانت داخل _WatchScreenState مباشرة —
// ~2650 سطر من أصل ~5400 قبل هذا الفصل.
//
// كل الأعضاء المذكورة بالكتلة المجرَّدة (abstract) أسفل ما زالت مُعرَّفة
// فعلياً بـ_WatchScreenState نفسها (بلا أي تغيير بجسمها) — الإعلان هنا فقط
// يخبر دارت "أي كلاس يستخدم هذا الـmixin لازم يوفّر هذي الأعضاء"، فيربطهم
// المترجم تلقائياً بالتجميع (with _StreamDiscoveryMixin). أي عدم تطابق هنا
// = خطأ ترجمة واضح فوراً، مو علة سلوك صامتة.
//
// هذا الفصل نقل فيزيائي بحت — صفر تغيير سلوكي مقصود. المكوّن الوحيد اللي
// تغيّر فعلياً: _autoDiscoveredServerLabel تحوّل من `static const` لـgetter
// عادي (قيمة الإرجاع نفسها بالضبط) لأن static members لا تُورَّث عبر آلية
// mixin — راجع تعليقها بـwatch_screen.dart.
// ============================================================================

mixin _StreamDiscoveryMixin on State<WatchScreen> {
  // -----------------------------------------------------------------------
  // أعضاء مُقدَّمة من _WatchScreenState نفسها (الجزء المتبقي بـwatch_screen.dart)
  // — إعلانات مجرَّدة فقط (بدون جسم/قيمة)، تسمح لدارت بربطها فعلياً بالكلاس
  // النهائي عند التجميع (with _StreamDiscoveryMixin). كل واحد منها له توقيع
  // مطابق تماماً للتصريح الحقيقي الموجود بـwatch_screen.dart — أي اختلاف هنا
  // يمنع الترجمة فوراً وبوضوح (خطأ ترجمة، وليس علة سلوك صامتة).
  _LoadState get _state;
  set _state(_LoadState value);
  bool get _isWebSource;
  set _isWebSource(bool value);
  // _errorMessage: تُكتب هنا فقط، ما تُقرأ (تُعرض لاحقاً بواجهة الشاشة
  // بـwatch_screen.dart) — setter فقط، بدون getter غير مستخدَم هنا.
  set _errorMessage(String value);
  // _session: تُقرأ هنا فقط، ما تُكتب — getter فقط.
  StreamSession? get _session;
  StreamServerOption? get _activeServer;
  set _activeServer(StreamServerOption? value);
  // _activeQuality: تُكتب هنا فقط، ما تُقرأ — setter فقط.
  set _activeQuality(StreamQuality? value);
  WebViewController? get _webController;
  set _webController(WebViewController? value);
  Map<String, String>? get _headers;
  // _resolvedStreamHeaders: تُقرأ هنا فقط، ما تُكتب — getter فقط.
  Map<String, String>? get _resolvedStreamHeaders;
  String get _autoDiscoveredServerLabel;

  Map<String, String> _effectiveStreamHeaders();
  String _resolveRelativeUrl(String url, String baseUrl);
  Future<void> _muteWebForNativeTrial(bool mute);
  Future<void> _playServerQuality(
    StreamServerOption server,
    StreamQuality quality, {
    bool fallbackToWeb = false,
    Map<String, String>? playbackHeaders,
    VideoFormat? formatHintOverride,
  });
  // -----------------------------------------------------------------------

  // ---------------------- web source (بقيت كما هي) ----------------------
  String? _webSourceOrigin;
  Timer? _webDetectorTimer;
  _WebSessionState _webSessionState = _WebSessionState.idle;
  int _webSessionGeneration = 0;
  bool _webDetectionInFlight = false;
  int _webNativeAttempts = 0;
  // كانت static const — تحوّلت لـgetter عادي (نفس القيمة) لأن static
  // members لا يصل لها كود يبقى بـwatch_screen.dart إلا بتأهيل صريح
  // (_StreamDiscoveryMixin.xxx)، بخلاف الأعضاء العادية اللي يدمجها الـmixin
  // تلقائياً. راجع flutter analyze: unqualified_reference_to_non_local_static_member.
  int get _webMaxNativeAttempts => 2;
  DateTime? _webLastNativeTrialAt;
  final Set<String> _webSeenSources = <String>{};
  final Set<String> _webFailedNativeSources = <String>{};
  final Map<String, int> _webCandidateEvidence = <String, int>{};
  final Map<String, String> _webCandidateLastReason = <String, String>{};
  // مضيف السيرفر اللي نجح آخر مرة لنفس القناة (يُحمَّل مرة واحدة بداية
  // جلسة الاكتشاف) — يُستخدم لتقديم أي مرشح جديد على نفس المضيف أولاً
  // بدل انتظاره خلف مرشحين آخرين لم يسبق أن نجحوا. راجع PreferredServerService.
  String? _preferredServerHost;
  bool _preferredServerHostLoaded = false;
  // اتصال HTTP واحد يُعاد استخدامه لكل نداءات فحص/تحقق المرشحين طوال
  // الجلسة بدل فتح اتصال جديد بكل نداء. راجع StreamNetworkClient.
  final StreamNetworkClient _streamNetworkClient = StreamNetworkClient();
  Map<String, String>? _webContextHeaders;
  bool _webDrmDetected = false;
  int _webInteractionAttempts = 0;
  // نفس سبب تحويل _webMaxNativeAttempts أعلاه.
  int get _webMaxInteractionAttempts => 3;
  DateTime? _webLastInteractionAt;
  DateTime? _webLastPrimeAt;
  Timer? _webStartupTimeoutTimer;
  bool _webPlaybackReady = false;
  bool _webPlaybackProven = false;
  DateTime? _webLastDetectionKickAt;
  bool _webPlayerFocusApplied = false;
  String? _webOriginalUrl;
  DateTime? _webStartupDeadline;
  DateTime? _webStartupHardDeadline;
  Timer? _webPromotionFallbackTimer;
  bool _webIframePromotionInFlight = false;
  bool _webPromotedPlayerMode = false;
  // يصير true أول ما نشوف دليل تشغيل حقيقي (web_playback: playing=true)
  // ويبقى true لبقية الجلسة — يمنع حارس التنقّل من السماح بأي تحويل
  // لدومين مختلف بعد بدء التشغيل الفعلي، حتى بوضع "مشغّل مُرقّى" اللي
  // يسمح عادة بتحويلات عابرة للنطاق كمصدر/CDN شرعي. فيديو يشتغل فعلاً ما
  // له سبب شرعي يستبدل الصفحة كاملة — رُصد فعلياً بسجل تشخيص حقيقي: سلسلة
  // إعلانات "تثبيت VPN" وهمية خطفت الإطار الرئيسي ~7 ثوانٍ منتصف تشغيل ناجح.
  bool _webRealPlaybackConfirmed = false;
  // Vidmoly is a real embedded HLS.js player surface. Keep it visible so a
  // user tap can reach the player when Android blocks autoplay.
  bool _webVidmolyPlayerMode = false;
  bool _webVideoJsPlayerMode = false;
  Timer? _webVidmolyRevealTimer;
  int _webIframePromotionAttempts = 0;
  String? _webLastPromotedIframeUrl;
  int _webMediaEvidenceScore = 0;
  int _webMediaResourceHits = 0;
  final Map<String, _WebNetworkCandidate> _webCandidateRegistry =
      <String, _WebNetworkCandidate>{};
  // بنية "تحويل جلب المانفست عبر WebView" — راجع _relayManifestViaWebView.
  // محاولة واحدة فقط لكل رابط مرشّح (وليس لكل جلسة ويب بالكامل) — كانت
  // محاولة واحدة لكل الجلسة تمنع أي إنقاذ عن كل مرشّح فشل تشغيله أصلياً
  // بعد أول مرشّح (شوهد فعلياً بسجل تشخيص: مرشّح ثانٍ فشل native trial بدون
  // أي محاولة MANIFEST_RELAY له إطلاقاً لأن المحاولة الوحيدة استُهلكت على
  // الأول). التتبّع لكل رابط يمنع لا يزال التكرار اللا نهائي على *نفس*
  // الرابط لو فشل الإنقاذ نفسه.
  final Map<String, Completer<String?>> _pendingManifestFetches = {};
  final Set<String> _webManifestRelayAttemptedUrls = <String>{};
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
  // Kept backward-compatible with existing Firestore documents: absence of
  // settings/player.showSourcePage means visible.
  bool _showSourcePage = true;
  bool _webPageRevealedByUser = false;
  // شاشة "تم تشغيل المصدر في الخلفية" غالباً مرحلة عابرة (بضع ثوانٍ) قبل
  // ما يتحول التشغيل للمشغل الأصلي — إظهارها فوراً يسبب وميضاً مزعجاً.
  // نؤجّل ظهورها بمهلة قصيرة؛ لو انتهت الحالة العابرة قبل انقضائها (الحالة
  // الشائعة) لا تظهر إطلاقاً، وتبقى مؤشر التحميل العادي كافياً.
  bool _hiddenSourceGraceElapsed = false;
  Timer? _hiddenSourceGraceTimer;
  // رسالة الانتظار تتغيّر مع الوقت لتطمئن المستخدم إن المشغل ما زال
  // شغّالاً (لا يبدو متجمّداً) بدل نص ثابت واحد قد يدفعه يرجع للخلف
  // ظناً منه إن التشغيل تعطّل.
  DateTime? _loadingBeganAt;
  Timer? _loadingTickerTimer;
  // يمنع _startSession() من التشغيل أكثر من مرة لنفس الشاشة، حتى لو رجع
  // استدعاء AdService.showInterstitialThenProceed أكثر من مرة (سباق بين
  // نسختين من WatchScreen تفتحان بسرعة لنفس القناة، أو أي سبب آخر). بدون
  // هذا الحارس كانت الصفحة تُعاد من الصفر منتصف عملية الاكتشاف، فتُهدر
  // عشرات الثواني من مهلة محاولة التشغيل الأصلي — وهذا سبب رئيسي لتذبذب
  // نجاح الانتقال للمشغل الأصلي حتى بالمصادر التي تنجح عادة.
  bool _sessionStarted = false;

  void _smartLog(String scope, String message) {
    if (kDebugMode) debugPrint('[$scope] $message');
  }

  // يسجّل بسجل التشخيص القابل للتصدير (SessionLogService) — منفصل تماماً
  // عن _smartLog (الذي يطبع فقط بوضع التطوير)، حتى يبقى متاحاً بنسخة
  // الإنتاج عند تفعيل زر التشخيص من لوحة التحكم.
  void _slog(String phase, [String details = '']) {
    SessionLogService.instance.log(phase, details);
  }

  String _safeLogUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return '<invalid-url>';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}';
  }

  /// webview_flutter may return JSON.stringify(...) either as a decoded
  /// object or as a JSON-encoded string containing another JSON string.
  /// Unwrap both forms so playback sentinels work consistently on Android.
  dynamic _decodeJavaScriptResult(dynamic result) {
    dynamic value = result;
    for (var i = 0; i < 3 && value is String; i++) {
      final text = value.trim();
      if (text.isEmpty) return null;
      try {
        final decoded = jsonDecode(text);
        if (decoded is String && decoded == value) return value;
        value = decoded;
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  void _setWebSessionState(_WebSessionState next) {
    if (_webSessionState == next) return;
    // nativePlaying يجب يبقى نهائياً بمجرد تحقّقه (راجع state-machine.md) —
    // شوهد فعلياً بسجل تشخيص: بعد نجاح تشغيل أصلي (PLAY_SERVER_QUALITY_SUCCESS)
    // وبينما WebView المخفي يستمر يتنقّل عبر سلسلة تحويلات إعلانية بالخلفية،
    // onPageFinished يمرّ من حارسه الخاص وتُستدعى _autoDetectWebSource من
    // جديد، اللي تكتب فوق هذه الحالة بلا شرط في أول سطر لها — فيُهدر آخر
    // محاولة تشغيل أصلي على إعادة تشغيل مصدر شغّال فعلاً، ويُسمع المستخدم
    // انقطاعاً/إعادة تشغيل للفيديو الشغّال. حماية مركزية هنا أوثق من ملاحقة
    // كل موقع استدعاء على حدة. الجلسة الجديدة (_openWebSource) تتجاوز هذا
    // الحارس عمداً بتعيين الحقل مباشرة لا عبر هذه الدالة.
    if (_webSessionState == _WebSessionState.nativePlaying) return;
    _webSessionState = next;
  }

  bool _webSessionIsActive(int generation) =>
      mounted && generation == _webSessionGeneration &&
      _webSessionState != _WebSessionState.stopped &&
      // بعد نجاح الانتقال للمشغل الأصلي لا داعٍ لأي اكتشاف إضافي — تركه
      // نشطاً كان يخلّي صفحة WebView (المخفية بالخلفية) تستمر بالتنقل
      // وأحياناً يعيد محاولة تشغيل أصلي ثانية فيهدم النسخة الشغّالة فعلياً.
      _webSessionState != _WebSessionState.nativePlaying;

  String _normalizeCandidate(String url) => CandidateScoring.normalizeCandidate(url);

  bool _canTrialNative(String source) {
    if (_webDrmDetected) return false;
    if (_webNativeAttempts >= _webMaxNativeAttempts) return false;
    if (_webFailedNativeSources.contains(source)) return false;
    final registered = _webCandidateRegistry[source];
    if (registered?.quarantined == true || registered?.failed == true) return false;
    if (_webSessionState == _WebSessionState.validating ||
        _webSessionState == _WebSessionState.nativeTrial ||
        _webSessionState == _WebSessionState.candidateTrial ||
        _webSessionState == _WebSessionState.nativePlaying) {
      return false;
    }
    final last = _webLastNativeTrialAt;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 2)) {
      return false;
    }
    return true;
  }

  void _registerWebCandidate(
    String rawUrl, {
    required String source,
    String? mime,
    int evidenceScore = 0,
    String? pageUrl,
    String? frameUrl,
    String? referer,
  }) {
    final normalized = _normalizeCandidate(rawUrl);
    final uri = Uri.tryParse(normalized);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    final mimeLower = (mime ?? '').toLowerCase();
    final hlsMime = mimeLower.contains('mpegurl');
    final existing = _webCandidateRegistry[normalized];
    if (existing != null) {
      existing.evidenceScore =
          (existing.evidenceScore + evidenceScore).clamp(0, 1000).toInt();
      if (existing.type == 'unknown' &&
          (_looksLikeHls(normalized) || hlsMime)) {
        existing.type = 'hls';
      }
      if (mime != null && mime.isNotEmpty) existing.mime = mime;
      if (pageUrl != null && pageUrl.startsWith('http')) {
        // The same master can be reported first by performance entries and
        // then by the player API. Keep the most useful document context for
        // native replay headers.
        existing.pageUrl = pageUrl;
        existing.frameUrl = frameUrl ?? pageUrl;
      }
      if (referer != null && referer.startsWith('http')) {
        existing.referer = referer;
      }
      return;
    }
    final candidatePageUrl = pageUrl ?? _webOriginalUrl ?? '';
    final type = _looksLikeHls(normalized) || hlsMime
        ? 'hls'
        : _looksLikeProgressiveVideo(normalized)
            ? 'progressive'
            : 'unknown';
    _webCandidateRegistry[normalized] = _WebNetworkCandidate(
      url: normalized,
      source: source,
      type: type,
      timestamp: DateTime.now(),
      pageUrl: candidatePageUrl,
      frameUrl: frameUrl ?? candidatePageUrl,
      referer: referer ?? _webContextHeaders?['referer'] ?? '',
      mime: mime ?? '',
      evidenceScore: evidenceScore,
    );
    _smartLog('HLS', 'candidate discovered ($source): ${_safeLogUrl(normalized)}');
  }

  void _kickWebDetection(WebViewController controller) {
    if (!mounted ||
        _webDrmDetected ||
        _webSessionState == _WebSessionState.candidateTrial ||
        _webSessionState == _WebSessionState.nativeTrial ||
        _webSessionState == _WebSessionState.nativePlaying ||
        _webDetectionInFlight) {
      return;
    }
    final last = _webLastDetectionKickAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _webLastDetectionKickAt = DateTime.now();
    // A manual tap can happen after the detector's finite initial budget has
    // ended. Restart the same bounded detector instead of making playback
    // depend on the original timer still being alive.
    if (_webDetectorTimer == null) {
      _setWebSessionState(_WebSessionState.discovering);
      unawaited(_autoDetectWebSource(controller));
    }
  }

  bool _isDangerousWebUrl(String target) {
    final uri = Uri.tryParse(target);
    if (uri == null) return true;
    final raw = target.toLowerCase();
    if (raw == 'about:blank') return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return true;
    final host = uri.host.toLowerCase();
    final pathAndQuery = '${uri.path}?${uri.query}'.toLowerCase();
    return RegExp(
      r'(doubleclick|googlesyndication|googleadservices|adservice|adnxs|adsco\.re|betteradsystem|vacantazon|scogienaira|backsetaspises|taghas|inboxdollars|moolahsyangtze|wvdme|rtmark|ay267|adexchangerapid|adminmr|realmoneycasino|mormors|popads|popcash|propellerads|onclick|exoclick|juicyads|trafficjunky|adsterra|outbrain|taboola|mgid|criteo|scorecardresearch|popup|popunder|interstitial|clickunder|app-install|download-app|push-notification)',
      caseSensitive: false,
    ).hasMatch('$host $pathAndQuery') ||
        RegExp(
          r'(sms:|tel:|intent:|mailto:|market:|whatsapp:|telegram:|otp|one[- ]?time|verification|verify|passcode|pin|subscription|subscribe|phone|mobile|credit[- ]?card)',
          caseSensitive: false,
        ).hasMatch(raw);
  }

  bool _isAllowedWebNavigation(String target) {
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.hasScheme) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    return !_isDangerousWebUrl(target);
  }

  void _handleWebIntelligenceMessage(WebViewController controller, Map<dynamic, dynamic> decoded) {
    if (!identical(controller, _webController)) return;
    final type = decoded['type']?.toString() ?? '';
    if (type == 'manifest_fetched') {
      // لا نمرّر هذي الرسالة لـ _captureMessageWebContext — pageUrl فيها هو
      // رابط المانفست نفسه لا صفحة القناة، فلا نريده يستبدل سياق الترويسات.
      final requestId = decoded['requestId']?.toString() ?? '';
      final results = decoded['results'];
      String? winningText;
      if (results is List) {
        for (final entry in results) {
          if (entry is! Map) continue;
          final attemptText = entry['text']?.toString() ?? '';
          final mode = entry['mode']?.toString() ?? '?';
          final status = entry['status'];
          final error = entry['error']?.toString() ?? '';
          _slog(
            'MANIFEST_FETCH_ATTEMPT',
            'mode=$mode status=$status ok=${entry['ok']} length=${attemptText.length} error=$error',
          );
          if (winningText == null &&
              attemptText.isNotEmpty &&
              attemptText.contains('#EXTM3U')) {
            winningText = attemptText;
          }
        }
      }
      final completer = _pendingManifestFetches.remove(requestId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(winningText);
      }
      return;
    }
    _captureMessageWebContext(decoded);
    if (type == 'drm_detected') {
      _slog('DRM_DETECTED', 'system=${decoded['system']}');
      if (!mounted) return;
      setState(() {
        _webDrmDetected = true;
      });
      _webDetectorTimer?.cancel();
      _webDetectorTimer = null;
      _smartLog('PLAYER', 'DRM detected; keeping WebView authoritative');
      _setWebSessionState(_WebSessionState.drmWebOnly);
      return;
    }
    if (type == 'media_resource') {
      _webMediaResourceHits++;
      final rawResourceUrl = decoded['url']?.toString() ?? '';
      final resourceUrl = rawResourceUrl.toLowerCase();
      final segmentEvidence = RegExp(r'(^|[/._-])seg(?:ment)?[-_]?\d+|\.(ts|m4s)(?:$|[?#])').hasMatch(resourceUrl);
      _webMediaEvidenceScore = (_webMediaEvidenceScore + (segmentEvidence ? 22 : 12)).clamp(0, 100).toInt();
      _slog(
        'MEDIA_RESOURCE',
        'url=${_safeLogUrl(rawResourceUrl)} segmentEvidence=$segmentEvidence score=$_webMediaEvidenceScore hits=$_webMediaResourceHits',
      );
      if (_looksLikeHls(rawResourceUrl)) {
        _registerWebCandidate(
          rawResourceUrl,
          source: 'performance',
          evidenceScore: 20,
          pageUrl: decoded['pageUrl']?.toString(),
          frameUrl: decoded['frameUrl']?.toString(),
          referer: decoded['referer']?.toString(),
        );
      }
      _extendWebStartupDeadline(const Duration(seconds: 5));
      return;
    }
    if (type == 'videojs_player') {
      _webVideoJsPlayerMode = true;
      _webMediaEvidenceScore = (_webMediaEvidenceScore + 20).clamp(0, 100).toInt();
      _extendWebStartupDeadline(const Duration(seconds: 10));
      _smartLog('VIDEOJS', 'player detected');
      _slog('VIDEOJS_PLAYER_DETECTED', 'score=$_webMediaEvidenceScore');
      return;
    }
    // نفس فكرة كشف Video.js أعلاه لكن لمشغّل JWPlayer — بالخاصية (window.jwplayer
    // أو عناصر jw-*) لا باسم الموقع/الدومين، فيعمل مع أي موقع يستخدم JWPlayer
    // مهما كان دومينه (بدل الاعتماد فقط على قائمة دومينات Vidmoly المعروفة
    // بـ_isVidmolyPlayerUrl، اللي لا تغطي مواقع جديدة تُستورد لاحقاً).
    if (type == 'jwplayer_player') {
      _webVidmolyPlayerMode = true;
      _webMediaEvidenceScore = (_webMediaEvidenceScore + 20).clamp(0, 100).toInt();
      _extendWebStartupDeadline(const Duration(seconds: 10));
      _smartLog('JWPLAYER', 'player detected');
      _slog('JWPLAYER_PLAYER_DETECTED', 'score=$_webMediaEvidenceScore');
      return;
    }
    if (type == 'hls_candidate') {
      final rawUrl = decoded['url']?.toString().trim() ?? '';
      if (rawUrl.isNotEmpty) {
        _registerWebCandidate(
          rawUrl,
          source: decoded['source']?.toString() ?? 'network',
          mime: decoded['mime']?.toString(),
          evidenceScore: 25,
          pageUrl: decoded['pageUrl']?.toString(),
          frameUrl: decoded['frameUrl']?.toString(),
          referer: decoded['referer']?.toString(),
        );
        _webMediaEvidenceScore =
            (_webMediaEvidenceScore + 12).clamp(0, 100).toInt();
        _extendWebStartupDeadline(const Duration(seconds: 5));
        _smartLog('HLS', 'network candidate event received');
        _slog(
          'HLS_CANDIDATE_FROM_JS',
          'url=${_safeLogUrl(rawUrl)} source=${decoded['source']} mime=${decoded['mime']} score=$_webMediaEvidenceScore',
        );
      }
      return;
    }
    if (type == 'web_playback') {
      if (_webDrmDetected) return;
      final playing = decoded['playing'] == true;
      final ready = decoded['ready'] == true;
      final currentTime = (decoded['time'] as num?)?.toDouble() ?? 0;
      if (playing || (ready && currentTime > 0.15)) {
        if (playing) _webRealPlaybackConfirmed = true;
        _webMediaEvidenceScore = (_webMediaEvidenceScore + 25).clamp(0, 100).toInt();
        _webMediaResourceHits = (_webMediaResourceHits + 1).clamp(0, 1000);
        _extendWebStartupDeadline(const Duration(seconds: 8));
        if (playing || currentTime > 0.15) {
          _smartLog(
            'PLAYBACK',
            'web evidence: playing=$playing currentTime=${currentTime.toStringAsFixed(2)}',
          );
          _slog(
            'WEB_PLAYBACK_EVIDENCE',
            'playing=$playing ready=$ready currentTime=${currentTime.toStringAsFixed(2)} score=$_webMediaEvidenceScore',
          );
          // Do not switch UI on this event alone. The sentinel still needs
          // two snapshots, and the native gate still needs a validated source.
          unawaited(_confirmWebPlaybackAndKickDetection(controller));
        }
      }
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
    _slog(
      'IFRAME_CANDIDATE',
      'url=${_safeLogUrl(rawUrl)} score=$score shouldPromote=$shouldPromote interactionAttempts=$_webInteractionAttempts',
    );
    if (!shouldPromote) return;
    unawaited(_promoteIframeToPlayerDocument(controller, rawUrl, score));
  }

  Future<void> _confirmWebPlaybackAndKickDetection(
      WebViewController controller) async {
    if (!mounted ||
        !identical(controller, _webController) ||
        _webDrmDetected ||
        _webSessionState == _WebSessionState.nativePlaying) {
      return;
    }
    final proven = await _webPlaybackSentinel(controller);
    if (!mounted || !identical(controller, _webController) || !proven) return;
    _webPlaybackProven = true;
    await _showWebPlaybackReady(controller);
    if (!mounted || !identical(controller, _webController)) return;
    _smartLog('PLAYBACK', 'web playback proof passed');
    _kickWebDetection(controller);
  }

  Future<void> _promoteIframeToPlayerDocument(
      WebViewController controller, String iframeUrl, int score) async {
    if (!mounted || _webIframePromotionInFlight || _webIframePromotionAttempts >= 2 || _webPlaybackReady || _webDrmDetected) return;
    _slog('IFRAME_PROMOTE_START', 'url=${_safeLogUrl(iframeUrl)} score=$score attempt=${_webIframePromotionAttempts + 1}');
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
        if (proof || _webMediaEvidenceScore >= 60) {
          _slog('IFRAME_PROMOTE_CONFIRMED', 'url=${_safeLogUrl(iframeUrl)} proof=$proof score=$_webMediaEvidenceScore');
          return;
        }
        if (_webIframePromotionAttempts < 2 && parentUrl != null && parentUrl.isNotEmpty) {
          _slog('IFRAME_PROMOTE_TIMEOUT_REVERT', 'url=${_safeLogUrl(iframeUrl)} backTo=${_safeLogUrl(parentUrl)}');
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

  void _captureMessageWebContext(Map<dynamic, dynamic> decoded) {
    final rawPage = decoded['pageUrl']?.toString() ?? '';
    final page = Uri.tryParse(rawPage);
    if (page == null ||
        !page.hasScheme ||
        (page.scheme != 'http' && page.scheme != 'https')) {
      return;
    }
    final context = <String, String>{...?_webContextHeaders};
    final origin = _originForUri(page);
    if (origin.isNotEmpty) {
      context['origin'] = origin;
      // Cross-origin media requests use the page origin as their Referer
      // under the browser's strict-origin referrer policy. The candidate
      // helper below applies this same rule during native replay.
      context['referer'] = '$origin/';
    }
    final reportedReferer = decoded['referer']?.toString() ?? '';
    if (reportedReferer.startsWith('http') && reportedReferer == rawPage) {
      context['referer'] = reportedReferer;
    }
    if (mounted && context.isNotEmpty) _webContextHeaders = context;
  }

  String _originForUri(Uri uri) {
    if (!uri.hasScheme || uri.host.isEmpty) return '';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
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
             const raw = String(url || '').toLowerCase();
             if (!/^https?:$/i.test(u.protocol)) return true;
            return /(doubleclick|googlesyndication|googleadservices|adservice|adnxs|adsco\.re|betteradsystem|vacantazon|scogienaira|backsetaspises|taghas|inboxdollars|moolahsyangtze|wvdme|rtmark|ay267|adexchangerapid|adminmr|realmoneycasino|mormors|popads|popcash|propellerads|onclick|exoclick|juicyads|trafficjunky|adsterra|outbrain|taboola|mgid|criteo|scorecardresearch|app-install|push-notification)/i.test(`${h} ${p}`) ||
               /(popup|popunder|clickunder|interstitial|advertisement|ads?\b|otp|one[- ]?time|verification|verify|passcode|pin|subscription|subscribe|phone|mobile|credit[- ]?card|download-app)/i.test(`${p} ${u.search} ${raw}`);
          } catch (_) { return false; }
        };
         const playerLike = (el) => {
           try {
             return !!(el && el.closest && el.closest('video, audio, iframe, .video-js, .jwplayer, .jw-wrapper, .plyr, [class*="player" i], [id*="player" i]'));
           } catch (_) { return false; }
         };
          const humanChallenge = (el) => {
            try {
              if (!el) return false;
              if (el.matches && el.matches('iframe[src*="challenges.cloudflare.com" i],iframe[src*="hcaptcha.com" i],iframe[src*="recaptcha" i],.cf-turnstile,#cf-chl-widget,#challenge-form,#challenge-running,.g-recaptcha,.h-captcha')) return true;
              if (el.querySelector && el.querySelector('iframe[src*="challenges.cloudflare.com" i],iframe[src*="hcaptcha.com" i],iframe[src*="recaptcha" i],.cf-turnstile,#cf-chl-widget,#challenge-form,#challenge-running,.g-recaptcha,.h-captcha')) return true;
              const text = `${el.innerText || ''} ${el.textContent || ''}`.toLowerCase();
              return /verify you are human|checking your browser|complete the security check|verifying you are human|i'?m not a robot|prove you'?re human/.test(text);
            } catch (_) { return false; }
          };
         const sensitivePrompt = (el) => {
           try {
             const text = `${el && el.innerText || ''} ${el && el.textContent || ''} ${el && el.getAttribute && el.getAttribute('placeholder') || ''} ${el && el.getAttribute && el.getAttribute('name') || ''} ${el && el.getAttribute && el.getAttribute('autocomplete') || ''}`.toLowerCase();
             return /(otp|one[- ]?time|verification|verify|passcode|pin|sms|phone|mobile|رقم الهاتف|رمز|رسالة نصية|اشتراك|subscribe|subscription|install app|تنزيل التطبيق)/i.test(text);
           } catch (_) { return false; }
         };
         const adLike = (el) => {
           try {
             if (!el) return false;
             const text = `${el.id || ''} ${el.className || ''} ${el.getAttribute && el.getAttribute('role') || ''}`.toLowerCase();
             const style = getComputedStyle(el);
             const r = el.getBoundingClientRect ? el.getBoundingClientRect() : {width:0,height:0};
             return /(ad\b|ads\b|advert|popup|popunder|interstitial|overlay-ad|clickunder|modal|offer|subscribe|otp|verification)/i.test(text) ||
               (style.position === 'fixed' && r.width >= innerWidth * 0.55 && r.height >= innerHeight * 0.25);
           } catch (_) { return false; }
         };
         const hideUnsafePrompts = () => {
           try {
             document.querySelectorAll('form,input,button,a,[role="dialog"],[class*="popup" i],[id*="popup" i],[class*="advert" i],[id*="advert" i]').forEach((el) => {
               if (playerLike(el)) return;
                if (humanChallenge(el) || (el.closest && humanChallenge(el.closest('form,[role="dialog"],body')))) return;
               if (sensitivePrompt(el) || adLike(el)) {
                 el.setAttribute('data-sports-player-blocked-ad','1');
                 el.style.setProperty('display','none','important');
                 el.style.setProperty('pointer-events','none','important');
               }
             });
           } catch (_) {}
         };
        const report = (payload) => {
          try {
            if (window.SportsPlayerSource && window.SportsPlayerSource.postMessage) {
              window.SportsPlayerSource.postMessage(JSON.stringify(payload));
            }
          } catch (_) {}
        };
        const manifestText = (text) => /#EXTM3U|#EXT-X-(STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE)/i.test(String(text || '').slice(0, 12000));
        const reportManifest = (url, source, mime) => {
          if (!url || !/^https?:\/\//i.test(String(url))) return;
          report({
            type:'hls_candidate',
            url:String(url),
            source:source || 'manifest-response',
            mime:mime || 'application/vnd.apple.mpegurl',
            pageUrl:location.href,
            frameUrl:location.href,
            referer:document.referrer || location.href
          });
        };
        const addCandidate = (value, source='network', mime='') => {
          try {
            if (!value || typeof value !== 'string') return;
            const v = value.trim();
            if (!/^https?:\/\//i.test(v)) return;
            window.__sportsPlayerMediaCandidates = window.__sportsPlayerMediaCandidates || [];
            if (window.__sportsPlayerMediaCandidates.indexOf(v) === -1) {
              window.__sportsPlayerMediaCandidates.push(v);
            }
            if (/\.(m3u8|m3u)(?:$|[?#])/i.test(v) ||
                /(?:master|playlist|manifest|hls)(?:[.?&=\/]|$)/i.test(v)) {
              report({
                type:'hls_candidate',
                url:v,
                source,
                mime,
                pageUrl:location.href,
                frameUrl:location.href,
                referer:document.referrer || location.href
              });
            }
          } catch (_) {}
        };
         const reportPayloadCandidates = (value, source='response-json', depth=0) => {
           try {
             if (depth > 6 || value == null) return;
             if (typeof value === 'string') {
               const text = value.trim();
               if (/^https?:\/\//i.test(text)) {
                 addCandidate(text, source);
               } else if (/(m3u8|master|playlist|manifest|hls)/i.test(text)) {
                 try { addCandidate(new URL(text, location.href).toString(), source); } catch (_) {}
               }
               return;
             }
             if (Array.isArray(value)) {
               value.slice(0, 40).forEach((item) => reportPayloadCandidates(item, source, depth + 1));
               return;
             }
             if (typeof value === 'object') {
               Object.keys(value).slice(0, 80).forEach((key) => {
                 const item = value[key];
                 if (/^(url|src|source|file|stream|streamUrl|playUrl|hls|dash|mpd|m3u8|manifest|playlist|media|sources)$/i.test(key) ||
                     depth < 2) {
                   reportPayloadCandidates(item, source, depth + 1);
                 }
               });
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
           const href = link ? link.getAttribute('href') || '' : '';
           const target = link ? (link.getAttribute('target') || '').toLowerCase() : '';
           if ((link && (target === '_blank' || target === '_new' || blocked(href))) ||
               (el && !playerLike(el) && (sensitivePrompt(el) || adLike(el)))) {
            e.preventDefault(); e.stopPropagation();
             if (e.stopImmediatePropagation) e.stopImmediatePropagation();
          }
        }, true);
         document.addEventListener('touchstart', (e) => {
           let el = e.target;
           if (el && el.nodeType === 3) el = el.parentElement;
           if (el && !playerLike(el) && (sensitivePrompt(el) || adLike(el))) {
             e.preventDefault(); e.stopPropagation();
             if (e.stopImmediatePropagation) e.stopImmediatePropagation();
           }
         }, {capture:true, passive:false});
        const style = document.createElement('style');
        style.id = 'sports-player-ad-cleanup';
          style.textContent = `[id*=\"popup\" i],[class*=\"popup\" i],[id*=\"popunder\" i],[class*=\"popunder\" i],[id*=\"advert\" i],[class*=\"advert\" i],[id*=\"adsbox\" i],[class*=\"adsbox\" i],[class*=\"overlay-ad\" i],[class*=\"interstitial\" i],[id*=\"otp\" i],[class*=\"otp\" i],[id*=\"verification\" i],[class*=\"verification\" i],[id*=\"subscribe\" i],[class*=\"subscribe\" i]{display:none!important;visibility:hidden!important;pointer-events:none!important;} iframe[src*=\"challenges.cloudflare.com\" i],iframe[src*=\"hcaptcha.com\" i],iframe[src*=\"recaptcha\" i],.cf-turnstile,#cf-chl-widget,#challenge-form,#challenge-running,.g-recaptcha,.h-captcha{display:block!important;visibility:visible!important;pointer-events:auto!important;}`;
        (document.head || document.documentElement).appendChild(style);
         hideUnsafePrompts();
         try { new MutationObserver(() => hideUnsafePrompts()).observe(document.documentElement || document, {subtree:true, childList:true, attributes:true, attributeFilter:['class','id','href','action','placeholder','name']}); } catch (_) {}

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
            if (/(doubleclick|googlesyndication|adservice|adnxs|adsco\.re|betteradsystem|vacantazon|scogienaira|backsetaspises|taghas|inboxdollars|moolahsyangtze|wvdme|rtmark|ay267|adexchangerapid|adminmr|realmoneycasino|mormors|popads|popcash|propellerads|exoclick|juicyads|trafficjunky|adsterra|popup|popunder|clickunder|interstitial)/i.test(text)) return;
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
        // مؤكَّد بسجل تشخيص فعلي (موقع مليء بإعلانات/تتبّع): إيجابيات كاذبة
        // حقيقيتان بهذا الفحص كانتا تخدعان النظام بالكامل ليعتقد أن تشغيلاً
        // حقيقياً أثبت نفسه خلال ثوانٍ من فتح الصفحة، رغم عدم وجود أي فيديو
        // بعد: (أ) روابط favicon من جوجل (`s2.googleusercontent.com/s2/
        // favicons?domain_url=...`) تضمّن رابط الصفحة نفسها بمعامل الاستعلام
        // — لصفحة مسلسل/حلقة هذا يحتوي غالباً كلمات "video"/"watch" فيُطابق
        // فحص الكلمات المفتاحية رغم إنه مجرد طلب أيقونة صغيرة. (ب) روابط
        // إعلانات كازينو حقيقية (`.../content/stream/agl/....gif`) تحتوي
        // كلمة "stream" بمسارها التسويقي (لا علاقة له بالبث)، فتُطابَق أيضاً.
        // النتيجة الفعلية المرصودة: _webMediaEvidenceScore وصل 100 خلال أقل
        // من 10 ثوانٍ من مجرد تحميل أيقونات وإعلانات، قبل حتى محاولة اكتشاف
        // أي مشغّل حقيقي — وهذا "الدليل" الكاذب يُسكِت آلية النقر التلقائي
        // (`_webInteractionAttempts` بـwatch_screen_discovery.dart، الشرط
        // `!await _webPlaybackSentinel(...)`) طوال الجلسة، فلا يُنقَر أي زر
        // سيرفر تلقائياً إطلاقاً على مواقع بهذا الشكل. الحل: (أ) فحص الكلمات
        // المفتاحية يتجاهل معامل الاستعلام كلياً الآن (نطاق+مسار فقط، لا
        // `search`) — رابط favicon يحمل الصفحة كاملة بمعامل استعلام لا يعود
        // يُطابَق. (ب) أي مورد نوعه الحقيقي (`initiatorType`) صورة/ستايل/خط
        // (`img`/`css`/`link`) أو امتداده صورة/خط معروف يُستبعَد قبل أي فحص
        // كلمات مفتاحية إطلاقاً — شريحة/قائمة تشغيل حقيقية لا تُحمَّل أبداً
        // بهذي الأنواع.
        const mediaResourceLike = (url, initiatorType) => {
          try {
            if (/^(img|css|link)$/i.test(initiatorType || '')) return false;
            const u = new URL(url, location.href);
            const pathOnly = `${u.hostname} ${u.pathname}`.toLowerCase();
            if (/\.(jpe?g|png|gif|webp|bmp|svg|ico|woff2?|ttf|eot|otf)(?:$|[?#])/i.test(pathOnly)) return false;
            if (/(doubleclick|googlesyndication|google-analytics|mc\.yandex|scorecardresearch|adservice|ads\b|adsco\.re|betteradsystem|vacantazon|scogienaira|backsetaspises|taghas|inboxdollars|moolahsyangtze|wvdme|rtmark|ay267|adexchangerapid|adminmr|realmoneycasino|mormors|beacon|telemetry|metrics|pixel|collect|favicon)/i.test(pathOnly)) return false;
            return /\.(m3u8|mpd|mp4|m4v|webm|mov|m4s|ts)(?:$|[?#])/i.test(pathOnly) ||
              /(?:manifest|playlist|master|stream|video|media|segment|seg-|chunk|hls2|dash|\/v\/|\/m3\/)/i.test(pathOnly);
          } catch (_) { return false; }
        };
        const reportMediaResources = () => {
          try {
            performance.getEntriesByType('resource').forEach((e) => {
              const name = e && e.name ? String(e.name) : '';
              if (!mediaResourceLike(name, e && e.initiatorType)) return;
              report({type:'media_resource', url:name});
              if (/\.(m3u8|m3u)(?:$|[?#])/i.test(name) ||
                  /(?:master|playlist|manifest)(?:[./?#&]|$)|\/m3\//i.test(name)) {
                report({type:'hls_candidate', url:name, source:'performance',
                  mime:e.initiatorType || '', pageUrl:location.href,
                  frameUrl:location.href, referer:document.referrer || location.href});
              }
            });
          } catch (_) {}
        };
        reportMediaResources();
        try { setInterval(reportMediaResources, 1800); } catch (_) {}

        // Video.js intelligence: some hosts expose the master only after the
        // player instance is created or after Play. Inspect the public player
        // API and registry repeatedly instead of trusting one DOM selector.
        try {
           const addVideoJsSource = (value, source='videojs') => {
             try {
               if (!value) return;
               if (typeof value === 'object') {
                 if (typeof value.src === 'function') addVideoJsSource(value.src(), source);
                 if (typeof value.currentSrc === 'function') addVideoJsSource(value.currentSrc(), source);
                 if (typeof value.currentSource === 'function') addVideoJsSource(value.currentSource(), source);
                 if (typeof value.currentSources === 'function') addVideoJsSource(value.currentSources(), source);
                 if (Array.isArray(value)) { value.slice(0,40).forEach(v => addVideoJsSource(v, source)); return; }
                 Object.keys(value).slice(0,80).forEach(k => {
                   if (/^(src|source|sources|url|file|playlist|hls|m3u8|manifest)$/i.test(k)) addVideoJsSource(value[k], source);
                 });
                 return;
               }
               const v = String(value).trim();
               if (!/^https?:\/\//i.test(v)) return;
               addCandidate(v, source);
               if (/\.(m3u8|m3u)(?:$|[?#])/i.test(v) || /(?:master|playlist|manifest|hls)(?:[?&=\/]|$)/i.test(v)) {
                 report({type:'hls_candidate', url:v, source, mime:'application/vnd.apple.mpegurl'});
               }
             } catch (_) {}
           };
           const inspectVideoJsPlayers = () => {
             try {
               const players = [];
               if (window.videojs) {
                 if (typeof window.videojs.getPlayers === 'function') players.push(...Object.values(window.videojs.getPlayers() || {}));
                 if (typeof window.videojs.getAllPlayers === 'function') players.push(...(window.videojs.getAllPlayers() || []));
                 document.querySelectorAll('.video-js,[data-setup],video[id]').forEach((el) => {
                   try {
                     const p = window.videojs.getPlayer ? window.videojs.getPlayer(el.id || el) : window.videojs(el.id || el);
                     if (p) players.push(p);
                   } catch (_) {}
                 });
               }
               players.forEach((p) => {
                 addVideoJsSource(p, 'videojs-api');
                 try { if (typeof p.tech === 'function') addVideoJsSource(p.tech(true), 'videojs-tech'); } catch (_) {}
               });
             } catch (_) {}
           };
          const detectVideoJs = () => {
            try {
              const text = `${document.documentElement?.innerHTML || ''} ${Array.from(document.scripts || []).map(s => s.src || s.textContent || '').join(' ')}`;
               const hasVideoJs = !!window.videojs || !!document.querySelector('.video-js,[data-setup]') ||
                 /video-js|videojs|video\.min\.js|videojs-contrib-quality-levels|videojs-hls-quality-selector/i.test(text);
               const hasVideo = !!document.querySelector('video,.video-js,[data-setup]');
               if (hasVideoJs && hasVideo) {
                 inspectVideoJsPlayers();
                 report({type:'videojs_player', initialized:!!window.videojs, hasVideo:true});
               }
            } catch (_) {}
          };
          detectVideoJs();
           setInterval(detectVideoJs, 900);
        } catch (_) {}

        // JWPlayer intelligence: same idea as the Video.js block above, but
        // detected by feature (window.jwplayer / jw-* markup) instead of by
        // domain, so any site running JWPlayer gets the same treatment —
        // not just the small list of hosts _isVidmolyPlayerUrl knows about.
        try {
          const detectJwPlayer = () => {
            try {
              const text = `${document.documentElement?.innerHTML || ''} ${Array.from(document.scripts || []).map(s => s.src || s.textContent || '').join(' ')}`;
              const hasJwPlayer = !!window.jwplayer || !!document.querySelector('.jwplayer,.jw-wrapper,.jw-video,[id*="jwplayer" i],[class*="jwplayer" i]') ||
                /jwplayer|jwplatform|jwpsrv/i.test(text);
              const hasVideo = !!document.querySelector('video,.jwplayer,.jw-wrapper');
              if (hasJwPlayer && hasVideo) {
                report({type:'jwplayer_player', initialized:!!window.jwplayer, hasVideo:true});
              }
            } catch (_) {}
          };
          detectJwPlayer();
          setInterval(detectJwPlayer, 900);
        } catch (_) {}

        // Playback heartbeat: a large class of embedded players use MSE,
        // MediaSource blobs, canvas overlays, or framework wrappers where
        // URL-based discovery is insufficient. Observe the real HTML5 media
        // element and report it as soon as the browser has actually started
        // playback. This also catches playback that began from a genuine user
        // tap before our next polling cycle.
        const playbackSeen = new WeakSet();
        const inspectPlayback = () => {
          try {
            document.querySelectorAll('video,audio').forEach((v) => {
              if (!v) return;
              const reportState = () => {
                try {
                  const ready = v.readyState >= 2;
                  const playing = !v.paused && !v.ended && ready;
                  const time = Number(v.currentTime || 0);
                   addCandidate(v.currentSrc || v.src || '', 'video-event');
                   if (window.videojs) {
                     try {
                       const p = v.id && window.videojs.getPlayer ? window.videojs.getPlayer(v.id) : null;
                       if (p) {
                         if (typeof p.currentSrc === 'function') addCandidate(p.currentSrc(), 'videojs-currentSrc');
                         if (typeof p.src === 'function') {
                           const source = p.src();
                           if (typeof source === 'string') addCandidate(source, 'videojs-src');
                           else if (Array.isArray(source)) source.forEach(item => {
                             if (item && typeof item.src === 'string') addCandidate(item.src, 'videojs-src');
                           });
                         }
                       }
                     } catch (_) {}
                   }
                  if (playing || ready || time > 0.15) {
                    report({type:'web_playback', playing, ready, time, src:(v.currentSrc || v.src || '')});
                  }
                } catch (_) {}
              };
              if (!playbackSeen.has(v)) {
                playbackSeen.add(v);
                   ['play','playing','timeupdate','canplay','loadedmetadata','loadeddata','durationchange'].forEach((name) => {
                  try { v.addEventListener(name, reportState, {passive:true}); } catch (_) {}
                });
              }
              reportState();
            });
          } catch (_) {}
        };
        inspectPlayback();
        try { setInterval(inspectPlayback, 450); } catch (_) {}

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
              try { addCandidate(typeof input === 'string' ? input : (input && input.url), 'fetch'); } catch (_) {}
              return originalFetch.apply(this, arguments).then((response) => {
                try { addCandidate(response && response.url, 'fetch-response'); } catch (_) {}
                const responseUrl = response && response.url ? response.url : (typeof input === 'string' ? input : '');
                const responseMime = response && response.headers ? (response.headers.get('content-type') || '') : '';
                if (/mpegurl/i.test(responseMime)) {
                  reportManifest(responseUrl, 'fetch-content-type', responseMime);
                }
                 try {
                   const copy = response.clone();
                   copy.text().then((text) => {
                     if (!text) return;
                     if (manifestText(text)) {
                       reportManifest(responseUrl, 'fetch-manifest', responseMime);
                     } else {
                       try { reportPayloadCandidates(JSON.parse(text), 'fetch-json'); } catch (_) {}
                     }
                   }).catch(() => {});
                 } catch (_) {}
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
               const result = originalOpen.apply(this, arguments);
               try {
                 addCandidate(url, 'xhr');
                 this.addEventListener('load', () => {
                   try {
                     const responseUrl = this.responseURL || url || '';
                     const responseMime = this.getResponseHeader('content-type') || '';
                     if (typeof this.responseText === 'string' && this.responseText) {
                       if (manifestText(this.responseText)) {
                         reportManifest(responseUrl, 'xhr-manifest', responseMime);
                       } else {
                         reportPayloadCandidates(JSON.parse(this.responseText), 'xhr-json');
                       }
                       return;
                     }
                     // بعض مواقع الأفلام تطلب responseType=arraybuffer/blob عمداً
                     // حتى لا يستطيع أي فاحص بسيط قراءة this.responseText مباشرة.
                     // نفك ترميز البايتات هنا كنص UTF-8 ونطبّق نفس فحص #EXTM3U.
                     if (this.response instanceof ArrayBuffer) {
                       const text = new TextDecoder('utf-8').decode(this.response);
                       if (manifestText(text)) {
                         reportManifest(responseUrl, 'xhr-manifest-buffer', responseMime);
                       }
                     } else if (this.response instanceof Blob) {
                       this.response.text().then((text) => {
                         if (manifestText(text)) {
                           reportManifest(responseUrl, 'xhr-manifest-blob', responseMime);
                         }
                       }).catch(() => {});
                     }
                   } catch (_) {}
                 });
               } catch (_) {}
               return result;
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
              /(?:m3u8|manifest|playlist|master|stream|live|hls)(?:[.?&=\/]|$)/i.test(l) ||
              /\/m3\//i.test(l)) out.add(v);
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

  int _scoreDetectedSource(String url) => CandidateScoring.scoreDetectedSource(url);

  bool _looksLikeHls(String url) => CandidateScoring.looksLikeHls(url);
  bool _looksLikeProgressiveVideo(String url) => CandidateScoring.looksLikeProgressiveVideo(url);

  /// يطلب من WebView نفسه (بجلسته وكوكيزه الحقيقية) يجيب محتوى رابط نصياً
  /// عبر fetch()، ويرجعه لنا هنا. ضروري لأن evaluateJavascript لا ينتظر
  /// اكتمال Promise، فنستخدم نفس قناة الرسائل الموجودة (SportsPlayerSource)
  /// بدل انتظار نتيجة مباشرة من runJavaScriptReturningResult.
  ///
  /// يجرّب أولاً بدون كوكيز (credentials:'omit'): أغلب CDNs التي تستضيف
  /// المانفست على نطاق مختلف عن صفحة اللاعب (مثل هذه الحالة تحديداً) ترسل
  /// `Access-Control-Allow-Origin: *`، وهذا يتعارض تماماً مع أي طلب يحمل
  /// كوكيز (credentials:'include') حسب مواصفة CORS نفسها — فيفشل الطلب
  /// صامتاً حتى لو كان مشغّل الصفحة نفسه (hls.js/video.js) قد جلب نفس
  /// الرابط بنجاح للتو بدون كوكيز. لو فشلت المحاولة الأولى، نجرّب
  /// بكوكيز (لحالة العكس: مانفست محمي بجلسة وليس عبر أصل مختلف).
  /// كل محاولة تُسجَّل بسبب فشلها الفعلي (حالة HTTP أو رسالة الخطأ) بدل
  /// فشل صامت واحد لا يوضّح شيئاً — انظر MANIFEST_FETCH_ATTEMPT بالسجل.
  Future<String?> _fetchTextViaWebView(String url,
      {Duration timeout = const Duration(seconds: 12)}) async {
    final controller = _webController;
    if (controller == null) return null;
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    final completer = Completer<String?>();
    _pendingManifestFetches[requestId] = completer;
    try {
      final urlJson = jsonEncode(url);
      final requestIdJson = jsonEncode(requestId);
      await controller.runJavaScript('''(function() {
        function attempt(mode) {
          return fetch($urlJson, {credentials: mode}).then(function(res) {
            return res.text().then(function(text) {
              return {text: text, status: res.status, ok: res.ok, mode: mode, error: ''};
            });
          }).catch(function(err) {
            return {text: '', status: 0, ok: false, mode: mode, error: (err && err.message) ? String(err.message) : String(err)};
          });
        }
        attempt('omit').then(function(first) {
          if (first.ok && first.text && first.text.indexOf('#EXTM3U') !== -1) return [first];
          return attempt('include').then(function(second) { return [first, second]; });
        }).then(function(results) {
          try {
            if (window.SportsPlayerSource && window.SportsPlayerSource.postMessage) {
              window.SportsPlayerSource.postMessage(JSON.stringify({type:'manifest_fetched', requestId:$requestIdJson, results: results}));
            }
          } catch (_) {}
        });
      })();''');
    } catch (_) {
      _pendingManifestFetches.remove(requestId);
      return null;
    }
    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      _pendingManifestFetches.remove(requestId);
      return null;
    }
  }

  /// عندما يفشل رابط HLS بالتشغيل الأصلي رغم ثقة عالية بأنه المصدر الصحيح
  /// (عادة خطأ "Source error" من ExoPlayer)، الاحتمال الأقوى أن نقطة
  /// الحماية (جلسة/توكن/بصمة اتصال) خاصة بهذا الرابط بالذات، وليست شيئاً
  /// WebView يحمله تلقائياً معه فقط (زي الكوكيز العادية اللي عالجناها في
  /// _headersForCandidate). بدل إعادة نفس المحاولة الفاشلة، نطلب من
  /// WebView نفسه — المُثبَت نجاحه بتشغيل هذا الفيديو فعلياً — يجيب محتوى
  /// الرابط بجلسته الحقيقية، ثم:
  /// - لو "master playlist" (فيها عدة جودات عبر #EXT-X-STREAM-INF): نرجّع
  ///   كل روابط الجودات المكتشفة (الأعلى جودة أولاً) لنجرّبها ونعرضها.
  /// - لو "media playlist" (فيها السيجمنتات مباشرة عبر #EXTINF): نكتبها
  ///   كملف محلي مؤقت (بروابط مطلقة)، فيقرأ ExoPlayer القائمة من الملف
  ///   المحلي دون أي طلب لرابط الحماية إطلاقاً، ولا يطلب شبكياً إلا ملفات
  ///   السيجمنت نفسها (غالباً غير محمية بنفس القوة).
  Future<_RelayedManifest?> _relayManifestViaWebView(String manifestUrl) async {
    final text = await _fetchTextViaWebView(manifestUrl);
    if (text == null || !text.contains('#EXTM3U')) return null;

    final lines = text.split(RegExp(r'\r?\n'));

    if (text.contains('#EXT-X-STREAM-INF')) {
      // (ترتيب الفرز, الدقة/التسمية, الرابط) — الفرز يعتمد BANDWIDTH لأنه
      // موجود دائماً بينما RESOLUTION اختياري بالمواصفة.
      final variants = <(int, String, String)>[];
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i]);
        final bandwidth = int.tryParse(bwMatch?.group(1) ?? '') ?? 0;
        final resMatch = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(lines[i]);
        final height = resMatch?.group(1);
        var j = i + 1;
        while (j < lines.length && lines[j].trim().isEmpty) {
          j++;
        }
        if (j >= lines.length) continue;
        final urlLine = lines[j].trim();
        if (urlLine.isEmpty || urlLine.startsWith('#')) continue;
        final label = height != null
            ? '${height}p'
            : (bandwidth > 0 ? '${(bandwidth / 1000).round()} kbps' : 'تلقائي');
        variants.add((bandwidth, label, _resolveRelativeUrl(urlLine, manifestUrl)));
      }
      if (variants.isEmpty) return null;
      variants.sort((a, b) => b.$1.compareTo(a.$1));
      final seen = <String>{};
      final ordered = <MapEntry<String, String>>[];
      for (final v in variants) {
        if (seen.add(v.$3)) ordered.add(MapEntry(v.$2, v.$3));
      }
      return _RelayedManifest.variants(ordered);
    }

    if (!text.contains('#EXTINF')) return null;
    final rewritten = lines.map((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) return line;
      return _resolveRelativeUrl(trimmed, manifestUrl);
    }).join('\n');
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/relayed_manifest_${DateTime.now().microsecondsSinceEpoch}.m3u8');
      await file.writeAsString(rewritten);
      return _RelayedManifest.localFile(file);
    } catch (_) {
      return null;
    }
  }

  // حارس أخير قبل أي محاولة تشغيل أصلي: صور الغلاف (poster/thumbnail) أو
  // ملفات أصول الصفحة (css/js/خطوط) قد تتسرب أحياناً لقائمة المرشحين عبر
  // فحص إعدادات المشغلات (JWPlayer/Video.js تحتوي غالباً حقل "image" بجانب
  // "sources")، فتحصل على نقاط ترجيح "مصدر من إطار عمل معروف" رغم إنها
  // ليست فيديو إطلاقاً. هذا الفحص يرفضها بغض النظر عن أي نقاط ترجيح أخرى.
  bool _isNonMediaAsset(String url) => CandidateScoring.isNonMediaAsset(url);

  Future<Map<String, String>> _headersForCandidate(
      String source, _WebNetworkCandidate? candidate) async {
    final headers = <String, String>{..._effectiveStreamHeaders()};
    final sourceUri = Uri.tryParse(source);
    final pageUri = Uri.tryParse(candidate?.pageUrl ?? '');
    if (sourceUri != null &&
        pageUri != null &&
        sourceUri.hasScheme &&
        pageUri.hasScheme &&
        pageUri.host.isNotEmpty) {
      final sourcePort = sourceUri.hasPort ? sourceUri.port : null;
      final pagePort = pageUri.hasPort ? pageUri.port : null;
      final sameOrigin = sourceUri.scheme == pageUri.scheme &&
          sourceUri.host.toLowerCase() == pageUri.host.toLowerCase() &&
          sourcePort == pagePort;
      if (!sameOrigin) {
        final pageOrigin = _originForUri(pageUri);
        if (pageOrigin.isNotEmpty) {
          headers['origin'] = pageOrigin;
          headers['referer'] = '$pageOrigin/';
        }
      }
    }

    // document.cookie (المصدر الحالي لـ headers['cookie'] عبر
    // _webContextHeaders) لا يرى كوكيز الجلسة المعلَّمة HttpOnly. نقرأها
    // هنا من مدير كوكيز WebView الأصلي لنفس دومين المصدر تحديداً (قد يكون
    // دوميناً مختلفاً عن صفحة القناة نفسها، مثل CDN بث منفصل)، ونستبدل بها
    // أي قيمة أضعف مأخوذة من جافاسكربت.
    if (sourceUri != null && sourceUri.hasScheme) {
      final nativeCookie = await NativeCookieService.getCookie(source);
      if (nativeCookie != null && nativeCookie.isNotEmpty) {
        headers['cookie'] = nativeCookie;
      }
    }
    return headers;
  }

  // بعد فشل تجربة تشغيل أصلي، ExoPlaybackException تعطي رسالة عامة جداً
  // ("Source error") بلا أي تفصيل حقيقي (403؟ استجابة فارغة؟ صفحة HTML
  // بدل مانفست حقيقي؟ توكن منتهي؟) — والسبب الحقيقي غالباً غير قابل
  // للتشخيص من سجل نصي وحده، يحتاج logcat الجهاز فعلياً. هذا الفحص يطلب
  // نفس الرابط بنفس الترويسات اللي استخدمها ExoPlayer، مباشرة بعد الفشل
  // (بفارق أقل من ثانية، حتى لا يفوّت رابطاً موقّتاً قصير الأجل)، ويسجّل
  // حالة HTTP الفعلية ونوع المحتوى وأول جزء من الجسم — بدون أي حاجة
  // لـ logcat لاحقاً. تشغيله بالخلفية (unawaited) حتى لا يؤخر محاولة
  // الإنقاذ عبر WebView التي تأتي بعده مباشرة وحساسة للتوقيت.
  Future<void> _logNativeFailureDiagnostics(
      String url, Map<String, String>? playbackHeaders) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
      final headers = <String, String>{
        ...(playbackHeaders ?? _effectiveStreamHeaders()),
        // نكتفي بأول 2 كيلوبايت — يكفي لمعرفة هل الرد مانفست/سيجمنت حقيقي
        // أو صفحة خطأ، بدون تحميل الملف كاملاً لمجرد التشخيص.
        'range': 'bytes=0-2047',
      };
      final stopwatch = Stopwatch()..start();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
      stopwatch.stop();
      final contentType = (response.headers['content-type'] ?? '').toLowerCase();
      final looksTextual = contentType.isEmpty ||
          contentType.contains('text') ||
          contentType.contains('json') ||
          contentType.contains('mpegurl') ||
          contentType.contains('xml');
      String snippet;
      if (looksTextual) {
        final text = response.body;
        snippet = text
            .substring(0, text.length.clamp(0, 200))
            .replaceAll('\n', ' ')
            .replaceAll('\r', '');
      } else {
        snippet = '<binary ${response.bodyBytes.length} bytes>';
      }
      _slog(
        'NATIVE_TRIAL_DIAGNOSTIC',
        'url=${_safeLogUrl(url)} status=${response.statusCode} contentType=$contentType '
        'contentLength=${response.headers['content-length'] ?? response.bodyBytes.length} '
        'latencyMs=${stopwatch.elapsedMilliseconds} snippet="$snippet"',
      );
    } catch (e) {
      _slog('NATIVE_TRIAL_DIAGNOSTIC_FAILED', 'url=${_safeLogUrl(url)} error=$e');
    }
  }

  Future<bool> _validatePublicMediaSource(String url,
      {Map<String, String>? requestHeaders}) async {
    try {
      final uri = Uri.parse(url);
      final headers = <String, String>{
        'user-agent': _headers?['user-agent'] ?? 'Mozilla/5.0 (Android) AppleWebKit/537.36 Chrome/131 Mobile Safari/537.36',
        'accept': '*/*',
        ...?_webContextHeaders,
        ...?_resolvedStreamHeaders,
        ...?requestHeaders,
      };
      if (_looksLikeHls(url)) {
        final response = await _streamNetworkClient.get(uri,
            headers: headers, timeout: const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) return false;
        final body = response.body;
        return RegExp(r'#EXTM3U', caseSensitive: false).hasMatch(body) ||
            RegExp(r'#EXT-X-(STREAM-INF|TARGETDURATION|MEDIA-SEQUENCE)', caseSensitive: false).hasMatch(body);
      }
      if (_looksLikeProgressiveVideo(url)) {
        try {
          final response = await _streamNetworkClient.head(uri,
              headers: headers, timeout: const Duration(seconds: 6));
          if (response.statusCode >= 200 && response.statusCode < 400) {
            final type = (response.headers['content-type'] ?? '').toLowerCase();
            if (type.isEmpty || type.startsWith('video/') || type.contains('octet-stream')) return true;
          }
        } catch (_) {}
        // Some CDNs reject HEAD (405) while allowing normal media requests.
        try {
          final rangeHeaders = <String, String>{...headers, 'range': 'bytes=0-1023'};
          final response = await _streamNetworkClient.get(uri,
              headers: rangeHeaders, timeout: const Duration(seconds: 8));
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
        final response = await _streamNetworkClient.get(uri,
            headers: headers, timeout: const Duration(seconds: 8));
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
          // نفس إصلاح mediaResourceLike أعلى بالملف (مسافة الأسماء JS
          // منفصلة هنا لأن هذا الحقن مستقل، لكن نفس فئة الإيجابية الكاذبة
          // بالضبط — راجع تعليقها لسبب استبعاد search/الصور): يتجاهل معامل
          // الاستعلام (رابط favicon يحمل صفحة الحلقة كاملة به) ويستبعد
          // موارد الصور/الأيقونات صراحة (initiatorType أو الامتداد).
          performance.getEntriesByType('resource').forEach((e) => {
            if (/^(img|css|link)$/i.test(e.initiatorType || '')) return;
            let pathOnly = '';
            try {
              const u = new URL(e.name || '', location.href);
              pathOnly = `${u.hostname} ${u.pathname}`.toLowerCase();
            } catch (_) { return; }
            if (/\.(jpe?g|png|gif|webp|bmp|svg|ico|woff2?|ttf|eot|otf)(?:$|[?#])/.test(pathOnly)) return;
            if (/(doubleclick|googlesyndication|google-analytics|mc\.yandex|adservice|adsco\.re|betteradsystem|vacantazon|scogienaira|backsetaspises|taghas|inboxdollars|moolahsyangtze|wvdme|rtmark|ay267|adexchangerapid|adminmr|realmoneycasino|mormors|beacon|telemetry|metrics|pixel|collect|favicon)/.test(pathOnly)) return;
            if (/\.(m3u8|mpd|mp4|m4v|webm|mov|m4s|ts)(?:$|[?#])/.test(pathOnly) || /(?:manifest|playlist|master|stream|video|media|segment|seg-|chunk|hls2|dash|\/v\/|\/m3\/)/.test(pathOnly)) {
              mediaHits++; lastMedia = e.name;
            }
          });
        } catch (_) {}
        return JSON.stringify({found:!!v, playing:!!(v && !v.paused && v.readyState >= 2), time:Number(v && v.currentTime || 0), duration, seekable, src:v ? (v.currentSrc || v.src || '') : '', mediaHits, lastMedia});
      })();''');
      final decoded = _decodeJavaScriptResult(result);
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
      // تسجيل تشخيصي جديد: "الدليل" هنا شبكي بحت (عدد موارد متزايد) لا
      // تشغيل فعلي مُلاحَظ — لو ظهر هذا التاغ بسجل تالٍ بلا أي
      // WEB_PLAYBACK_EVIDENCE مقابل خلال نفس الجلسة، فهذا تأكيد أن الصفحة
      // أُعلنت "جاهزة" اعتماداً على ضجيج شبكي فقط بينما عنصر <video> نفسه
      // لم يُلاحَظ يشتغل إطلاقاً (راجع الحقل found: لو false فالعنصر غير
      // مرئي أصلاً لجافاسكربت المُحقَن، مرشّح قوي لـ<video> داخل iframe
      // من أصل مختلف لا نقدر نصل له).
      if (secondHits >= firstHits + 2 || secondHits >= 5) {
        _webMediaEvidenceScore = (_webMediaEvidenceScore + 20).clamp(0, 100).toInt();
        _slog('WEB_PLAYBACK_PROOF_NETWORK_ONLY',
            'reason=hits_growing found=${first['found']} playing=${first['playing']} firstHits=$firstHits secondHits=$secondHits');
        return true;
      }
      if (_webMediaEvidenceScore >= 70 && _webMediaResourceHits >= 4) {
        _slog('WEB_PLAYBACK_PROOF_NETWORK_ONLY',
            'reason=score_threshold found=${first['found']} playing=${first['playing']} score=$_webMediaEvidenceScore hits=$_webMediaResourceHits');
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _findBestIframeCandidate(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(r'''(() => {
        const bad = /(doubleclick|googlesyndication|googleadservices|adservice|adnxs|ay267|adexchangerapid|adminmr|realmoneycasino|mormors|popads|popcash|propellerads|exoclick|juicyads|trafficjunky|adsterra|outbrain|taboola|mgid|criteo|scorecardresearch|popup|popunder|clickunder|interstitial)/i;
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
      final decoded = _decodeJavaScriptResult(result);
      if (decoded == null || decoded == 'null') return null;
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
      final text = result is String ? result : result.toString();
      if (text.contains('clicked') && text.contains('true')) {
        _smartLog('PLAY', 'safe play control dispatched');
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
        const nonMediaAsset = /\.(jpe?g|png|gif|webp|bmp|svg|ico|css|woff2?|ttf|eot|otf|json|swf|wasm)(?:$|[?#])/i;
        const addDeep = (value, depth=0) => {
          if (depth > 5 || value == null) return;
          if (typeof value === 'string') {
            const trimmed = value.trim();
            // "sources"/"file" objects also commonly carry a sibling "image"/
            // "poster" thumbnail field. A blanket "any https:// string" match
            // was sweeping those in too — they are never a playable source.
            if (nonMediaAsset.test(trimmed)) return;
            if (/^https?:\/\//i.test(trimmed) || /\.(m3u8|mpd|mp4|m4v|webm|mov)(?:$|[?#])/i.test(trimmed)) add(value);
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
             try {
               const registry = typeof window.videojs.getPlayers === 'function'
                 ? window.videojs.getPlayers()
                 : (typeof window.videojs.getAllPlayers === 'function' ? window.videojs.getAllPlayers() : null);
               const players = Array.isArray(registry) ? registry : Object.values(registry || {});
               players.forEach((p) => {
                 try {
                   if (typeof p.currentSrc === 'function') add(p.currentSrc());
                   if (typeof p.src === 'function') addDeep(p.src());
                   if (typeof p.currentSource === 'function') addDeep(p.currentSource());
                   if (typeof p.currentSources === 'function') addDeep(p.currentSources());
                   if (typeof p.tech === 'function') addDeep(p.tech(true));
                 } catch (_) {}
               });
             } catch (_) {}
            document.querySelectorAll('.video-js, video[id]').forEach(el => {
               try {
                 const p = window.videojs.getPlayer ? window.videojs.getPlayer(el.id || el) : window.videojs(el.id || el);
                 if (p) {
                   addDeep(p);
                   if (typeof p.currentSrc === 'function') add(p.currentSrc());
                   if (typeof p.src === 'function') addDeep(p.src());
                   if (typeof p.currentSource === 'function') addDeep(p.currentSource());
                 }
               } catch (_) {}
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
      final text = result is String ? result : result.toString();
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
      final decoded = _decodeJavaScriptResult(result);
      return decoded is Map && decoded['detected'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyPlayerFocus(WebViewController controller) async {
    if (_showSourcePage || _webPageRevealedByUser) return;
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

  bool get _shouldShowWebPage =>
      _showSourcePage ||
      _webPageRevealedByUser ||
      _webSessionState == _WebSessionState.humanVerificationRequired;

  bool get _isHiddenWebSourceActive =>
      _isWebSource && !_shouldShowWebPage && _state == _LoadState.ready;

  /// يبدأ (مرة واحدة) مؤقّت المهلة القصيرة قبل إظهار شاشة "تم تشغيل
  /// المصدر بالخلفية"، ويلغيه لو خرجنا من هذه الحالة قبل انقضائه (تحوّل
  /// التشغيل بسرعة للمشغل الأصلي، الحالة الشائعة — فلا تظهر الشاشة إطلاقاً).
  void _syncHiddenSourceGraceTimer() {
    if (_isHiddenWebSourceActive) {
      _hiddenSourceGraceTimer ??= Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _hiddenSourceGraceElapsed = true);
      });
    } else if (_hiddenSourceGraceTimer != null) {
      _hiddenSourceGraceTimer!.cancel();
      _hiddenSourceGraceTimer = null;
      _hiddenSourceGraceElapsed = false;
    }
  }

  bool get _isLoadingContent =>
      _state == _LoadState.loading ||
      (_isHiddenWebSourceActive && !_hiddenSourceGraceElapsed);

  /// يشغّل مؤقّتاً دوريّاً أثناء التحميل فقط، حتى تتغيّر رسالة الانتظار
  /// تلقائياً مع مرور الوقت (راجع _loadingMessageFor).
  void _syncLoadingTicker() {
    if (_isLoadingContent) {
      _loadingBeganAt ??= DateTime.now();
      _loadingTickerTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) setState(() {});
      });
    } else if (_loadingTickerTimer != null) {
      _loadingTickerTimer!.cancel();
      _loadingTickerTimer = null;
      _loadingBeganAt = null;
    }
  }

  String get _loadingMessage {
    final began = _loadingBeganAt;
    final elapsed = began == null ? Duration.zero : DateTime.now().difference(began);
    if (elapsed >= const Duration(seconds: 15)) {
      return 'ما زلنا نجهّز المصدر… بعض الروابط تحتاج وقتاً أطول قليلاً، شكراً لصبرك';
    }
    if (elapsed >= const Duration(seconds: 6)) {
      return 'يرجى الانتظار قليلاً حتى يتم تجهيز المحتوى…';
    }
    return 'جاري تشغيل المحتوى…';
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
        if (state == _WebSessionState.humanVerificationRequired ||
            state == _WebSessionState.validating ||
            state == _WebSessionState.nativeTrial ||
            state == _WebSessionState.candidateTrial) {
          _webStartupTimeoutTimer = Timer(const Duration(milliseconds: 500), arm);
          return;
        }
        _webDetectorTimer?.cancel();
        if (_tryNextWebServer('startup_timeout')) return;
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
    _slog('AUTO_DETECT_START', 'generation=$generation');
    _setWebSessionState(_WebSessionState.discovering);

    if (!_preferredServerHostLoaded) {
      _preferredServerHostLoaded = true;
      final channelId = widget.channelId;
      if (channelId != null) {
        _preferredServerHost = await PreferredServerService.loadHost(channelId);
        if (_preferredServerHost != null) {
          _slog('PREFERRED_SERVER_LOADED', 'host=$_preferredServerHost');
        }
      }
      if (!_webSessionIsActive(generation)) return;
    }

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
            _slog('HUMAN_VERIFICATION_DETECTED', 'revealing real page to user, pausing auto-detect');
            _webHumanVerificationDetected = true;
            // Keep a real challenge visible and interactive. We do not solve
            // it; we only hand the page back to the user.
            _webPageRevealedByUser = true;
            _extendWebStartupDeadline(const Duration(seconds: 30));
            _setWebSessionState(_WebSessionState.humanVerificationRequired);
            if (mounted) setState(() {});
          }
          return;
        }
        if (_webHumanVerificationDetected) {
          _slog('HUMAN_VERIFICATION_CLEARED', 'resuming auto-detect');
          _webHumanVerificationDetected = false;
          _setWebSessionState(_WebSessionState.discovering);
          if (mounted) setState(() {});
        }
      }

      if (attempts++ >= 15) {
        _slog('AUTO_DETECT_BUDGET_EXHAUSTED', 'attempts=$attempts generation=$generation mediaEvidence=$_webMediaEvidenceScore mediaHits=$_webMediaResourceHits');
        timer.cancel();
        _webDetectorTimer = null;
        if (_webSessionIsActive(generation) && _webSessionState == _WebSessionState.discovering) {
          _setWebSessionState(_WebSessionState.webReady);
        }
        return;
      }
      if (_webDetectionInFlight ||
          _webSessionState == _WebSessionState.validating ||
          _webSessionState == _WebSessionState.nativeTrial ||
          _webSessionState == _WebSessionState.candidateTrial) {
        return;
      }
      if (_webDrmDetected) {
        _setWebSessionState(_WebSessionState.drmWebOnly);
        timer.cancel();
        _webDetectorTimer = null;
        return;
      }
      if (_webNativeAttempts >= _webMaxNativeAttempts) {
        _setWebSessionState(_WebSessionState.webReady);
        timer.cancel();
        _webDetectorTimer = null;
        return;
      }

      _webDetectionInFlight = true;
      try {
        final lastPrime = _webLastPrimeAt;
        final canPrime = lastPrime == null ||
            DateTime.now().difference(lastPrime) >= const Duration(seconds: 4);
        if (canPrime &&
            _webInteractionAttempts < _webMaxInteractionAttempts) {
          _webLastPrimeAt = DateTime.now();
          // Chromium blocks autoplay of unmuted media without a *trusted*
          // user gesture — a JS-synthesized click() from here never counts
          // as one, on any site. Muted autoplay is always allowed, so while
          // the page must stay hidden from the user we mute first: this is
          // what actually lets the site's own player start decoding/
          // fetching segments (real network evidence for the native-trial
          // pipeline below) instead of silently failing to play at all.
          // Left unmuted when the page is shown, since then a real user tap
          // is available and audio is expected.
          if (!_shouldShowWebPage) {
            await _muteWebForNativeTrial(true);
          }
          if (_webVidmolyPlayerMode) {
            await _primeVidmolyPlayback(controller);
          } else if (_webVideoJsPlayerMode) {
            await _primeVideoJsPlayback(controller);
          }
        }
        final webPlaybackProven = await _webPlaybackSentinel(controller);
        if (webPlaybackProven) {
          _webPlaybackProven = true;
          if (_webSessionIsActive(generation)) {
            await _showWebPlaybackReady(controller);
          }
        }

        final iframeCandidate = await _findBestIframeCandidate(controller);
        if (iframeCandidate != null && !_webIframePromotionInFlight && !_webPlaybackReady) {
          final candidateUri = Uri.tryParse(iframeCandidate);
          final candidateHost = candidateUri?.host.toLowerCase() ?? '';
          final currentHost = _webSourceOrigin?.toLowerCase() ?? '';
          final playerish = RegExp(r'(embed|shell|player|video|watch|stream|play|live)', caseSensitive: false).hasMatch(iframeCandidate);
          _slog(
            'IFRAME_POLL_CANDIDATE',
            'url=${_safeLogUrl(iframeCandidate)} playerish=$playerish crossHost=${candidateHost != currentHost}',
          );
          if (playerish || candidateHost != currentHost) {
            await _promoteIframeToPlayerDocument(controller, iframeCandidate, 80);
            return;
          }
        }

        if (!webPlaybackProven &&
            !_webPlaybackProven &&
            _webMediaEvidenceScore >= 70 &&
            _webMediaResourceHits >= 4) {
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
        final sources = <String>{
          ...frameworkSources,
          ...genericSources,
          ..._webCandidateRegistry.keys,
        }.toList();
        if (!_webSessionIsActive(generation)) return;
        _slog(
          'SOURCES_SCAN',
          'attempt=$attempts framework=${frameworkSources.length} generic=${genericSources.length} registry=${_webCandidateRegistry.length} total=${sources.length}',
        );

        if (_webInteractionAttempts < _webMaxInteractionAttempts && !await _webPlaybackSentinel(controller)) {
          _slog('AUTO_CLICK_ATTEMPT', 'interactionAttempts=$_webInteractionAttempts/$_webMaxInteractionAttempts');
          final interacted = await _runSmartInteraction(controller);
          _slog('AUTO_CLICK_RESULT', 'clicked=$interacted');
          if (interacted) {
            timer.cancel();
            _webDetectorTimer = null;
            _setWebSessionState(_WebSessionState.discovering);
            unawaited(_autoDetectWebSource(controller));
            return;
          }
        }

        // Phase 1: cheap synchronous filtering only (no network) — builds the
        // list of candidates worth an actual network validation call.
        //
        // التقييم/الاستبعاد أدناه يمرّ الآن عبر استراتيجية خاصة بنوع
        // المشغّل المكتشَف فعلياً بهذي الجلسة (JWPlayer/vidmoly، video.js،
        // أو عام) بدل صيغة واحدة مشتركة لكل الأنواع — راجع player_strategy
        // .dart لسبب هذا الفصل (سجل #39/#40/#41ب بـTECHNICAL.md). القيم
        // الافتراضية مطابقة تماماً للصيغة القديمة، فهذا لا يغيّر أي سلوك
        // حالي بمفرده.
        final strategy = PlayerStrategyRegistry.select(
          isVideoJsMode: _webVideoJsPlayerMode,
          isJwPlayerLikeMode: _webVidmolyPlayerMode,
        );
        final probes = <_CandidateProbe>[];
        for (final sourceRaw in sources) {
          final source = _normalizeCandidate(sourceRaw);
          if (strategy.isNonMediaAsset(source)) continue;
          final registered = _webCandidateRegistry[source];
          final score = strategy.scoreCandidate(
            source,
            isFrameworkSource: frameworkSources.contains(sourceRaw),
            registeredAsHls: registered?.type == 'hls',
          );
          final registryEvidence = registered?.evidenceScore ?? 0;
          _webCandidateEvidence[source] =
              (_webCandidateEvidence[source] ?? 0) + 1 + (registryEvidence ~/ 25);
          if (score < 80) {
            _slog('SOURCE_SKIPPED', 'url=${_safeLogUrl(source)} reason=score_too_low score=$score');
            continue;
          }
          final uri = Uri.tryParse(source);
          if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) continue;
          if (!_canTrialNative(source)) {
            _slog('SOURCE_SKIPPED', 'url=${_safeLogUrl(source)} reason=cannot_trial_native');
            continue;
          }

          final evidence = _webCandidateEvidence[source] ?? 0;
          final strongHls =
              (registered?.type == 'hls' || _looksLikeHls(source)) &&
                  score >= 100;
          final strongFramework = frameworkSources.contains(sourceRaw) && score >= 80;
          if (evidence < 2 && !strongHls && !strongFramework) {
            _slog('SOURCE_SKIPPED', 'url=${_safeLogUrl(source)} reason=insufficient_evidence evidence=$evidence score=$score');
            continue;
          }
          // A URL observed in the browser is not enough. Native replay is
          // allowed only after the browser has proved real playback.
          if (!webPlaybackProven && !_webPlaybackProven) {
            _slog('SOURCE_SKIPPED', 'url=${_safeLogUrl(source)} reason=web_playback_not_proven_yet');
            continue;
          }
          probes.add(_CandidateProbe(
            source: source,
            registered: registered,
            score: score,
            evidence: evidence,
            strongHls: strongHls,
            strongFramework: strongFramework,
          ));
        }

        // Strongest candidate first: with only _webMaxNativeAttempts trials
        // budgeted per session, wasting one on a low-score candidate that
        // happened to appear first in `sources` (an unordered Set) costs
        // real chances at a working candidate. Stable by construction (ties
        // broken by original index) since List.sort is not guaranteed
        // stable and candidates found in the same scan can tie on score.
        if (probes.length > 1) {
          final indexed = List<MapEntry<int, _CandidateProbe>>.generate(
              probes.length, (i) => MapEntry(i, probes[i]));
          indexed.sort((a, b) {
            final scoreCompare = b.value.score.compareTo(a.value.score);
            return scoreCompare != 0 ? scoreCompare : a.key.compareTo(b.key);
          });
          probes
            ..clear()
            ..addAll(indexed.map((e) => e.value));
        }

        // A candidate on the host that already succeeded for this channel
        // before jumps to the front (relative order within each group is
        // otherwise unchanged — List.sort is not stable, so this partitions
        // manually instead of sorting).
        final preferredHost = _preferredServerHost;
        if (preferredHost != null && probes.length > 1) {
          final preferred = <_CandidateProbe>[];
          final rest = <_CandidateProbe>[];
          for (final probe in probes) {
            if (Uri.tryParse(probe.source)?.host == preferredHost) {
              preferred.add(probe);
            } else {
              rest.add(probe);
            }
          }
          if (preferred.isNotEmpty) {
            probes
              ..clear()
              ..addAll(preferred)
              ..addAll(rest);
          }
        }

        // Phase 2: start every remaining candidate's validation concurrently
        // (fire immediately, don't await here) instead of one await per
        // candidate in sequence. Phase 3 below then awaits each candidate's
        // OWN future in priority order — since every one of them already
        // started here, that wait is bounded by that candidate's own
        // latency alone, never by a slower/lower-priority candidate further
        // down the list. Awaiting the whole batch together (an earlier
        // version of this did) has the same total network cost but forces
        // the winning candidate — often already resolved instantly via the
        // strong-evidence skip below — to sit idle behind a slow candidate
        // it was never going to need, wasting real seconds before every
        // native trial starts. Confirmed on a real diagnostic log: an 8s
        // validation timeout on a losing low-priority candidate delayed the
        // winning strong-evidence candidate's native trial by the same 8s.
        if (probes.isNotEmpty) {
          _setWebSessionState(_WebSessionState.validating);
        }
        final validationFutures = <Future<void>>[
          for (final probe in probes)
            () async {
              probe.headers = await _headersForCandidate(probe.source, probe.registered);
              if (probe.strongHls || probe.strongFramework) {
                // أدلة قوية أصلاً (HLS مؤكد أو إطار تشغيل معروف بنتيجة عالية) —
                // نتيجة فحص الشبكة هنا لن تُغيّر القرار مهما كانت (الشرط أسفل
                // مستثنيها أصلاً عبر strongHls/strongFramework)، فتخطّيه يوفّر
                // ثواني حرجة قبل تجربة التشغيل الأصلي الفعلية. شوهد فعلياً بسجل
                // تشخيص: رابط بث موقّت (توكن قصير الأجل على الأغلب) يعمل بنجاح
                // مستمر داخل WebView لكن يفشل بالتشغيل الأصلي — الفارق الزمني
                // بين لحظة اكتشاف الرابط ولحظة تجربته فعلياً هو المشتبه الأول،
                // وهذا الفحص كان يضيف زمناً إضافياً بلا أي فائدة لهذه الحالة.
                probe.validated = true;
                _slog('SOURCE_VALIDATION_SKIPPED', 'url=${_safeLogUrl(probe.source)} reason=strong_evidence score=${probe.score}');
                return;
              }
              // Best-effort validation. A negative validation is not fatal when
              // the browser has already supplied strong evidence (for example a
              // stream requiring Referer/Origin/cookies).
              _slog('SOURCE_VALIDATING', 'url=${_safeLogUrl(probe.source)} evidence=${probe.evidence} score=${probe.score} headers=${probe.headers.keys.toList()}');
              final validated = await _validatePublicMediaSource(
                probe.source,
                requestHeaders: probe.headers,
              );
              probe.validated = validated;
              probe.registered?.validated = validated;
              _smartLog(
                'HLS',
                'candidate ${validated ? 'validated' : 'rejected'}: ${_safeLogUrl(probe.source)}',
              );
              _slog('SOURCE_VALIDATED', 'url=${_safeLogUrl(probe.source)} validated=$validated');
            }(),
        ];

        // Phase 3: pick the first candidate (in original discovery-priority
        // order) that passed, exactly as the sequential version did — only
        // one native trial is ever started here, so the single-controller
        // playback architecture is untouched.
        for (var probeIndex = 0; probeIndex < probes.length; probeIndex++) {
          final probe = probes[probeIndex];
          await validationFutures[probeIndex];
          if (!_webSessionIsActive(generation)) return;
          if (!probe.validated &&
              probe.evidence < 3 &&
              !probe.strongHls &&
              !probe.strongFramework) {
            _slog('SOURCE_SKIPPED', 'url=${_safeLogUrl(probe.source)} reason=failed_validation');
            continue;
          }

          _setWebSessionState(_WebSessionState.nativeTrial);
          _webNativeAttempts++;
          _webLastNativeTrialAt = DateTime.now();
          _extendWebStartupDeadline(const Duration(seconds: 12));
          _webSeenSources.add(probe.source);
          _webCandidateLastReason[probe.source] =
              'validated candidate, evidence=${probe.evidence}, score=${probe.score}';
          _slog('NATIVE_TRIAL_QUEUED', 'url=${_safeLogUrl(probe.source)} attempt=$_webNativeAttempts/$_webMaxNativeAttempts');
          timer.cancel();

          final quality = StreamQuality(label: _autoDiscoveredServerLabel, url: probe.source);
          await _playServerQuality(
            StreamServerOption(label: _autoDiscoveredServerLabel, qualities: [quality]),
            quality,
            fallbackToWeb: true,
            playbackHeaders: probe.headers,
            // registered?.type == 'hls' alone missed real cases: a candidate
            // can be confirmed HLS by strongHls (URL pattern, e.g. a '/hls/'
            // path segment) above without ever having a matching registry
            // entry — e.g. when the exact URL string picked up a trailing
            // '/' somewhere between collection and this point. Without an
            // explicit hint, ExoPlayer falls back to guessing the container
            // from the URL's file extension, which fails outright on a URL
            // that doesn't literally end in ".m3u8" — producing a generic
            // "Source error" for content that is genuinely playable HLS.
            // strongHls already carries this exact judgement (also used
            // just above to skip redundant validation); reuse it here too.
            formatHintOverride: (probe.registered?.type == 'hls' || probe.strongHls)
                ? VideoFormat.hls
                : null,
          );
          return;
        }
        if (probes.isNotEmpty) {
          _setWebSessionState(_WebSessionState.discovering);
        }

        // Browser playback is already proven, but no safe native candidate
        // passed the gate. Keep the real page visible as the primary fallback.
        //
        // While the page is shown, weak evidence is enough — the user can
        // see the page and a real tap can push a blocked player over the
        // line. While it must stay hidden, no one can see or tap it, so
        // claiming "ready" on weak evidence alone leaves the user stuck on
        // a "playing in background" screen with nothing actually playing.
        // Require real proof (advancing playback, or strong network
        // evidence — see _webPlaybackSentinel) before revealing in that
        // case; otherwise keep retrying instead of lying about the state.
        final hasRealProof = webPlaybackProven || _webPlaybackProven;
        if (_webVidmolyPlayerMode) {
          final hasWeakEvidence = _webMediaEvidenceScore >= 35 || _webMediaResourceHits >= 2;
          if (hasRealProof || (_shouldShowWebPage && hasWeakEvidence)) {
            _slog('FALLBACK_TO_WEBVIEW', 'reason=vidmoly_no_native_candidate score=$_webMediaEvidenceScore hits=$_webMediaResourceHits proof=$hasRealProof');
            await _revealVidmolyPlayer(controller);
          }
          return;
        }
        if (_webVideoJsPlayerMode) {
          final hasWeakEvidence = _webMediaEvidenceScore >= 25 || _webMediaResourceHits >= 1;
          if (hasRealProof || (_shouldShowWebPage && hasWeakEvidence)) {
            _slog('FALLBACK_TO_WEBVIEW', 'reason=videojs_no_native_candidate score=$_webMediaEvidenceScore hits=$_webMediaResourceHits proof=$hasRealProof');
            await _revealVideoJsPlayer(controller);
          }
          return;
        }
      } finally {
        _webDetectionInFlight = false;
      }
    });
  }

  bool _isVideoJsPlayerUrl(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final path = uri?.path.toLowerCase() ?? '';
    return host == '3ick.club' || host.endsWith('.3ick.club') ||
        host == '3ickk.xyz' || host.endsWith('.3ickk.xyz') ||
        host == '3isk.club' || host.endsWith('.3isk.club') ||
        host == '3iskk.xyz' || host.endsWith('.3iskk.xyz') ||
        host == 'ukrcdn.club' || host.endsWith('.ukrcdn.club') ||
        host == 'ukrcdn.xyz' || host.endsWith('.ukrcdn.xyz') ||
        path.contains('/embed/') || path.contains('/player/');
  }

  bool _isVidmolyPlayerUrl(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final path = uri?.path.toLowerCase() ?? '';
    return host == 'vidmoly.org' ||
        host.endsWith('.vidmoly.org') ||
        host == 'vidmoly.me' ||
        host.endsWith('.vidmoly.me') ||
        host == 'vidmoly.biz' ||
        host.endsWith('.vidmoly.biz') ||
        host == 'vidmoly.to' ||
        host.endsWith('.vidmoly.to') ||
        host == 'sw.vidmoly.me' ||
        path.contains('/embed-');
  }

  Future<void> _revealVidmolyPlayer(WebViewController controller) async {
    if (!mounted || !_webVidmolyPlayerMode || _webPlaybackReady) return;
    _webVidmolyRevealTimer?.cancel();
    _webVidmolyRevealTimer = null;
    _setWebSessionState(_WebSessionState.webReady);
    await _applyPlayerFocus(controller);
    if (!mounted || _webPlaybackReady) return;
    // مؤكَّد بمراجعة كود (سجل تشخيص فعلي: FALLBACK_TO_WEBVIEW يتكرر كل ~2
    // ثانية طوال الجلسة، بلا توقف) — هذي الدالة لم تكن تضبط _webPlaybackReady
    // إطلاقاً، فحارسها الخاص بأول السطر (`|| _webPlaybackReady`) كان ميتاً
    // دائماً: تُعاد استدعاؤها بكل دورة اكتشاف بدل مرة واحدة فقط، تُعيد ضبط
    // حالة الجلسة وتستدعي setState بلا داعٍ كل مرة.
    _webPlaybackReady = true;
    setState(() {
      _state = _LoadState.ready;
      _isWebSource = true;
      _errorMessage = '';
    });
  }

  Future<void> _revealVideoJsPlayer(WebViewController controller) async {
    if (!mounted || !_webVideoJsPlayerMode || _webPlaybackReady) return;
    _setWebSessionState(_WebSessionState.webReady);
    await _applyPlayerFocus(controller);
    await _primeVideoJsPlayback(controller);
    if (!mounted || _webPlaybackReady) return;
    // نفس إصلاح _revealVidmolyPlayer أعلاه — نفس الخلل بالضبط هنا.
    _webPlaybackReady = true;
    setState(() {
      _state = _LoadState.ready;
      _isWebSource = true;
      _errorMessage = '';
    });
  }

  Future<void> _primeVideoJsPlayback(WebViewController controller) async {
    try {
      await controller.runJavaScript(r"""(() => {
        try {
          const visible = (el) => {
            if (!el) return false;
            const r = el.getBoundingClientRect();
            const cs = getComputedStyle(el);
            return r.width > 20 && r.height > 20 && cs.display !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0';
          };
          const scoreButton = (el) => {
            const text = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim();
            const idcls = `${el.id || ''} ${el.className || ''}`;
            if (/login|subscribe|purchase|buy|download|advert|close/i.test(`${text} ${idcls}`)) return -100;
            let score = 0;
            if (/^(play|start|watch|live|تشغيل|ابدأ|شاهد|مشاهدة|بدء)$/i.test(text)) score += 80;
            if (/(vjs-big-play-button|play-control|play|start|watch|live)/i.test(idcls)) score += 35;
            return score;
          };
          let best = null, bestScore = 0;
          document.querySelectorAll('button,[role=\"button\"],a,[class*=\"play\" i],[id*=\"play\" i]').forEach(el => {
            if (!visible(el)) return;
            const s = scoreButton(el);
            if (s > bestScore) { best = el; bestScore = s; }
          });
          if (best) {
            try { best.scrollIntoView({block:'center',inline:'center'}); } catch (_) {}
            try { best.click(); } catch (_) {}
          }
          if (window.videojs) {
            document.querySelectorAll('video').forEach(v => {
              try {
                const player = v.id ? window.videojs.getPlayer(v.id) : null;
                if (player && typeof player.play === 'function') player.play();
              } catch (_) {}
            });
          }
          document.querySelectorAll('video,audio').forEach(v => {
            try { if (v.paused && v.readyState >= 2) v.play().catch(() => {}); } catch (_) {}
          });
        } catch (_) {}
      })();""");
    } catch (_) {}
  }

  Future<void> _primeVidmolyPlayback(WebViewController controller) async {
    try {
      await controller.runJavaScript(r"""(() => {
        try {
          const visible = (el) => {
            if (!el) return false;
            const r = el.getBoundingClientRect();
            const cs = getComputedStyle(el);
            return r.width > 20 && r.height > 20 && cs.display !== 'none' && cs.visibility !== 'hidden';
          };
          const nodes = Array.from(document.querySelectorAll('button,[role=\"button\"],a,[class*=\"play\" i],[id*=\"play\" i]'));
          for (const el of nodes) {
            if (!visible(el)) continue;
            const text = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim();
            const idcls = `${el.id || ''} ${el.className || ''}`;
            if (/^(play|start|watch|live|تشغيل|ابدأ|شاهد|مشاهدة|بدء)$/i.test(text) || /(^|\W)(play|start|watch|jw-icon-play|jwplayer)(\W|$)/i.test(idcls)) {
              try { el.scrollIntoView({block:'center', inline:'center'}); } catch (_) {}
              try { el.click(); } catch (_) {}
              break;
            }
          }
          if (window.jwplayer) {
            const roots = document.querySelectorAll('[id],[class]');
            for (const el of roots) {
              const id = el.id || '';
              const cls = typeof el.className === 'string' ? el.className : '';
              if (!/jwplayer|jw-wrapper|jw-video/i.test(`${id} ${cls}`)) continue;
              try {
                const p = window.jwplayer(id || el);
                if (p && typeof p.play === 'function') { p.play(); break; }
              } catch (_) {}
            }
          }
          document.querySelectorAll('video').forEach(v => {
            try { if (v.paused && v.readyState >= 2) v.play().catch(() => {}); } catch (_) {}
          });
        } catch (_) {}
      })();""");
    } catch (_) {}
  }

  // فشل نهائي بجلسة WebView (صفحة لم تفتح أصلاً، أو انتهت مهلة الاكتشاف
  // بدون أي نتيجة) — لو للحلقة أكثر من سيرفر (استُوردت من أكثر من موقع،
  // راجع sources[]/site-importer.js) يجرّب السيرفر التالي تلقائياً بدل
  // عرض شاشة خطأ فوراً؛ فقط عند نفاد كل السيرفرات تُعرض الشاشة الحقيقية.
  // "التالي" يُحسب من موضع _activeServer الحالي بقائمة السيرفرات نفسها،
  // لا دائماً الأول، حتى لا تُعاد تجربة سيرفر فشل للتو لو تكرّر الفشل.
  bool _tryNextWebServer(String reason) {
    final session = _session;
    if (session == null || session.kind != StreamKind.web || !session.hasMultipleServers) {
      return false;
    }
    final servers = session.servers;
    final currentIndex = _activeServer == null
        ? -1
        : servers.indexWhere((s) => identical(s, _activeServer));
    if (currentIndex + 1 >= servers.length) return false;
    final next = servers[currentIndex + 1];
    _slog(
      'WEB_SERVER_AUTO_FALLBACK',
      'from=${_activeServer?.label} to=${next.label} reason=$reason',
    );
    unawaited(_openWebSource(next.qualities.first.url, server: next));
    return true;
  }

  Future<void> _openWebSource(String url, {StreamServerOption? server}) async {
    _slog('OPEN_WEB_SOURCE', _safeLogUrl(url));
    if (server != null) {
      _activeServer = server;
      _activeQuality = server.qualities.isNotEmpty ? server.qualities.first : null;
    }
    _webDetectorTimer?.cancel();
    _webSessionGeneration++;
    _webSessionState = _WebSessionState.loadingPage;
    _webDetectionInFlight = false;
    _webNativeAttempts = 0;
    _webLastNativeTrialAt = null;
    _webInteractionAttempts = 0;
    _webLastInteractionAt = null;
    _webLastPrimeAt = null;
    _webPlaybackReady = false;
    _webPlaybackProven = false;
    _webLastDetectionKickAt = null;
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
    _webVidmolyPlayerMode = false;
    _webVideoJsPlayerMode = false;
    _webVidmolyRevealTimer?.cancel();
    _webVidmolyRevealTimer = null;
    _webIframePromotionAttempts = 0;
    _webLastPromotedIframeUrl = null;
    _webMediaEvidenceScore = 0;
    _webMediaResourceHits = 0;
    _webStartupTimeoutTimer?.cancel();
    _webSeenSources.clear();
    _webFailedNativeSources.clear();
    _webCandidateEvidence.clear();
    _webCandidateLastReason.clear();
    _webCandidateRegistry.clear();
    _webManifestRelayAttemptedUrls.clear();
    setState(() {
      _state = _LoadState.loading;
      _isWebSource = true;
      _webContextHeaders = null;
      _webDrmDetected = false;
    });
    try {
      final sourceUri = Uri.parse(url);
      _webSourceOrigin = sourceUri.host;
      _webVidmolyPlayerMode = _isVidmolyPlayerUrl(url);
      _webVideoJsPlayerMode = _isVideoJsPlayerUrl(url);
      late final WebViewController controller;
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        // يضبط هوية محرّك WebView نفسه (مو بس هيدر الطلب الأول) — بعض
        // المواقع خلف حماية WAF تميّز/تحظر WebView المدمج بنظام أندرويد عن
        // متصفح حقيقي حتى مع نفس نص الـ User-Agent بالهيدر، لأن هوية
        // المحرّك الفعلية تُستخدم لأي طلب فرعي (جافاسكريبت، XHR، تنقّل...)
        // بغض النظر عن هيدرز أول تحميل. راجع مناقشة net::ERR_CONNECTION_RESET
        // بسجل تشخيص حقيقي لموقع رفض WebView تحديداً بينما فتح عادي بمتصفح حقيقي.
        ..setUserAgent(widget.externalUserAgent ??
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.119 Mobile Safari/537.36')
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
            if (_isDangerousWebUrl(request.url)) {
              _smartLog('NAV', 'blocked unsafe navigation');
              _slog('NAV_BLOCKED_UNSAFE', _safeLogUrl(request.url));
              return NavigationDecision.prevent;
            }
            if (!request.isMainFrame) {
              _slog('NAV_SUBFRAME_ALLOWED', _safeLogUrl(request.url));
              return NavigationDecision.navigate;
            }
            if (!_isAllowedWebNavigation(request.url)) {
              _slog('NAV_BLOCKED_DISALLOWED', _safeLogUrl(request.url));
              return NavigationDecision.prevent;
            }
            if (_webInitialLoadCompleted) {
              final requestHost = Uri.tryParse(request.url)?.host.toLowerCase() ?? '';
              final originHost = _webSourceOrigin?.toLowerCase() ?? '';
              if (requestHost.isNotEmpty && originHost.isNotEmpty && requestHost != originHost) {
                // A promoted cross-origin player is now the main document.
                // Its legitimate player/CDN redirects may cross hosts; blocking
                // them here can leave a working player stuck on its first page.
                // Ad/popup hosts are still rejected by _isAllowedWebNavigation.
                if (!_webPromotedPlayerMode) {
                  _slog(
                    'NAV_BLOCKED_CROSS_ORIGIN',
                    'from=$originHost to=$requestHost promoted=$_webPromotedPlayerMode',
                  );
                  return NavigationDecision.prevent;
                }
              }
            }
            _slog('NAV_ALLOWED', _safeLogUrl(request.url));
            return NavigationDecision.navigate;
          },
          onPageFinished: (finishedUrl) async {
            _webInitialLoadCompleted = true;
            _slog('PAGE_FINISHED', _safeLogUrl(finishedUrl));
            // بعد نجاح التشغيل الأصلي (nativePlaying)، الـ WebView يبقى حياً
            // بالخلفية فقط كاحتياط (مثلاً لإعادة جلب الـ manifest لاحقاً عند
            // تبديل الجودة)، لكنه غالباً يستمر يتنقّل وحده عبر سلسلة تحويلات
            // إعلانية (073m.com → afu.php → مواقع أخرى). بدون هذا الحارس، كل
            // تنقّل كان يعيد ضبط _state لـ "جاري التحميل" (يخفي الفيديو
            // الشغّال فعلياً خلف شاشة بحث وهمية) ويطلق دورة اكتشاف وتشغيل
            // كاملة ثانية لنفس المصدر — بدون إيقاف الأولى، فيسمع المستخدم
            // صوتين متزامنين. راجع سجل تشخيص فعلي وثّق هذا بالضبط.
            if (_webSessionState == _WebSessionState.nativePlaying) return;
            // The initial source may be RistoAnime, then V11 promotes its
            // Vidmoly iframe to the main document. Re-evaluate the player mode
            // on every completed main-frame navigation so the promoted embed
            // receives the same WebView-first treatment.
            if (_isVidmolyPlayerUrl(finishedUrl)) {
              _webVidmolyPlayerMode = true;
            }
            if (_isVideoJsPlayerUrl(finishedUrl)) {
              _webVideoJsPlayerMode = true;
            }
            if (_webPromotedPlayerMode) {
              _webMediaEvidenceScore = 0;
              _webMediaResourceHits = 0;
              _extendWebStartupDeadline(const Duration(seconds: 15));
            }
            await _installWebProtection(controller);
            await _captureWebContext(controller);
            if (!mounted) return;

            // Vidmoly's embed is the actual player surface. Network evidence
            // confirms HLS.js fetching real .ts segments from this document.
            // Reveal it instead of hiding it behind the startup overlay: on
            // Android autoplay may be blocked and the player needs a real tap.
            if ((_webVidmolyPlayerMode || _webVideoJsPlayerMode) &&
                _shouldShowWebPage) {
              _setWebSessionState(_WebSessionState.webReady);
              setState(() {
                _state = _LoadState.ready;
                _isWebSource = true;
                _errorMessage = '';
              });
              await _applyPlayerFocus(controller);
              if (_webVidmolyPlayerMode) {
                _smartLog('VIDMOLY', 'player detected; priming JW/HTML5 controls');
                _slog('KNOWN_PLAYER_DETECTED', 'vidmoly — showing WebView as ready, native trial skipped');
                await _primeVidmolyPlayback(controller);
              } else if (_webVideoJsPlayerMode) {
                _smartLog('VIDEOJS', 'player detected; priming Video.js/HTML5 controls');
                _slog('KNOWN_PLAYER_DETECTED', 'video.js — showing WebView as ready, native trial skipped');
                await _primeVideoJsPlayback(controller);
              }
              unawaited(_autoDetectWebSource(controller));
              return;
            }

            // Keep the page hidden until playback is proven when the
            // dashboard setting requests background discovery. This still
            // leaves the WebView mounted so autoplay/network discovery can
            // continue; the Flutter status surface is shown above it.
            setState(() => _state = _LoadState.loading);
            if (!_webDrmDetected) {
              _setWebSessionState(_WebSessionState.webReady);
              _slog('KICK_AUTO_DETECT', 'from onPageFinished, generation=$_webSessionGeneration');
              unawaited(_autoDetectWebSource(controller));
            } else {
              _slog('DRM_ALREADY_DETECTED', 'skipping auto-detect after page load');
            }
          },
          onWebResourceError: (error) {
            _slog(
              'WEB_RESOURCE_ERROR',
              'code=${error.errorCode} desc=${error.description} mainFrame=${error.isForMainFrame} sessionState=$_webSessionState',
            );
            if (mounted && error.isForMainFrame == true && _webSessionState != _WebSessionState.candidateTrial && _webSessionState != _WebSessionState.nativePlaying) {
              if (_tryNextWebServer('web_resource_error:${error.errorCode}')) return;
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
      if (_tryNextWebServer('open_web_source_failed')) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'تعذر فتح صفحة المصدر. تحقق من الرابط وحاول مرة أخرى.';
      });
    }
  }

}
