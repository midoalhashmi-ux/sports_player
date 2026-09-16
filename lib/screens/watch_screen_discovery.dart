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
  // دومين أول صفحة فُتحت هذي الجلسة (قبل أي ترقية iframe) — مفتاح وصفة
  // الموقع أدناه. يُضبَط مرة واحدة بـ_openWebSource ولا يتغيّر بعدها حتى
  // لو _webSourceOrigin تغيّر لاحقاً (يتحدّث لمضيف iframe المُرقَّى).
  String? _webEntryHost;
  // وصفة موقع متعلّمة: مضيف iframe الذي نجح سابقاً لنفس _webEntryHost،
  // تُرقّى أي مرشح مطابق لنفس المضيف فوراً بدل انتظار الأدلة العامة
  // (نص "playerish" أو crossHost). راجع SiteRecipeService وافكار_مهمة.md
  // قسم 3.
  SiteRecipe? _webSiteRecipe;
  bool _webSiteRecipeLoaded = false;
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
  // آخر لحظة زاد فيها هذا العدّاد فعلياً — تشخيص فقط: يسمح لوكيل الـHLS
  // (hls_cache_proxy) يسجّل هل WebView كان نشطاً شبكياً (يجلب نفس المصدر)
  // بنفس لحظة فشل جلب شريحتنا بالضبط، بدل مقارنة يدوية للطوابع الزمنية
  // بين سجلَّين منفصلين لاحقاً.
  DateTime? _lastWebMediaResourceHitAt;
  /// مفاتيح الجودات التي أثبت مشغّل الموقع (داخل WebView) أنه يجلب شرائحها
  /// فعلاً على هذي الشبكة بهذي اللحظة — أدق مقياس متاح لقدرة الاتصال، لأن
  /// آلية التكيّف الخاصة بالموقع تعمل بنفس الظروف تماماً. تُستخدَم لتقديم
  /// نفس الجودة للتشغيل الأصلي بدل الأعلى دائماً (راجع
  /// `HlsVariantSelector` وTECHNICAL.md #50).
  final Set<String> _webProvenVariantKeys = <String>{};
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
  // WebView always calls onPageFinished after a navigation attempt, even
  // when that navigation actually failed (e.g. ERR_CONNECTION_RESET on the
  // main frame — confirmed by a real log where onWebResourceError correctly
  // set _state = error, only for onPageFinished to fire immediately after
  // and unconditionally reset it back to loading + kick discovery against a
  // page that never actually loaded any HTML, burning the auto-detect
  // budget on 0 candidates every scan). Set on a fatal main-frame resource
  // error, cleared at the start of every fresh page load in _openWebSource.
  bool _webMainFrameLoadFailed = false;
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

  // Dynamic replacement for a manually-maintained ad-domain blacklist.
  // _isDangerousWebUrl above only catches names/keywords we already know —
  // real logs show brand-new ad-redirect hosts (a random-looking .shop/
  // .com.in/shortlink domain) sailing straight through it every time,
  // exactly the "I have to keep adding domains myself" problem. Once a
  // promoted player page has actually loaded real resources this session
  // (an HLS manifest, a segment, the player's own JS — anything recorded in
  // _webCandidateRegistry), nothing about legitimate playback ever needs
  // the TOP FRAME to jump to a host that produced zero of that traffic —
  // that shape (sudden top-level nav to a host we've never once fetched
  // anything from) is exactly what an ad/redirect hijack looks like,
  // regardless of what the domain is named. So instead of blacklisting
  // known-bad names, this allowlists only hosts this session has actually
  // seen serve real content — anything else is blocked automatically, no
  // manual list to maintain.
  bool _isTrustedNavigationHost(String host) {
    if (host.isEmpty) return false;
    bool sameSite(String a, String b) =>
        a.isNotEmpty && b.isNotEmpty && (a == b || _registrableDomain(a) == _registrableDomain(b));
    if (sameSite(host, _webEntryHost ?? '')) return true;
    if (sameSite(host, _webSourceOrigin ?? '')) return true;
    for (final candidate in _webCandidateRegistry.values) {
      final candidateHost = Uri.tryParse(candidate.url)?.host.toLowerCase() ?? '';
      if (sameSite(host, candidateHost)) return true;
      final pageHost = Uri.tryParse(candidate.pageUrl)?.host.toLowerCase() ?? '';
      if (sameSite(host, pageHost)) return true;
    }
    return false;
  }

  // Simplistic eTLD+1 extraction (last two labels) — good enough to
  // recognize sibling CDN subdomains (cdn1.example.com vs cdn2.example.com
  // as "the same site"); not a security boundary, just a same-site heuristic.
  String _registrableDomain(String host) {
    final parts = host.toLowerCase().split('.').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return parts.join('.');
    return parts.sublist(parts.length - 2).join('.');
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
    if (type == 'overlay_ad_blocked') {
      // تشخيص فقط — يثبت بالسجل أن الكاسح البنيوي اشتغل فعلاً وعلى ماذا،
      // بدل الاعتماد على وصف المستخدم لشكل الإعلان.
      _slog('OVERLAY_AD_BLOCKED',
          'score=${decoded['score']} tag=${decoded['tag']}');
      return;
    }
    if (type == 'media_resource') {
      _webMediaResourceHits++;
      _lastWebMediaResourceHitAt = DateTime.now();
      final rawResourceUrl = decoded['url']?.toString() ?? '';
      final resourceUrl = rawResourceUrl.toLowerCase();
      final segmentEvidence = RegExp(r'(^|[/._-])seg(?:ment)?[-_]?\d+|\.(ts|m4s)(?:$|[?#])').hasMatch(resourceUrl);
      _webMediaEvidenceScore = (_webMediaEvidenceScore + (segmentEvidence ? 22 : 12)).clamp(0, 100).toInt();
      if (segmentEvidence) {
        // شريحة فيديو حقيقية جلبها الموقع بنجاح = إثبات عملي أن الشبكة
        // تتحمّل هذي الجودة تحديداً. نسجّلها لنقدّمها للتشغيل الأصلي بدل
        // الأعلى نطاقاً (الأخيرة أثبتت السجلات فشلها المتكرر).
        final provenKey = HlsVariantSelector.variantKey(rawResourceUrl);
        if (provenKey != null && _webProvenVariantKeys.add(provenKey)) {
          _slog('WEB_PROVEN_VARIANT', 'key=$provenKey');
        }
      }
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
        _lastWebMediaResourceHitAt = DateTime.now();
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
          final entryHost = _webEntryHost;
          final targetHost = Uri.tryParse(iframeUrl)?.host ?? '';
          if (entryHost != null && entryHost.isNotEmpty && targetHost.isNotEmpty) {
            final mode = _webVidmolyPlayerMode
                ? 'vidmoly'
                : (_webVideoJsPlayerMode ? 'videojs' : 'generic');
            unawaited(SiteRecipeService.remember(
                entryHost, SiteRecipe(targetHost: targetHost, playerMode: mode)));
            _slog('SITE_RECIPE_SAVED', 'entryHost=$entryHost targetHost=$targetHost playerMode=$mode');
          }
          return;
        }
        if (_webIframePromotionAttempts < 2 && parentUrl != null && parentUrl.isNotEmpty) {
          _slog('IFRAME_PROMOTE_TIMEOUT_REVERT', 'url=${_safeLogUrl(iframeUrl)} backTo=${_safeLogUrl(parentUrl)}');
          // فشل الوصفة المحفوظة (لو كانت هي سبب هذي الترقية) — رجوع فوري
          // للمسار الكامل العادي بإزالتها، بدل تركها تعطّل نفس المسار مجدداً
          // بالزيارة القادمة لنفس الموقع.
          final entryHost = _webEntryHost;
          final recipe = _webSiteRecipe;
          final failedHost = Uri.tryParse(iframeUrl)?.host.toLowerCase() ?? '';
          if (entryHost != null &&
              entryHost.isNotEmpty &&
              recipe != null &&
              recipe.targetHost.toLowerCase() == failedHost) {
            _webSiteRecipe = null;
            unawaited(SiteRecipeService.invalidate(entryHost));
            _slog('SITE_RECIPE_INVALIDATED', 'entryHost=$entryHost targetHost=$failedHost');
          }
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
    await controller.runJavaScript(kWebProtectionScript);
    // كاسح بنيوي مستقل يعمل بالتوازي مع الحماية أعلاه: لا يقرأ أي كلمة
    // ولا يعتمد أي اسم كلاس، فيصمد أمام أي إعلان جديد مهما تغيّر شكله أو
    // لغته (راجع kOverlayAdSweeperScript وTECHNICAL.md #51).
    await controller.runJavaScript(kOverlayAdSweeperScript);
  }

  Future<List<String>> _detectPublicMediaSources(WebViewController controller) async {
    try {
      const js = kDetectPublicMediaSourcesScript;
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
      // الفرز يعتمد BANDWIDTH لأنه موجود دائماً بينما RESOLUTION اختياري
      // بالمواصفة.
      final variants = <HlsVariant>[];
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
        variants.add(HlsVariant(
          bandwidth: bandwidth,
          label: label,
          url: _resolveRelativeUrl(urlLine, manifestUrl),
        ));
      }
      if (variants.isEmpty) return null;
      // **لا نبدأ بالأعلى نطاقاً بعد الآن**: السجلات أثبتت أن الطبقة الأعلى
      // هي بالضبط ما يفشل جلبه (شريحة تزحف ثوانيَ ثم يُقطع الاتصال)، بينما
      // مشغّل الموقع نفسه يشتغل بنجاح على جودة أدنى بنفس اللحظة. الترتيب
      // الآن بالأفضلية الفعلية — المُثبَتة من WebView أولاً — مع الإبقاء
      // على كل الجودات متاحة للاختيار اليدوي (راجع TECHNICAL.md #50).
      final prioritized = HlsVariantSelector.prioritize(
        variants,
        provenKeys: _webProvenVariantKeys,
      );
      _slog(
        'HLS_VARIANTS_PRIORITIZED',
        'count=${prioritized.length} proven=${_webProvenVariantKeys.length} '
        'first=${prioritized.first.label}',
      );
      final seen = <String>{};
      final ordered = <MapEntry<String, String>>[];
      for (final v in prioritized) {
        if (seen.add(v.url)) ordered.add(MapEntry(v.label, v.url));
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
        // _headers الأساسي (watch_screen.dart) يضبط 'sec-fetch-site' ثابتاً
        // على 'same-origin' دائماً — قيمة خاطئة بالضبط لنفس هذا المسار
        // (مرشّح CDN منفصل تماماً عن صفحة التضمين، وهذا سبب وجود فحص
        // sameOrigin أعلاه أصلاً لـorigin/referer). متصفح حقيقي يرسل
        // 'cross-site' هنا؛ قيمة ثابتة خاطئة تتناقض مع Origin/Referer
        // المرسَلين بنفس الطلب — نمط كشف بوتات معروف (فحص تطابق
        // Sec-Fetch-Site مع Origin الفعلي). لم يُختبَر بسجل بعد أن هذا هو
        // سبب رفض CDN تحديداً — تصحيح منطقي مبني على قراءة الكود، صفر
        // مخاطرة (تصحيح قيمة خاطئة أصلاً، لا تغيير بتوقيت/تزامن الجلب).
        headers['sec-fetch-site'] = 'cross-site';
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
      final result = await controller.runJavaScriptReturningResult(kCaptureWebContextScript);
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
      final result = await controller.runJavaScriptReturningResult(kSmartInteractionScript);
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
      final result = await controller.runJavaScriptReturningResult(kDetectFrameworkSourcesScript);
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
      final result = await controller.runJavaScriptReturningResult(kPlayerFocusScript);
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

    if (!_webSiteRecipeLoaded) {
      _webSiteRecipeLoaded = true;
      final entryHost = _webEntryHost;
      if (entryHost != null && entryHost.isNotEmpty) {
        _webSiteRecipe = await SiteRecipeService.load(entryHost);
        if (_webSiteRecipe != null) {
          _slog(
            'SITE_RECIPE_LOADED',
            'entryHost=$entryHost targetHost=${_webSiteRecipe!.targetHost} playerMode=${_webSiteRecipe!.playerMode}',
          );
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
          final recipe = _webSiteRecipe;
          final recipeMatch = recipe != null && candidateHost == recipe.targetHost.toLowerCase();
          _slog(
            'IFRAME_POLL_CANDIDATE',
            'url=${_safeLogUrl(iframeCandidate)} playerish=$playerish crossHost=${candidateHost != currentHost} recipeMatch=$recipeMatch',
          );
          if (playerish || candidateHost != currentHost || recipeMatch) {
            if (recipeMatch) {
              // وصفة موقع متعلّمة: هذا الدومين بالضبط سبق ونجح معه هذا
              // المضيف — نضبط نوع المشغّل فوراً بدل انتظار اكتشافه من صيغة
              // الرابط لاحقاً بـonPageFinished، فتبدأ محاولات التنشيط
              // (priming) من أول دورة بعد الترقية مباشرة.
              if (recipe!.playerMode == 'vidmoly') {
                _webVidmolyPlayerMode = true;
              } else if (recipe.playerMode == 'videojs') {
                _webVideoJsPlayerMode = true;
              }
            }
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
      await controller.runJavaScript(kVideoJsPrimeScript);
    } catch (_) {}
  }

  Future<void> _primeVidmolyPlayback(WebViewController controller) async {
    try {
      await controller.runJavaScript(kVidmolyPrimeScript);
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
    _webMainFrameLoadFailed = false;
    _webHumanVerificationDetected = false;
    _webVerificationCheckInFlight = false;
    _webEntryHost = null;
    _webSiteRecipe = null;
    _webSiteRecipeLoaded = false;
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
    // إثبات الجودة خاص بجلسة/شبكة/مصدر بعينه — حلقة أخرى قد تكون على CDN
    // مختلف تماماً، فلا يُورَّث الإثبات القديم.
    _webProvenVariantKeys.clear();
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
      _webEntryHost = sourceUri.host;
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
                // Ad/popup hosts named in _isDangerousWebUrl are already
                // rejected above, but that list always lags one step behind
                // new ad domains (confirmed by real logs: sw.muralssouth.shop,
                // trendyol.com.in, amzn.to none of which matched any keyword).
                // Once promoted, only allow a further top-level jump to a
                // host this session has actually seen serve real player
                // traffic — see _isTrustedNavigationHost for why that's a
                // reliable, name-agnostic stand-in for "is this an ad".
                if (!_webPromotedPlayerMode) {
                  _slog(
                    'NAV_BLOCKED_CROSS_ORIGIN',
                    'from=$originHost to=$requestHost promoted=$_webPromotedPlayerMode',
                  );
                  return NavigationDecision.prevent;
                }
                // Confirmed regression by a real log (dororo/ristoanime.me):
                // vidmoly.net immediately redirects its own embed page to
                // vidmoly.biz — a same-service, different-TLD mirror, the
                // exact first hop right after promotion, before this session
                // has registered a single real candidate yet. That's normal,
                // legitimate behavior for this class of site (mirrors rotate
                // TLDs to dodge blocking) — blocking it here with nothing yet
                // in _webCandidateRegistry to call it "trusted" left the page
                // stuck re-polling the same dead candidate forever (confirmed
                // in the log: 7+ IFRAME_POLL_CANDIDATE with zero progress).
                // So only enforce the trusted-host allowlist once this
                // session has actually registered real candidate traffic —
                // every ad hijack confirmed so far (sw.muralssouth.shop,
                // nfs.watchd.click, webls.net) happened well after that point
                // (dozens of HLS_CANDIDATE_FROM_JS entries already logged),
                // so this still catches all of them without blocking the
                // very first, evidence-free redirect a legitimate mirror needs.
                if (_webCandidateRegistry.isNotEmpty &&
                    !_isTrustedNavigationHost(requestHost)) {
                  _slog(
                    'NAV_BLOCKED_UNTRUSTED_HOST',
                    'from=$originHost to=$requestHost promoted=true',
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
            // WebView calls onPageFinished even for a navigation that just
            // failed at the network level — confirmed by a real log where
            // onWebResourceError had already set _state = error for
            // ERR_CONNECTION_RESET on the main frame, only for this exact
            // callback to fire right after and silently reset it back to
            // loading, then kick a full discovery cycle against a page that
            // never actually loaded (9 scans in a row, 0 candidates every
            // time — the error was correct, this callback just overwrote
            // it). onWebResourceError already tried an alternate server or
            // settled on the error screen; there is nothing here to do.
            if (_webMainFrameLoadFailed) return;
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
              // نفس إصلاح _revealVidmolyPlayer/_revealVideoJsPlayer (سجل
              // #44) — نسخة ثالثة من نفس منطق "إظهار WebView جاهزاً" فاتها
              // نفس الإصلاح: بدون _webPlaybackReady=true هنا، أي محاولة
              // تشغيل أصلي لاحقة (مرشّح HLS يُكتشَف بعدها بثوانٍ عبر حلقة
              // الاكتشاف العادية — "الناجح trial يُتخطّى" بالتعليق تحت غير
              // صحيح فعلياً، يحصل كثيراً) تفرض _state=loading من جديد عبر
              // حارس _playServerQuality (`!(fallbackToWeb && _webPlaybackReady)`)
              // فتغطي شاشة تحميل فيديو WebView الشغّال فعلاً تحتها لحظياً —
              // مؤكَّد بسجلات فعلية متعددة (native trial يفشل بعد 9 ثوانٍ
              // متكررة بينما segmentEvidence=true مستمر طوال الوقت).
              _webPlaybackReady = true;
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
              _webMainFrameLoadFailed = true;
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
