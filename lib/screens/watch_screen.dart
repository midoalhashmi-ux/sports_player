import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

import '../services/ad_service.dart';
import '../services/candidate_scoring.dart';
import '../services/channel_source_resolver.dart';
import '../services/stream_models.dart';
import '../services/api_source_resolver.dart';
import '../services/hls_cache_proxy.dart';
import '../services/native_cookie_service.dart';
import '../services/player_strategies/player_strategy.dart';
import '../services/player_visibility_service.dart';
import '../services/preferred_server_service.dart';
import '../services/site_recipe_service.dart';
import '../services/stream_network_client.dart';
import '../services/session_log_service.dart';
import '../theme/app_theme.dart';

// محرك اكتشاف مصدر WebView -> Native (كل _web* السابقة) صار mixin منفصل
// فيزيائياً بملف خاص — راجع الشرح الكامل أعلى watch_screen_discovery.dart.
part 'watch_screen_discovery.dart';

enum _LoadState { loading, error, ready }

class _ResolvedPublicUrl {
  final String url;
  final Map<String, String> headers;
  const _ResolvedPublicUrl(this.url, this.headers);
}

/// انكماش خفيف عند الضغط ورجوع فوري عند الإفلات — نفس إحساس الاستجابة
/// السريعة بأزرار يوتيوب. لا يستبدل onTap الأصلي للـchild (عادة InkWell
/// يوفّر تأثير التموّج)، فقط يضيف حركة قياس فوقه.
class _BouncyPress extends StatefulWidget {
  final Widget child;
  const _BouncyPress({required this.child});

  @override
  State<_BouncyPress> createState() => _BouncyPressState();
}

class _BouncyPressState extends State<_BouncyPress> {
  double _scale = 1.0;

  void _set(double value) {
    if (mounted) setState(() => _scale = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(0.86),
      onPointerUp: (_) => _set(1.0),
      onPointerCancel: (_) => _set(1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
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

/// نتيجة _relayManifestViaWebView: إما قائمة جودات مكتشفة (تسمية + رابط،
/// من master playlist)، أو ملف m3u8 محلي جاهز للتشغيل مباشرة (من media
/// playlist).
class _RelayedManifest {
  final List<MapEntry<String, String>>? variants;
  final File? localFile;
  const _RelayedManifest._({this.variants, this.localFile});

  factory _RelayedManifest.variants(List<MapEntry<String, String>> variants) =>
      _RelayedManifest._(variants: variants);
  factory _RelayedManifest.localFile(File file) =>
      _RelayedManifest._(localFile: file);

  bool get isLocalFile => localFile != null;

  String describe() => isLocalFile
      ? 'local_file(${localFile!.path.split('/').last})'
      : 'variants(${variants?.length ?? 0})';
}

/// A short-lived registry for media candidates observed during the current
/// WebView session. URLs are discovered from the page/session only; they are
/// never persisted or hard-coded.
class _WebNetworkCandidate {
  final String url;
  final String source;
  String type;
  final DateTime timestamp;
  String pageUrl;
  String frameUrl;
  String referer;
  String mime;
  int evidenceScore;
  bool validated = false;
  bool failed = false;
  bool quarantined = false;

  _WebNetworkCandidate({
    required this.url,
    required this.source,
    required this.type,
    required this.timestamp,
    required this.pageUrl,
    required this.frameUrl,
    required this.referer,
    required this.mime,
    this.evidenceScore = 0,
  });
}

/// مرشّح واحد أثناء مرحلة الفحص المتوازي في _autoDetectWebSource — يحمل
/// نتيجة الفحص الشبكي (حين يُنفَّذ) ليُقرأ بعد اكتمال كل المرشحين معاً
/// بدل انتظار كل واحد على حدة.
class _CandidateProbe {
  final String source;
  final _WebNetworkCandidate? registered;
  final int score;
  final int evidence;
  final bool strongHls;
  final bool strongFramework;
  Map<String, String> headers = const {};
  bool validated = false;

  _CandidateProbe({
    required this.source,
    required this.registered,
    required this.score,
    required this.evidence,
    required this.strongHls,
    required this.strongFramework,
  });
}

/// One authoritative state machine for a WebView -> Native detection session.
/// It replaces the fragile combination of overlapping booleans/timers.
enum _WebSessionState {
  idle,
  loadingPage,
  webReady,
  interacting,
  discovering,
  validating,
  nativeTrial,
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
  // اسم الحلقة/الفيلم المعروض بأعلى شاشة المشاهدة (مثل يوتيوب) — اختياري
  // تماماً: مصدره إما رابط عميق من BinSheikh (title=...) أو رابط محفوظ
  // يدوياً (SavedLink.title). غيابه لا يعطّل أي شيء، فقط لا يظهر الشريط.
  final String? title;

  const WatchScreen({
    super.key,
    this.channelId,
    this.externalUrl,
    this.externalUserAgent,
    this.title,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen>
    with WidgetsBindingObserver, _StreamDiscoveryMixin {
  // نفس التسمية المستخدمة عند إنشاء سيرفر لمرشّح مُكتشَف تلقائياً من
  // WebView (_autoDetectWebSource) — تُستخدم كعلامة موثوقة لتمييز هذا
  // النوع من السيرفرات (روابطها دائماً وسائط حقيقية مُثبَتة، لا صفحات
  // ويب) عن سيرفرات CMS متعددة المصادر (channels.sources[]، روابطها
  // غالباً صفحات ويب كاملة تحتاج فتحاً لا تشغيلاً مباشراً).
  // كانت static const — تحوّلت لـgetter عادي (نفس القيمة بالضبط) لأن
  // static members لا تُورَّث عبر آلية mixin، و_StreamDiscoveryMixin
  // يحتاج يقرأها كعضو instance عادي (راجع تعليق watch_screen_discovery.dart).
  @override
  String get _autoDiscoveredServerLabel => 'المصدر المكتشف تلقائياً';

  VideoPlayerController? _controller;
  late final HlsCacheProxy _hlsCacheProxy;
  @override
  WebViewController? _webController;
  @override
  bool _isWebSource = false;
  final GlobalKey _videoBoundaryKey = GlobalKey();

  @override
  _LoadState _state = _LoadState.loading;
  @override
  String _errorMessage = '';
  @override
  StreamSession? _session;
  @override
  StreamServerOption? _activeServer;
  @override
  StreamQuality? _activeQuality;
  @override
  Map<String, String>? _headers;
  @override
  Map<String, String>? _resolvedStreamHeaders;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _bufferIndicatorVisible = false;
  Timer? _slowConnectionTimer;
  Timer? _bufferIndicatorTimer;
  bool _slowConnectionHint = false;
  // مراقب انقطاع طويل أثناء المشاهدة (وليس عند البدء — ذاك له منطق منفصل
  // بالكامل بمسار الاكتشاف): تخزين مؤقت بدون تقدّم لفترة طويلة يعني الاتصال
  // مات فعلياً غالباً، لا مجرد بطء عابر. بدون هذا كان المستخدم يبقى عالقاً
  // على مؤشر تحميل للأبد بدون أي مخرج غير الخروج يدوياً من الشاشة.
  Timer? _stallNudgeTimer;
  Timer? _stallGiveUpTimer;
  bool _stallNudgeAttempted = false;
  // شبكة ضعيفة تجعل ExoPlayer يرمي خطأ فعلياً (لا مجرد تخزين مؤقت بلا تقدّم،
  // ذاك مغطّى بمراقب الانقطاع أعلاه) — كان يظهر شاشة خطأ كاملة فوراً تحتاج
  // ضغطة "إعادة المحاولة" يدوياً حتى لو كانت الشبكة تعافت خلال ثوانٍ. الآن
  // نعيد الاتصال تلقائياً بصمت (نفس السيرفر/الموضع) عدة مرات بتأخير متزايد،
  // ولا نعرض شاشة الخطأ إلا بعد استنفاد المحاولات أو ضغط المستخدم للإيقاف
  // بنفسه (_userPausedPlayback) — عندها لا نزاحمه بمحاولات تلقائية إطلاقاً.
  Timer? _nativeReconnectTimer;
  int _nativeAutoReconnectAttempts = 0;
  bool _userPausedPlayback = false;
  // مؤشر جيل لكل استدعاء لـ_playServerQuality — مؤكَّد بسجل تشخيص فعلي:
  // إعادة اتصال تلقائية صامتة (_handleNativePlaybackError، fallbackToWeb
  // الافتراضي false) ومحاولة تجربة ثانية قادمة من اكتشاف WebView
  // (fallbackToWeb=true) قد تعملان بالتوازي فعلياً على نفس القناة —
  // الثانية نجحت (PLAY_SERVER_QUALITY_SUCCESS) بينما الأولى، القديمة
  // فعلياً وغير ذات صلة، كانت لا تزال عالقة داخل initialize().timeout(9s)
  // الخاص بها. لما انتهت أخيراً بفشل (Timeout)، فرع catch العام (fallbackToWeb
  // false) نفّذ setState(_state = error) بلا أي شرط — يمسح حالة النجاح
  // الحقيقية فوراً رغم أن المتحكم (_controller) الفعلي الناجح لم يُمس إطلاقاً،
  // فيستمر صوت المصدر يُسمع خلف شاشة الخطأ. الحل: كل استدعاء يحجز رقم جيل
  // فريد عند بدايته، ويتحقق منه قبل أي setState نهائي — استدعاء قديم تجاوزه
  // استدعاء أحدث يتجاهل نتيجته (نجاحاً كان أو فشلاً) بصمت بدل الكتابة فوق
  // حالة قد تكون أحدث وأصح.
  int _playAttemptGeneration = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100;
  bool _muted = false;
  bool _fullscreen = false;
  bool _isLandscape = true;

  bool _locked = false;
  BoxFit _fit = BoxFit.contain;
  String? _seekFeedback;
  // مجموع الثواني المتراكمة بنفس الاتجاه خلال نافذة التغذية الراجعة —
  // مثل يوتيوب: نقر مزدوج متكرر بسرعة بنفس الجهة يظهر "+20"، "+30"... بدل
  // إعادة البدء من +10 كل مرة.
  int _seekFeedbackAccumulated = 0;
  Timer? _seekFeedbackTimer;
  // مثل يوتيوب: كرة شريط التقدّم تظهر فقط أثناء السحب الفعلي، غير ذلك
  // خط نظيف بلا كرة دائمة الظهور.
  bool _isScrubbingSlider = false;
  bool _wasPlayingBeforeScrub = false;

  // شارة نصية مؤقتة وسط الشاشة (وضع العرض عند كل نقرة تبديل، ونسبة التكبير
  // أثناء التقريب/الإبعاد بإصبعين) — شكل عام واحد يُستخدم للاثنين.
  String? _centerToast;
  Timer? _centerToastTimer;

  // تكبير/تصغير بإصبعين (مثل MX Player): 1.0 = 100% الحجم الطبيعي.
  double _zoomScale = 1.0;
  double _zoomGestureBaseScale = 1.0;

  // speed / screenshot
  double _playbackSpeed = 1.0;
  bool _savingScreenshot = false;

  // swipe/scale — بوابة واحدة موحّدة (GestureDetector لا يسمح بخلط
  // onHorizontalDrag*/onVerticalDrag* مع onScale* على نفس الأداة، والتكبير
  // بإصبعين يحتاج onScale أصلاً) — سحبة إصبع واحد تُقفَل على محور أفقي
  // (تقديم/تأخير) أو رأسي (صوت) حسب أي اتجاه تحرّك أكثر أولاً، ولمسّتان
  // تُعامَلان دائماً كتكبير بغض النظر عن أي قفل محور سابق.
  Offset? _swipeStart;
  bool _seekingFromSwipe = false;
  String? _dragAxisLock; // null | 'h' | 'v' | 'zoom'

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
      if (_sessionStarted) return;
      if (mounted && identical(_activeInstance, this)) {
        _sessionStarted = true;
        _startSession();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _hlsCacheProxy = HlsCacheProxy(onLog: _slog);
    SessionLogService.instance.startSession(
      'channelId=${widget.channelId} externalUrl=${widget.externalUrl}',
    );
    // A video screen is landscape-first. The explicit orientation button
    // below is the only thing that switches it back to portrait.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_setPlayerOrientation(true));
    });
    unawaited(_prepareAndStartPlayback());
  }

  Future<void> _setPlayerOrientation(bool landscape) async {
    if (mounted) {
      setState(() {
        _isLandscape = landscape;
        if (!landscape) _fullscreen = false;
      });
    }
    try {
      await SystemChrome.setPreferredOrientations(
        landscape
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ],
      );
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {
      // Orientation control is best effort on platforms that do not expose it.
    }
  }

  Future<void> _toggleOrientation() async {
    await _setPlayerOrientation(!_isLandscape);
    _scheduleHide();
  }

  // ---------------------- player listener ----------------------
  void _videoListener() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      _slog('NATIVE_PLAYBACK_ERROR', 'position=${value.position} error=${value.errorDescription}');
      _handleNativePlaybackError();
      return;
    }
    final wasBuffering = _isBuffering;
    // Some Android media backends leave isBuffering=true for one or more
    // callbacks after a seek. If playback is already advancing, that flag
    // is stale and must not leave a permanent spinner on screen.
    final positionAdvanced = value.isPlaying && value.position > _position;
    final effectiveBuffering = value.isBuffering && !positionAdvanced;
    final playingChanged = _isPlaying != value.isPlaying;
    final bufferingFlagChanged = _isBuffering != effectiveBuffering;
    // Update the raw fields unconditionally (the stall watchdog and the
    // progress bar/time text next time controls are shown both need
    // accurate values), but only ask Flutter to rebuild this whole
    // screen when something actually visible changed, or the on-screen
    // progress bar/time text needs the fresh position while it's shown.
    // video_player fires this listener several times a second during
    // normal playback; rebuilding the entire Stack (many Positioned/
    // AnimatedOpacity children) on every tick for no visible reason was
    // wasted work landing on the same frame as decode/render — reported
    // as a brief, recurring stutter across several unrelated sources,
    // which points at UI-thread jank rather than a per-source issue.
    _isPlaying = value.isPlaying;
    _isBuffering = effectiveBuffering;
    _position = value.position;
    _duration = value.duration;
    if (playingChanged || bufferingFlagChanged || _controlsVisible) {
      setState(() {});
    }
    if (effectiveBuffering && !wasBuffering) {
      _slog('NATIVE_BUFFERING_START', 'position=${value.position} isPlaying=${value.isPlaying}');
      _bufferIndicatorTimer?.cancel();
      if (!_bufferIndicatorVisible) {
        setState(() => _bufferIndicatorVisible = true);
      }
      // A stale buffering flag must never cover a healthy video forever.
      _bufferIndicatorTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _bufferIndicatorVisible) {
          setState(() => _bufferIndicatorVisible = false);
        }
      });
      _startSlowConnectionTimer();
      _startStallWatchdog();
    } else if (!effectiveBuffering && wasBuffering) {
      _slog('NATIVE_BUFFERING_END', 'position=${value.position}');
      _bufferIndicatorTimer?.cancel();
      _bufferIndicatorTimer = null;
      if (_bufferIndicatorVisible) {
        setState(() => _bufferIndicatorVisible = false);
      }
      _cancelSlowConnectionTimer();
      _cancelStallWatchdog();
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

  void _cancelStallWatchdog() {
    _stallNudgeTimer?.cancel();
    _stallNudgeTimer = null;
    _stallGiveUpTimer?.cancel();
    _stallGiveUpTimer = null;
    _stallNudgeAttempted = false;
  }

  // مراقبة تخزين مؤقت طويل بدون تقدّم أثناء مشاهدة فعلية (بعد نجاح
  // التشغيل، وليس فشل البدء الأولي — ذاك منفصل تماماً بمنطق الاكتشاف).
  // محاولة إنعاش واحدة (seekTo لنفس الموضع يجبر إعادة طلب البيانات من
  // الخادم — يحل مشاكل اتصال ماتت فعلياً دون أي علامة خطأ صريحة)، فإذا
  // ما نفعت خلال مهلة إضافية، الانتقال لشاشة الخطأ الموجودة (بزر إعادة
  // المحاولة المعروف) بدل ترك المستخدم عالقاً على مؤشر تحميل للأبد.
  void _startStallWatchdog() {
    _stallNudgeTimer?.cancel();
    _stallNudgeTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || !_isBuffering || _stallNudgeAttempted) return;
      _stallNudgeAttempted = true;
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        _slog('NATIVE_STALL_RECOVERY_NUDGE', 'position=${controller.value.position}');
        controller.seekTo(controller.value.position);
      }
      _stallGiveUpTimer?.cancel();
      _stallGiveUpTimer = Timer(const Duration(seconds: 20), () {
        if (!mounted || !_isBuffering) return;
        _slog('NATIVE_STALL_GIVE_UP', 'position=$_position');
        setState(() {
          _state = _LoadState.error;
          _errorMessage = 'انقطع الاتصال أثناء التشغيل. جرّب مرة أخرى أو غيّر السيرفر.';
        });
      });
    });
  }

  void _cancelSlowConnectionTimer() {
    _slowConnectionTimer?.cancel();
    _slowConnectionTimer = null;
    if (_slowConnectionHint) setState(() => _slowConnectionHint = false);
  }

  void _cancelNativeReconnect() {
    _nativeReconnectTimer?.cancel();
    _nativeReconnectTimer = null;
    _nativeAutoReconnectAttempts = 0;
  }

  // شبكة ضعيفة تجعل ExoPlayer يرمي خطأ فعلياً (value.hasError) بدل مجرد
  // التخزين المؤقت — كان هذا يُظهر شاشة الخطأ الكاملة فوراً ويحتاج ضغطة
  // "إعادة المحاولة" يدوياً حتى لو تعافت الشبكة خلال ثوانٍ. نعيد المحاولة
  // تلقائياً بصمت (نفس السيرفر والجودة، تكمل من آخر موضع عبر resumeFrom
  // بـ_playServerQuality) بتأخير متزايد، ونتوقف فوراً لو ضغط المستخدم زر
  // الإيقاف بنفسه (_userPausedPlayback) — لا نزاحمه بمحاولات تلقائية. بعد
  // عدد كافٍ من المحاولات الفاشلة (شبكة ميتة فعلياً، لا مجرد بطء) نستسلم
  // لشاشة الخطأ المعروفة (بزر إعادة المحاولة وتغيير السيرفر).
  static const int _nativeMaxAutoReconnectAttempts = 8;

  void _handleNativePlaybackError() {
    if (!mounted) return;
    final server = _activeServer;
    final quality = _activeQuality;
    if (_userPausedPlayback ||
        server == null ||
        quality == null ||
        _nativeAutoReconnectAttempts >= _nativeMaxAutoReconnectAttempts) {
      _cancelNativeReconnect();
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'تعذر تشغيل رابط البث. جرّب مرة أخرى أو غيّر السيرفر.';
      });
      return;
    }
    _nativeAutoReconnectAttempts++;
    // تأخير شبه فوري بدل ثوانٍ كاملة — أول محاولة بعد 200ms فقط، يزيد
    // تدريجياً كل محاولة فاشلة (حتى لا يضرب خادماً ميتاً فعلياً بحلقة
    // ضيقة)، بحد أقصى 2 ثانية فقط حتى بأبعد محاولة.
    final delayMs = (200 * _nativeAutoReconnectAttempts).clamp(200, 2000);
    _slog(
      'NATIVE_AUTO_RECONNECT',
      'attempt=$_nativeAutoReconnectAttempts/$_nativeMaxAutoReconnectAttempts delay=${delayMs}ms position=$_position',
    );
    if (!_isBuffering) setState(() => _isBuffering = true);
    _nativeReconnectTimer?.cancel();
    _nativeReconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || _userPausedPlayback) return;
      unawaited(_playServerQuality(server, quality));
    });
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
      _slog('RESOLVE_CHANNEL_URL', 'initialUrl=${_safeLogUrl(initialUrl)}');
      final parsedInitial = Uri.tryParse(initialUrl);
      final isSpaRoute = parsedInitial != null && parsedInitial.fragment.isNotEmpty;
      if (isSpaRoute) {
        _slog('SPA_ROUTE_DETECTED', 'handing full URL to WebView unresolved');
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
      _slog('API_SOURCE_RESOLVER', 'candidates=${apiCandidates.length}');
      for (final candidate in apiCandidates.take(5)) {
        if (!_isDirectPlayable(candidate.url)) {
          _slog('API_CANDIDATE_SKIPPED', 'url=${_safeLogUrl(candidate.url)} reason=not_direct_playable');
          continue;
        }
        _resolvedStreamHeaders = candidate.headers;
        final lower = candidate.url.toLowerCase();
        final kind = (lower.contains('.m3u8') || lower.contains('.m3u')) ? StreamKind.hls
            : lower.contains('.mpd') ? StreamKind.dash
            : StreamKind.progressive;
        // video_player_android (ExoPlayer) has supported DASH natively since
        // well before the version pinned in pubspec.yaml, so DASH candidates
        // are played the same as HLS/MP4 — see _playServerQuality's
        // formatHint, which is what actually tells ExoPlayer to use its DASH
        // extractor instead of guessing from the URL alone.
        _slog('API_CANDIDATE_ACCEPTED', 'url=${_safeLogUrl(candidate.url)} kind=$kind');
        return StreamSession.success(
          kind: kind,
          isLive: true,
          servers: [
            StreamServerOption(
              label: 'المصدر',
              qualities: [StreamQuality(label: 'تلقائي', url: candidate.url)],
            ),
          ],
        );
      }

      final resolvedUrl = await _resolveStreamUrl(initialUrl);
      if (resolvedUrl == null) {
        _slog('RESOLVE_STREAM_URL_FAILED', 'initialUrl=${_safeLogUrl(initialUrl)}');
        return StreamSession.failure('تعذر حل رابط البث.');
      }
      _slog('RESOLVE_STREAM_URL_RESULT', 'resolvedUrl=${_safeLogUrl(resolvedUrl)}');

      final lower = resolvedUrl.toLowerCase();
      final isHls = lower.contains('.m3u8') || lower.contains('.m3u');
      final isDash = lower.contains('.mpd');
      final isProgressive = lower.contains('.mp4') || lower.contains('.webm') || lower.contains('.mov');

      StreamKind kind;
      if (isHls) {
        kind = StreamKind.hls;
      } else if (isDash) {
        kind = StreamKind.dash;
      } else if (isProgressive) {
        kind = StreamKind.progressive;
      } else {
        kind = StreamKind.web;
      }

      return StreamSession.success(
        kind: kind,
        isLive: true,
        servers: [
          StreamServerOption(
            label: 'المصدر ',
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
        if (location == null || location.isEmpty) {
          _slog('FETCH_HOP', 'url=${_safeLogUrl(currentUrl)} status=${response.statusCode} reason=empty_redirect_location');
          return null;
        }
        final next = uri.resolve(location).toString();
        _slog('FETCH_HOP_REDIRECT', 'from=${_safeLogUrl(currentUrl)} to=${_safeLogUrl(next)} status=${response.statusCode}');
        return _ResolvedPublicUrl(next, headers);
      }

      if (response.statusCode < 200 || response.statusCode >= 400) {
        _slog('FETCH_HOP', 'url=${_safeLogUrl(currentUrl)} status=${response.statusCode} reason=bad_status');
        return null;
      }

      final responseHeaders = <String, String>{...headers};
      final body = response.body;

      if (contentType.contains('mpegurl') || contentType.contains('dash+xml') ||
          _isDirectPlayable(currentUrl) || _containsMediaMarker(body)) {
        _slog('FETCH_HOP_DIRECT_MEDIA', 'url=${_safeLogUrl(currentUrl)} contentType=$contentType');
        return _ResolvedPublicUrl(currentUrl, responseHeaders);
      }

      final candidates = <_DecodedPayload>{};
      _collectPayloadCandidates(body, candidates, currentUrl: currentUrl);

      for (final candidate in candidates) {
        final direct = _extractBestUrl(candidate.text, currentUrl);
        if (direct != null) {
          final resolved = _resolveRelativeUrl(direct, currentUrl);
          // شبكة أمان إضافية: _extractUrlDeep (مسار JSON، أعلى بهذي الدالة)
          // يرجّع أول رابط موجود بحقل معروف (url/src/stream/...) بلا أي
          // تحقق من نوعه — لو كان ملف مفتاح تشفير/شريحة خام صدفةً بأحد هذي
          // الحقول، نتجاهله هنا بدل تسليمه كرابط تشغيل نهائي مؤكَّد الفشل.
          if (CandidateScoring.isNonMediaAsset(resolved)) continue;
          if (_isDirectPlayable(resolved)) {
            return _ResolvedPublicUrl(resolved, responseHeaders);
          }
          if (resolved.startsWith('http')) {
            return _ResolvedPublicUrl(resolved, responseHeaders);
          }
        }
      }

      return _ResolvedPublicUrl(currentUrl, responseHeaders);
    } catch (e) {
      _slog('FETCH_HOP_EXCEPTION', 'url=${_safeLogUrl(currentUrl)} error=$e');
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
        _looksLikeJson(text) || lower.contains('.m3u8') || lower.contains('.m3u') || lower.contains('.mpd') ||
        lower.contains('#extm3u') || lower.contains('"url"') ||
        lower.contains('"stream"') || lower.contains('"source"') ||
        lower.contains('<video') || lower.contains('<iframe');
  }

  bool _containsMediaMarker(String text) => CandidateScoring.containsMediaMarker(text);

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
      // نفس فئة خطأ مفتاح التشفير/الشريحة الخام المُصلَحة بمحرك اكتشاف
      // WebView (راجع CandidateScoring.isNonMediaAsset) — هذا المسار
      // المنفصل (استخراج رابط من JSON/نص صفحة عام) كان يفتقد نفس الفحص،
      // فيقدر يختار ملفاً غير قابل للتشغيل إطلاقاً لمجرد احتوائه "/hls/"
      // بمساره. استبعاده هنا يترك الفرصة لمرشّح آخر حقيقي بنفس النص.
      if (CandidateScoring.isNonMediaAsset(candidate)) continue;
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

  /// تحويل الرابط النسبي إلى مطلق.
  @override
  String _resolveRelativeUrl(String url, String baseUrl) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.isAbsolute) return url;
    final base = Uri.parse(baseUrl);
    return base.resolveUri(uri).toString();
  }

  /// التحقق من أن الرابط قابل للتشغيل مباشرة.
  bool _isDirectPlayable(String url) => CandidateScoring.isDirectPlayable(url);

  bool _looksLikeJson(String text) => CandidateScoring.looksLikeJson(text);

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

  @override
  Map<String, String> _effectiveStreamHeaders() {
    return {
      ..._headers ?? {},
      ...?_webContextHeaders,
      ...?_resolvedStreamHeaders,
    };
  }

  /// يحلّل نص playlist رئيسي (master) بحثاً عن أسطر `#EXT-X-STREAM-INF`
  /// (جودات/معدلات نقل بديلة لنفس المحتوى) ويبني منها قائمة جودات
  /// حقيقية قابلة للاختيار — بدل الاعتماد فقط على رابط واحد. يعمل مع أي
  /// مصدر HLS (لا يخص موقعاً معيّناً)؛ يرجع قائمة فارغة لو النص ليس
  /// playlist رئيسياً (أي مصدر بجودة واحدة فقط، سلوك سابق دون تغيير).
  List<StreamQuality> _parseHlsVariantQualities(String manifestText, Uri baseUri) {
    final lines = manifestText.split('\n');
    final variants = <StreamQuality>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      // أول سطر غير فارغ وغير تعليق بعد #EXT-X-STREAM-INF هو رابط الجودة.
      String? uriLine;
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty || candidate.startsWith('#')) continue;
        uriLine = candidate;
        break;
      }
      if (uriLine == null) continue;
      Uri resolved;
      try {
        resolved = baseUri.resolve(uriLine);
      } catch (_) {
        continue;
      }
      final resMatch = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final height = resMatch != null ? int.tryParse(resMatch.group(1)!) : null;
      final bandwidth = bwMatch != null ? int.tryParse(bwMatch.group(1)!) : null;
      final label = height != null
          ? '${height}p'
          : (bandwidth != null
              ? '${(bandwidth / 1000).round()} كيلوبت/ث'
              : 'جودة ${variants.length + 1}');
      variants.add(StreamQuality(label: label, url: resolved.toString()));
      // رتبة الفرز مطلوبة بالأعلى فقط لو تعدّد الجودات — نخزّن الترتيب
      // عبر إعادة البناء أدناه بدل إبقاء متغيّر مساعد هنا.
    }
    if (variants.length < 2) return const [];
    // الأعلى دقة/معدل نقل أولاً — يطابق تعارف قوائم الجودة بكل المشغلات.
    final withScore = variants.map((q) {
      final h = RegExp(r'^(\d+)p$').firstMatch(q.label);
      final score = h != null ? int.parse(h.group(1)!) : 0;
      return MapEntry(score, q);
    }).toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    // "تلقائي" أولاً يعيد استخدام الرابط الرئيسي نفسه (تكيّفي — ExoPlayer
    // يختار بنفسه حسب سرعة الشبكة، وهذا فعلياً ما يعمل الآن افتراضياً)،
    // يليه كل جودة مُجبَرة صراحة.
    return [
      StreamQuality(label: 'تلقائي', url: baseUri.toString()),
      ...withScore.map((e) => e.value),
    ];
  }

  /// يجلب playlist المصدر المكتشَف تلقائياً بالخلفية (بعد نجاح التشغيل
  /// فعلياً، فلا يؤخّر أول محاولة تشغيل إطلاقاً) ويستبدل قائمة جوداته
  /// الوهمية (خيار واحد فقط) بجودات حقيقية لو كان playlist رئيسياً متعدد
  /// الجودات. أي فشل هنا صامت تماماً — تحسين اختياري، لا يؤثر على
  /// التشغيل الجاري بأي شكل.
  Future<void> _populateHlsQualitiesInBackground(
    StreamServerOption server,
    String masterUrl,
    Map<String, String> headers,
  ) async {
    try {
      final baseUri = Uri.parse(masterUrl);
      final response = await http
          .get(baseUri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final qualities = _parseHlsVariantQualities(response.body, baseUri);
      if (qualities.isEmpty || !mounted) return;
      final updatedServer = StreamServerOption(label: server.label, qualities: qualities);
      // مزامنة قائمة session.servers أفضل جهد فقط — السيرفر المُكتشَف
      // تلقائياً غالباً لا يُدرَج أصلاً بهذه القائمة (يُمرَّر مباشرة كوسيط
      // إلى _playServerQuality بدون إضافته لـ_session.servers)، فتحديث
      // _activeServer أدناه هو ما يُظهر الجودات فعلياً بقائمة الاختيار —
      // لا يجب أن يمنعه فشل هذه المزامنة.
      final session = _session;
      if (session != null) {
        final index = session.servers.indexWhere((s) => identical(s, server));
        if (index >= 0) session.servers[index] = updatedServer;
      }
      setState(() {
        if (identical(_activeServer, server)) {
          _activeServer = updatedServer;
          // أول عنصر بالقائمة الجديدة دائماً "تلقائي" (نفس رابط
          // التشغيل الحالي فعلياً) — يعكس الواقع أن التشغيل الجاري
          // تكيّفي، لا جودة مُجبَرة، فتظهر علامة الاختيار الصحيحة فوراً.
          _activeQuality = updatedServer.qualities.first;
        }
      });
    } catch (_) {
      // تحسين اختياري فقط — أي خطأ (شبكة/تحليل) يُتجاهل بصمت.
    }
  }

  @override
  Future<void> _muteWebForNativeTrial(bool mute) async {
    final web = _webController;
    if (web == null) return;
    try {
      await web.runJavaScript(r"""(() => {
        document.querySelectorAll('video,audio').forEach((v) => {
          try {
            if (mute) {
              if (!v.hasAttribute('data-sports-player-original-muted')) {
                v.setAttribute('data-sports-player-original-muted', v.muted ? '1' : '0');
              }
              v.muted = true;
            } else if (v.hasAttribute('data-sports-player-original-muted')) {
              v.muted = v.getAttribute('data-sports-player-original-muted') === '1';
              v.removeAttribute('data-sports-player-original-muted');
            }
          } catch (_) {}
        });
      })();""".replaceFirst('mute', mute ? 'true' : 'false'));
    } catch (_) {}
  }

  @override
  Future<void> _playServerQuality(
      StreamServerOption server, StreamQuality quality,
      {
        bool fallbackToWeb = false,
        Map<String, String>? playbackHeaders,
        VideoFormat? formatHintOverride,
      }) async {
    final myGeneration = ++_playAttemptGeneration;
    if (fallbackToWeb) {
      _setWebSessionState(_WebSessionState.nativeTrial);
      _smartLog('NATIVE', 'trial started');
    }
    // أي محاولة تشغيل جديدة (يدوية أو تلقائية) تعني نية تشغيل واضحة — تُلغي
    // أي إيقاف سابق طلبه المستخدم بنفسه حتى لا يتعارض مع منطق إعادة
    // الاتصال التلقائي بـ_handleNativePlaybackError.
    _userPausedPlayback = false;
    _slog(
      'PLAY_SERVER_QUALITY_START',
      'url=${_safeLogUrl(quality.url)} fallbackToWeb=$fallbackToWeb',
    );
    // نفس مشكلة "تُومض شاشة التحميل" الموثّقة أدناه للحالة العكسية: إعادة
    // اتصال تلقائي بعد خطأ شبكي عابر (CDN يقطع الاتصال لحظياً أثناء تشغيل
    // ناجح فعلاً — مؤكَّد بسجل تشخيص فعلي) كانت تهدم عرض الفيديو بالكامل
    // وتستبدله بشاشة تحميل سوداء كاملة (مؤشر + نص) في كل محاولة من الثماني
    // المسموحة بـ_handleNativePlaybackError، فيظهر للمستخدم كأن التطبيق
    // "يفتح ويقفل" الملف بشكل متكرر رغم إن الفيديو نفسه لم يتوقف فعلياً عن
    // العمل (نفس تبديل جودة/سيرفر يدوي أثناء تشغيل فعلي أيضاً يستفيد من هذا
    // — resumeFrom أصلاً يكمل من نفس النقطة، فلا داعي لشاشة تحميل كاملة).
    final wasAlreadyPlayingNative =
        !fallbackToWeb && _state == _LoadState.ready && !_isWebSource;
    setState(() {
      // A background candidate trial fired *after* the WebView's own
      // playback was already proven and shown (_webPlaybackReady) must stay
      // invisible to the user — confirmed via a real debug log: the
      // periodic candidate-discovery timer keeps running even once the
      // video is already playing, so an opportunistic native trial (which
      // usually fails — NATIVE_TRIAL_FAILED, "staying on WebView") was
      // yanking the full-screen loading spinner over top of the actively
      // playing WebView for its whole duration, reading to the user as a
      // spurious "playback failed" flash that "fixes itself" a few seconds
      // later when the next auto-detect cycle re-proves the WebView.
      if (!(fallbackToWeb && _webPlaybackReady) && !wasAlreadyPlayingNative) {
        _state = _LoadState.loading;
      }
      // During a WebView-originated Native trial the browser is the
      // authoritative fallback and must stay mounted/visible until Native
      // playback has been proven.
      _isWebSource = fallbackToWeb ? true : false;
      _activeServer = server;
      _activeQuality = quality;
    });
    try {
      // تبديل جودة/سيرفر يدوي أثناء تشغيل فعلي (مو أول محاولة قادمة من
      // WebView) يجب يكمل من نفس النقطة بدل ما يرجّع الفيديو لبدايته.
      final resumeFrom = (!fallbackToWeb &&
              _controller?.value.isInitialized == true &&
              _position > Duration.zero)
          ? _position
          : null;
      final oldController = _controller;
      oldController?.removeListener(_videoListener);
      await oldController?.dispose();
      await _hlsCacheProxy.stop();

      // Explicit formatHint so ExoPlayer picks its DASH/HLS extractor
      // directly instead of guessing from the URL — needed for DASH sources
      // in particular, since a signed/extension-less .mpd URL would
      // otherwise not be auto-detected correctly.
      final lowerQualityUrl = quality.url.toLowerCase();
      final formatHint = formatHintOverride ??
          (lowerQualityUrl.contains('.mpd')
              ? VideoFormat.dash
              : (lowerQualityUrl.contains('.m3u8') ||
                      lowerQualityUrl.contains('.m3u'))
                  ? VideoFormat.hls
                  : null);

      // وكيل تخزين مؤقت محلي لمصادر HLS فقط (راجع hls_cache_proxy.dart
      // لماذا وكيف اختلفت هذي المحاولة عن الأولى الفاشلة) — اختبار ذاتي
      // داخل start() نفسها يمنع تسليم رابط غير مستجيب لـExoPlayer أصلاً؛
      // أي فشل يرجع للرابط الأصلي المباشر دون أي أثر على السلوك القديم.
      final effectiveHeaders = playbackHeaders ?? _effectiveStreamHeaders();
      var playbackUri = Uri.parse(quality.url);
      var controllerHeaders = effectiveHeaders;
      // ملف محلي (file://) ناتج من إنقاذ WebView (_relayManifestViaWebView)
      // يُمرَّر للوكيل بالضبط كأي مصدر HLS آخر — HlsCacheProxy يقرأ القائمة
      // من القرص مباشرة لهذا المسار (بدل http.Client اللي لا يدعم file://
      // أساساً، راجع hls_cache_proxy.dart) فيستفيد من نفس حماية التخزين/
      // إعادة المحاولة للشرائح البعيدة اللي القائمة تشير إليها. **كان هذا
      // مُتخطّى بالكامل بمحاولة سابقة** (اعتقاداً إن file:// مؤكَّد الفشل
      // دائماً) — لكن سجل تشخيص فعلي لاحق أظهر تقطيعاً شديداً بالضبط
      // بهذا المسار تحديداً (بلا أي حماية HLS_PROXY_* إطلاقاً أثناء
      // التشغيل)، فتأكَّد إن تخطّيه كان الخطأ الفعلي، لا الحل.
      if (formatHint == VideoFormat.hls) {
        final proxied = await _hlsCacheProxy.start(
          sourceUrl: quality.url,
          headers: effectiveHeaders,
        );
        if (proxied != null) {
          playbackUri = proxied;
          controllerHeaders = const {};
        }
      }

      final newController = VideoPlayerController.networkUrl(
        playbackUri,
        formatHint: formatHint,
        httpHeaders: controllerHeaders,
      );
      _controller = newController;
      _position = resumeFrom ?? Duration.zero;
      _duration = Duration.zero;
      _isPlaying = false;
      newController.addListener(_videoListener);
      if (fallbackToWeb) await _muteWebForNativeTrial(true);
      // شبكة أمان عامة: مؤكَّد بسجل تشخيص فعلي أن initialize() قد يعلق
      // بلا نجاح ولا فشل مسجَّل لأكثر من 40 ثانية (بلا هذا الحد). أي تعليق
      // فعلي الآن يتحوّل لفشل واضح ومسجَّل خلال مهلة محدودة، فيدخل بمسار
      // المعالجة/إعادة الاتصال الموجود بدل تعليق صامت غير مشخَّص.
      // خُفِّضت من 15 إلى 9 ثوانٍ: سجلات تشخيص فعلية متعددة تُظهر أن أي
      // تشغيل ناجح فعلياً يكتمل خلال 3-5 ثوانٍ كحد أقصى (مهما كان المصدر)،
      // بينما مرشّح ميت فعلياً (اتصال CDN منقطع) كان يُهدر المهلة الكاملة
      // 15 ثانية قبل الانتقال للمرشّح التالي — مع وجود مرشّحين محتملين أو
      // أكثر بجلسة واحدة هذا يعني حتى 30 ثانية انتظار قبل ما يبدأ المسلسل،
      // رغم إن كلا المرشّحين ميّتان فعلياً من ثوانيهما الأولى.
      await newController.initialize().timeout(
        const Duration(seconds: 9),
        onTimeout: () => throw TimeoutException(
            'native initialize() timed out after 9s — url=${_safeLogUrl(quality.url)}'),
      );
      if (resumeFrom != null) {
        try {
          await newController.seekTo(resumeFrom);
        } catch (_) {}
      }
      await newController.setPlaybackSpeed(_playbackSpeed);
      await newController.setVolume(_muted ? 0 : _volume / 100);
      await newController.play();
      if (fallbackToWeb) {
        await _proveNativePlayback(newController);
      }
      await WakelockPlus.enable();
      _webStartupTimeoutTimer?.cancel();
      if (!mounted) return;
      if (myGeneration != _playAttemptGeneration) {
        // A newer _playServerQuality call already started while this one was
        // awaiting initialize() — this attempt is stale even though it just
        // succeeded. The newer call owns _controller now; dispose our own
        // now-redundant controller instead of leaking it, and touch nothing
        // else (no _state/_controller mutation — the newer call's own
        // success or failure handling is authoritative).
        unawaited(newController.dispose());
        return;
      }
      if (fallbackToWeb) {
        _setWebSessionState(_WebSessionState.nativePlaying);
        // الاكتشاف بالخلفية لم يعد له داعٍ بعد نجاح التشغيل الأصلي — تركه
        // شغّالاً كان يخلّي الصفحة تستمر بالتنقل (تسمح بإعلانات/تحويلات
        // جديدة لم تكن ظاهرة وقت الاكتشاف الأول)، وأحياناً يكتشف "مرشحاً"
        // آخر ويعيد محاولة تشغيل أصلي ثانية فتُهدم النسخة الشغّالة فعلياً
        // ويُعاد إنشاؤها من الصفر — وهذا سبب "إعادة تشغيل الصفحة" العشوائية.
        _webDetectorTimer?.cancel();
        _webDetectorTimer = null;
        _smartLog('NATIVE', 'playback proof success; switching WebView -> Native');
      }
      _slog(
        'PLAY_SERVER_QUALITY_SUCCESS',
        'url=${_safeLogUrl(quality.url)} fallbackToWeb=$fallbackToWeb — final state: ${fallbackToWeb ? 'NATIVE (switched from WebView)' : 'NATIVE (direct)'}',
      );
      _cancelNativeReconnect();
      setState(() {
        _state = _LoadState.ready;
        if (fallbackToWeb) _isWebSource = false;
      });
      // إثراء قائمة الجودات بالخلفية بعد نجاح التشغيل فعلياً — لا يؤخّر
      // أول محاولة تشغيل إطلاقاً (راجع تعليقات الدالة). فقط للسيرفرات
      // المُكتشَفة تلقائياً (رابطها الوحيد وسائط مُثبَتة، لا صفحة ويب)
      // وبصيغة HLS، ولو كان لا يزال بجودة وهمية واحدة فقط.
      if (formatHint == VideoFormat.hls &&
          server.label == _autoDiscoveredServerLabel &&
          server.qualities.length <= 1) {
        unawaited(_populateHlsQualitiesInBackground(
          server,
          quality.url,
          playbackHeaders ?? _effectiveStreamHeaders(),
        ));
      }
      // نجاح تشغيل أصلي حقيقي قادم من اكتشاف WebView — نحفظ مضيف هذا
      // الرابط لنفس القناة حتى تُقدَّم مرشحات نفس المضيف أولاً في الزيارة
      // القادمة (راجع _preferredServerHost في _autoDetectWebSource).
      if (fallbackToWeb) {
        final channelId = widget.channelId;
        final host = Uri.tryParse(quality.url)?.host;
        if (channelId != null && host != null && host.isNotEmpty) {
          unawaited(PreferredServerService.rememberHost(channelId, host));
        }
      }
    } catch (error) {
      if (!mounted) return;
      if (myGeneration != _playAttemptGeneration) {
        // Same staleness as the success path above, mirrored for failure:
        // confirmed by a real log where a silent auto-reconnect call
        // (_handleNativePlaybackError, fallbackToWeb=false) was still stuck
        // inside its own 9s initialize() timeout when a second, newer trial
        // from WebView discovery (fallbackToWeb=true) had already started,
        // taken over _controller, and succeeded. The stale call's eventual
        // TimeoutException fell straight into the unconditional
        // setState(_state = error) below with nothing to stop it — wiping
        // out a playback that was, at that moment, working correctly.
        // _controller now belongs to the newer call; touching it (or
        // _hlsCacheProxy, shared across calls) here would corrupt it.
        return;
      }
      if (fallbackToWeb) {
        final failedController = _controller;
        _controller = null;
        try {
          await failedController?.dispose();
        } catch (_) {}
        unawaited(_hlsCacheProxy.stop());
        await _muteWebForNativeTrial(false);
        final failedUrl = _normalizeCandidate(quality.url);
        _webFailedNativeSources.add(failedUrl);
        _webSeenSources.add(failedUrl);
        final registered = _webCandidateRegistry[failedUrl];
        if (registered != null) {
          registered.failed = true;
          registered.quarantined = true;
        }
        _webCandidateLastReason[failedUrl] = 'native playback failed: ${_describePlaybackError(error)}';
         _smartLog(
           'QUARANTINE',
           'native candidate failed: ${_safeLogUrl(failedUrl)}',
         );
        _slog(
          'NATIVE_TRIAL_FAILED',
          'url=${_safeLogUrl(failedUrl)} error=${_describePlaybackError(error)} rawError=$error nativeAttempts=$_webNativeAttempts/$_webMaxNativeAttempts — staying on WebView',
        );
        unawaited(_logNativeFailureDiagnostics(failedUrl, playbackHeaders));

        // محاولة إنقاذ إضافية (مرة واحدة لكل رابط، ولا تُحتسب من ميزانية
        // المحاولات العادية): لو الرابط الفاشل يشبه HLS، نطلب من WebView
        // نفسه يجيب محتواه بجلسته الحقيقية — راجع _relayManifestViaWebView.
        // مقصور على http(s) لأن ملف محلي (file://) الناتج من إنقاذ سابق على
        // نفس هذا المرشّح لا معنى لإعادة "جلبه عبر WebView" من جديد.
        final failedUri = Uri.tryParse(failedUrl);
        final failedUrlIsHttp = failedUri != null &&
            (failedUri.scheme == 'http' || failedUri.scheme == 'https');
        if (!_webManifestRelayAttemptedUrls.contains(failedUrl) &&
            failedUrlIsHttp &&
            _looksLikeHls(failedUrl) &&
            _webController != null &&
            mounted) {
          _webManifestRelayAttemptedUrls.add(failedUrl);
          final relayed = await _relayManifestViaWebView(failedUrl);
          if (relayed != null && mounted) {
            _slog('MANIFEST_RELAY_SUCCESS',
                'url=${_safeLogUrl(failedUrl)} kind=${relayed.describe()}');
            if (relayed.isLocalFile) {
              // بصيغة file:// (لا مسار عادي) حتى يتعرف Uri.parse بجهة
              // _playServerQuality عليه كرابط صالح — ExoPlayer يدعم رؤوس
              // HTTP مخصّصة حتى مع ملف محلي، وتُطبَّق فعلياً على طلبات
              // السيجمنت البعيدة اللي يذكرها الملف (موثّق من فحص كود
              // video_player_android نفسه).
              final fileUri = Uri.file(relayed.localFile!.path).toString();
              await _playServerQuality(
                StreamServerOption(label: server.label, qualities: [
                  StreamQuality(label: quality.label, url: fileUri)
                ]),
                StreamQuality(label: quality.label, url: fileUri),
                fallbackToWeb: true,
                playbackHeaders: playbackHeaders,
                formatHintOverride: VideoFormat.hls,
              );
              return;
            }
            final qualities = [
              for (final v in relayed.variants!)
                StreamQuality(label: v.key, url: v.value),
            ];
            final relayedServer =
                StreamServerOption(label: server.label, qualities: qualities);
            if (mounted) {
              setState(() {
                _session = StreamSession.success(
                  kind: StreamKind.hls,
                  isLive: _session?.isLive ?? true,
                  servers: [relayedServer],
                );
              });
            }
            await _playServerQuality(
              relayedServer,
              qualities.first,
              fallbackToWeb: true,
              playbackHeaders: playbackHeaders,
              formatHintOverride: VideoFormat.hls,
            );
            return;
          }
          _slog('MANIFEST_RELAY_FAILED', 'url=${_safeLogUrl(failedUrl)}');
          if (!mounted) return;
        }

        _extendWebStartupDeadline(const Duration(seconds: 8));
        _setWebSessionState(_WebSessionState.nativeFailed);
        setState(() {
          _isWebSource = true;
          // Same guard as the trial-start setState above: a trial that
          // failed after the WebView was already proven playing must not
          // yank the loading spinner over it either — leave _state alone
          // (already ready) so the visible video is never interrupted.
          if (!_webPlaybackReady) _state = _LoadState.loading;
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
          _slog(
            'NATIVE_TRIALS_GIVEN_UP',
            'attempts=$_webNativeAttempts/$_webMaxNativeAttempts drmDetected=$_webDrmDetected — final state: WEBVIEW ONLY',
          );
          _setWebSessionState(_webDrmDetected
              ? _WebSessionState.drmWebOnly
              : _WebSessionState.webReady);
          // بدون هذا، _state يبقى "جاري التحميل" للأبد بعد استنفاد كل
          // محاولات التشغيل الأصلي — يظهر مؤشر تحميل دائم فوق فيديو يعمل
          // فعلياً بداخل WebView (شوهد بسجل تشخيص فعلي: السيجمنتات تُجلب
          // بنجاح مستمر رغم فشل كل محاولات ExoPlayer)، ويمنع المستخدم من
          // التفاعل مع الصفحة (شرط "_state == ready" أضيف لاحقاً لمنع
          // لمسات عشوائية أثناء الاكتشاف الصامت) رغم إن WebView هو فعلياً
          // المشغّل النهائي بهذه الحالة.
          if (mounted) setState(() => _state = _LoadState.ready);
        }
        return;
      }
      _slog('PLAY_SERVER_QUALITY_FAILED', 'url=${_safeLogUrl(quality.url)} error=${_describePlaybackError(error)} rawError=$error');
      unawaited(_hlsCacheProxy.stop());
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
      if (mounted && _isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    if (_isPlaying) {
      _userPausedPlayback = true;
      controller.pause();
    } else {
      _userPausedPlayback = false;
      controller.play();
    }
    _scheduleHide();
  }

  void _seekBy(Duration delta) {
    final controller = _controller;
    if (controller == null) return;
    final target = _position + delta;
    final wasPlaying = _isPlaying;
    controller.seekTo(target < Duration.zero ? Duration.zero : target);
    // Seeking past the buffered window can drop ExoPlayer's playWhenReady on
    // some sources/devices, leaving playback paused until the user manually
    // taps play — unlike YouTube, which always resumes after a seek. Force
    // resume here when playback was already in progress before the seek.
    if (wasPlaying) controller.play();
    _cancelSlowConnectionTimer();
    if (_isBuffering) _startSlowConnectionTimer();
    _scheduleHide();
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      _muted = value == 0;
    });
    _controller?.setVolume(_muted ? 0 : value / 100);
  }

  Future<void> _toggleFullscreen() async {
    final nextFullscreen = !_fullscreen;
    setState(() {
      _fullscreen = nextFullscreen;
      if (nextFullscreen) _isLandscape = true;
    });
    if (nextFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // Leaving fullscreen does not unexpectedly rotate the viewer back to
      // portrait. Portrait remains an explicit choice via the top button.
      await SystemChrome.setPreferredOrientations(
        _isLandscape
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ],
      );
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
    setState(() {
      _locked = !_locked;
      _controlsVisible = true;
    });
    _scheduleHide();
  }

  void _showCenterToast(String text, {Duration duration = const Duration(milliseconds: 700)}) {
    _centerToastTimer?.cancel();
    setState(() => _centerToast = text);
    _centerToastTimer = Timer(duration, () {
      if (mounted) setState(() => _centerToast = null);
    });
  }

  // تبديل بنقرة واحدة بدل قائمة منسدلة — بعض الخيارات كانت تظهر أسفل حافة
  // الشاشة بدون إمكانية سحب لأعلى بحسب حجم الشاشة/الخط. كل نقرة تنتقل
  // للوضع التالي بالترتيب (وتلف من الأخير للأول)، مع شارة نصية مؤقتة وسط
  // الشاشة تعرض اسم الوضع الجديد فوراً.
  void _cycleFit() {
    final modes = _fitModes.keys.toList();
    final next = modes[(modes.indexOf(_fit) + 1) % modes.length];
    setState(() => _fit = next);
    _showCenterToast(_fitModes[next]?.$1 ?? '');
  }

  // خمسة أوضاع عرض بدل ثلاثة — شاشات الهواتف تختلف نسبتها (19.5:9، 20:9،
  // 21:9...) عن نسبة الفيديو غالباً، فثلاثة أوضاع لا تكفي لتناسب كل جهاز/
  // ذوق: "احتواء" يترك حوافاً سوداء لكن يعرض الفيديو كاملاً، "تعبئة الشاشة"
  // تملأ الاثنين تلقائياً (تقصّ البُعد الأطول)، "ملء العرض"/"ملء الارتفاع"
  // يعطيان تحكماً يدوياً صريحاً بأي بُعد يُملأ بالضبط (بديل لمن يفضّل قصّاً
  // بجهة واحدة محددة بدل قرار "تعبئة" التلقائي)، و"تمديد" تملأ الشاشة بدون
  // قص أي جزء إطلاقاً (بديل عملي لمن يزعجه القص أكثر من التمدد الطفيف).
  // خُفِّضت من 5 إلى 4 أوضاع بناءً على طلب صريح — إزالة "ملء العرض"
  // (fitWidth) تحديداً لأنه يقصّ من الأعلى والأسفل، وهو بالضبط المكان
  // اللي تظهر فيه الترجمة المحروقة بأغلب المصادر؛ الأوضاع الأربعة الباقية
  // إما بلا قصّ إطلاقاً (احتواء/تمديد) أو تقصّ من الجانبين فقط
  // (تعبئة الشاشة/ملء الارتفاع)، فلا تلمس الترجمة أبداً.
  static const _fitModes = <BoxFit, (String, String, IconData)>{
    BoxFit.contain: ('احتواء', 'يعرض الفيديو كاملاً، قد تظهر حواف سوداء', Icons.fit_screen),
    BoxFit.cover: ('تعبئة الشاشة', 'يملأ الشاشة بالكامل، قد يقصّ من الجانبين', Icons.crop_free),
    BoxFit.fitHeight: ('ملء الارتفاع', 'يملأ ارتفاع الشاشة بالضبط، قد يقصّ من الجانبين', Icons.height),
    BoxFit.fill: ('تمديد', 'يملأ الشاشة بدون قص، مع تمدد بسيط للصورة', Icons.aspect_ratio),
  };

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
    if (!mounted) return;
    setState(() {
      _playbackSpeed = speed;
    });
    _scheduleHide();
  }

  void _openSpeedSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
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
    );
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
    final side = isRight ? 'right' : 'left';
    _seekBy(Duration(seconds: isRight ? 10 : -10));
    _seekFeedbackTimer?.cancel();
    setState(() {
      // نقر متكرر بسرعة بنفس الجهة يراكم (+10 ← +20 ← +30...)؛ تغيير
      // الجهة يبدأ من +10 من جديد — نفس سلوك يوتيوب بالنقر المزدوج.
      _seekFeedbackAccumulated =
          _seekFeedback == side ? _seekFeedbackAccumulated + 10 : 10;
      _seekFeedback = side;
    });
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _seekFeedback = null;
          _seekFeedbackAccumulated = 0;
        });
      }
    });
  }

  double _dragStartVolume = 0;

  // بوابة إيماءات موحّدة (راجع تعليق الحقول أعلاه لسبب الدمج): تقديم/تأخير
  // أفقياً، صوت رأسياً، تكبير/تصغير بإصبعين — كلها من نفس onScale*.
  void _onScaleStart(ScaleStartDetails details) {
    if (_locked || _state != _LoadState.ready) return;
    _swipeStart = details.focalPoint;
    _seekingFromSwipe = false;
    _dragAxisLock = null;
    _dragStartVolume = _muted ? 0 : _volume;
    _zoomGestureBaseScale = _zoomScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_swipeStart == null) return;
    if (details.pointerCount >= 2) {
      _dragAxisLock = 'zoom';
      final next = (_zoomGestureBaseScale * details.scale).clamp(0.5, 3.0);
      setState(() => _zoomScale = next);
      _showCenterToast('${(next * 100).round()}%');
      return;
    }
    if (_dragAxisLock == 'zoom') return; // انتهت لمسّة ثانية، هذه الحركة صارت ملك التكبير
    if (_dragAxisLock == null) {
      final total = details.focalPoint - _swipeStart!;
      if (total.dx.abs() > 8 && total.dx.abs() > total.dy.abs()) {
        _dragAxisLock = 'h';
      } else if (total.dy.abs() > 8 && total.dy.abs() > total.dx.abs()) {
        _dragAxisLock = 'v';
      }
    }
    if (_dragAxisLock == 'h') {
      if (!_contentIsSeekable || _seekingFromSwipe) return;
      final delta = details.focalPoint.dx - _swipeStart!.dx;
      if (delta.abs() > _swipeThreshold) {
        _seekingFromSwipe = true;
        final seconds = (delta / _swipeThreshold).round() * 5;
        _seekBy(Duration(seconds: seconds));
        _seekFeedbackTimer?.cancel();
        setState(() {
          _seekFeedback = delta > 0 ? 'right' : 'left';
          _seekFeedbackAccumulated = seconds.abs();
        });
        _seekFeedbackTimer = Timer(const Duration(milliseconds: 600), () {
          if (mounted) {
            setState(() {
              _seekFeedback = null;
              _seekFeedbackAccumulated = 0;
            });
          }
        });
      }
    } else if (_dragAxisLock == 'v') {
      final height = MediaQuery.of(context).size.height;
      final delta = (_swipeStart!.dy - details.focalPoint.dy) / height;
      final newVolume = (_dragStartVolume + delta * 100).clamp(0.0, 100.0);
      _setVolume(newVolume);
      // شارة مؤقتة وسط الشاشة بدل زر/شريط صوت دائم بشريط التحكم — نفس
      // أسلوب المشغلات الكبرى (MX Player وغيره): تظهر أثناء السحب فقط
      // وتختفي تلقائياً بعده (_showCenterToast يلغي المؤقّت السابق ويعيده
      // بكل نداء، فتبقى ظاهرة طوال السحب المستمر).
      _showCenterToast('${newVolume <= 0 ? '🔇' : '🔊'} ${newVolume.round()}%');
      _scheduleHide();
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _swipeStart = null;
    _seekingFromSwipe = false;
    _dragAxisLock = null;
  }

  // ---------------------- sheets ----------------------
  void _openQualitySheet() {
    final session = _session;
    if (session == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
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
                        // جلسة WebView (episodes.streamType='web') تحتاج
                        // فتح صفحة السيرفر الجديد كاملة، لا تجربة تشغيل
                        // أصلي مباشرة — quality.url هنا صفحة ويب وليست
                        // رابط وسائط.
                        if (session.kind == StreamKind.web) {
                          _openWebSource(server.qualities.first.url, server: server);
                        } else {
                          _playServerQuality(server, server.qualities.first);
                        }
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
                        // نفس ثغرة تبديل السيرفر المُصلَحة سابقاً (488ce33)
                        // لكن هنا لتبديل الجودة: جلسة WebView تحتاج فتح
                        // صفحة الجودة الجديدة كاملة، لا تجربة تشغيل أصلي
                        // مباشرة على رابط صفحة ويب. الاستثناء: سيرفر
                        // مُكتشَف تلقائياً (راجع _autoDiscoveredServerLabel)
                        // — جوداته مبنية من تحليل playlist رئيسي حقيقي
                        // (_populateHlsQualitiesInBackground)، فروابطها
                        // دائماً وسائط مُثبَتة لا صفحات ويب، بغض النظر عن
                        // session.kind.
                        if (session.kind == StreamKind.web &&
                            _activeServer?.label != _autoDiscoveredServerLabel) {
                          _openWebSource(quality.url, server: _activeServer);
                        } else {
                          _playServerQuality(_activeServer!, quality);
                        }
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
  bool _webWasPlayingBeforeBackground = false;

  // إيقاف/استئناف فيديو الـWebView عند تعليق/استئناف التطبيق — بنفس منطق
  // المشغّل الأصلي أدناه. بدون هذا، أي جلسة تشغّل عبر WebView (شائعة جداً:
  // كل مواقع JWPlayer/Video.js المعروفة تُعرض عبر WebView مباشرة، وأيضاً
  // الملاذ الأخير بوضع الإخفاء) تستمر بتشغيل صوت/فيديو خلفياً بصمت عند
  // تصغير التطبيق — استهلاك بطارية/بيانات غير متوقع، واستمرار صفحة الموقع
  // بالتنقل عبر سلاسل إعلانية بالخلفية (راجع تعليق PAGE_FINISHED).
  Future<void> _pauseWebPlayback() async {
    final controller = _webController;
    if (controller == null) return;
    try {
      final result = await controller.runJavaScriptReturningResult(r'''(() => {
        let wasPlaying = false;
        document.querySelectorAll('video,audio').forEach((v) => {
          try {
            if (!v.paused) { wasPlaying = true; v.pause(); }
          } catch (_) {}
        });
        return wasPlaying;
      })();''');
      _webWasPlayingBeforeBackground = result == true || result.toString() == 'true';
    } catch (_) {}
  }

  // لا نتوقف على _webWasPlayingBeforeBackground قبل المحاولة — علمها غير
  // موثوق أصلاً بنفس عيب _pauseWebPlayback أعلاه: كلاهما querySelectorAll
  // على الوثيقة الرئيسية فقط، ولا يصلان لعنصر <video> داخل iframe من أصل
  // مختلف (الحالة الشائعة فعلياً: vidmoly/JWPlayer المُرقَّى كوثيقة رئيسية
  // نفسه غالباً نفس الأصل، لكن بعض المزوّدين يُبقونه بداخل iframe متداخل).
  // لو الفيديو كان يشتغل فعلاً بداخل iframe كذا، _pauseWebPlayback لم
  // يلمسه أصلاً (فما احتاج استئناف)، لكن نظام أندرويد نفسه (لا كودنا) قد
  // يُعلّق WebView بالكامل عند قفل الشاشة — الاستدعاء هنا لا يضر بأي حال
  // (فحص v.paused قبل play() آمن حتى لو لم يكن متوقفاً أصلاً)، فلا داعي
  // لحارس قد يمنع محاولة استئناف حقيقية.
  Future<void> _resumeWebPlayback() async {
    final controller = _webController;
    if (controller == null) return;
    _webWasPlayingBeforeBackground = false;
    try {
      await controller.runJavaScript(r'''(() => {
        document.querySelectorAll('video,audio').forEach((v) => {
          try { if (v.paused && v.readyState >= 2) v.play().catch(() => {}); } catch (_) {}
        });
      })();''');
    } catch (_) {}
  }

  // مؤكَّد من المستخدم فعلياً: تشغيل ويب كان يعمل، قفل الشاشة بزر الباور
  // ثم فتحها ترك الجلسة معلَّقة تماماً — لا استئناف تلقائي، ولا حتى إعادة
  // تشغيل الصفحة من الصفر تنجح. _resumeWebPlayback أعلاه (استدعاء JS
  // play() فقط) لا يكفي لو نظام أندرويد نفسه علَّق محرّك الرسم/الجافاسكربت
  // الداخلي لـWebView بالكامل أثناء قفل الشاشة (سلوك معروف لبعض إصدارات
  // أندرويد عند تعليق طويل نسبياً) — عندها لا يوجد أي استدعاء JS من جهتنا
  // يقدر "يوقظه" لأن حلقة الأحداث نفسها متجمّدة. الحل: مراقب قصير بعد أي
  // استئناف فعلي لجلسة ويب — لو لم يتحرّك أي دليل شبكي حقيقي خلال مهلة
  // معقولة (يعني الصفحة فعلاً عالقة، لا مجرد استئناف بطيء)، نعيد فتح نفس
  // المصدر من الصفر (نفس مسار "تبديل سيرفر تلقائي" الموجود أصلاً) بدل ترك
  // المستخدم عالقاً للأبد على صفحة ميتة.
  Timer? _webResumeStallWatchdog;
  void _armWebResumeStallWatchdog() {
    _webResumeStallWatchdog?.cancel();
    final hitsAtResume = _webMediaResourceHits;
    final urlAtResume = _webOriginalUrl;
    final generationAtResume = _webSessionGeneration;
    void arm() {
      _webResumeStallWatchdog = Timer(const Duration(seconds: 7), () {
        if (!mounted ||
            !_isWebSource ||
            _webSessionState == _WebSessionState.nativePlaying ||
            _webSessionGeneration != generationAtResume ||
            urlAtResume == null) {
          return;
        }
        // نفس استثناء _startWebStartupTimeout بالضبط: حالات نشطة فعلاً
        // (تحدٍّ بشري ينتظر تفاعل المستخدم، تحقّق مصدر، محاولة تشغيل قيد
        // التنفيذ) ليست "عالقة" — إعادة فتح الصفحة هنا تقاطع مستخدماً يحل
        // CAPTCHA فعلياً بيده، أو تهدر محاولة تشغيل شرعية لسا ما انتهت.
        // نؤجّل الفحص بدل إلغائه، بنفس مبدأ arm() هناك.
        final state = _webSessionState;
        if (state == _WebSessionState.humanVerificationRequired ||
            state == _WebSessionState.validating ||
            state == _WebSessionState.nativeTrial ||
            state == _WebSessionState.candidateTrial) {
          arm();
          return;
        }
        if (_webMediaResourceHits > hitsAtResume) {
          // فعلاً استأنف — دليل شبكي جديد تحرّك خلال المهلة.
          return;
        }
        _slog(
          'WEB_RESUME_STALLED',
          'noNetworkActivityFor=7s hitsAtResume=$hitsAtResume — reopening web source fresh',
        );
        unawaited(_openWebSource(urlAtResume, server: _activeServer));
      });
    }

    arm();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    final hasNative = controller != null && controller.value.isInitialized;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (hasNative && controller.value.isPlaying) {
          _wasPlayingBeforeBackground = true;
          controller.pause();
        }
        if (_isWebSource) unawaited(_pauseWebPlayback());
        break;
      case AppLifecycleState.resumed:
        if (hasNative && _wasPlayingBeforeBackground) {
          _wasPlayingBeforeBackground = false;
          controller.play();
        }
        if (_isWebSource) {
          unawaited(_resumeWebPlayback());
          _armWebResumeStallWatchdog();
        }
        break;
    }
  }

  @override
  void dispose() {
    SessionLogService.instance.endSession('screen disposed (state=$_state, isWebSource=$_isWebSource)');
    _webDetectorTimer?.cancel();
    _webStartupTimeoutTimer?.cancel();
    _webPromotionFallbackTimer?.cancel();
    _webVidmolyRevealTimer?.cancel();
    if (identical(_activeInstance, this)) _activeInstance = null;
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _hiddenSourceGraceTimer?.cancel();
    _loadingTickerTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _centerToastTimer?.cancel();
    _slowConnectionTimer?.cancel();
    _bufferIndicatorTimer?.cancel();
    _stallNudgeTimer?.cancel();
    _stallGiveUpTimer?.cancel();
    _nativeReconnectTimer?.cancel();
    _webResumeStallWatchdog?.cancel();
    _controller?.removeListener(_videoListener);
    WakelockPlus.disable();
    _controller?.dispose();
    unawaited(_hlsCacheProxy.stop());
    _streamNetworkClient.close();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ---------------------- تعديل _startSession (استخدام المعالجة الجديدة) ----------------------
  Future<void> _startSession() async {
    _slog('START_SESSION', 'channelId=${widget.channelId} externalUrl=${widget.externalUrl}');
    setState(() => _state = _LoadState.loading);

    _resolvedStreamHeaders = null;
    _showSourcePage = await PlayerVisibilityService.loadShowSourcePage();
    _webPageRevealedByUser = false;
    if (!mounted) return;

    // تحسين الهيدرز لمحاكاة مستخدم حقيقي
    _headers = {
      'user-agent': widget.externalUserAgent ??
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.119 Mobile Safari/537.36',
      'accept-language': 'ar,en-US;q=0.9,en;q=0.8',
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin',
      ...(_headers ?? {}),
    };

    StreamSession? session;

    if (widget.externalUrl != null && widget.externalUrl!.isNotEmpty) {
      final external = widget.externalUrl!.trim();
      final lower = external.toLowerCase();
      final looksLikeVideo = lower.contains('.m3u8') || lower.contains('.m3u') ||
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
      } catch (e) {
        cmsResolverAvailable = false;
        _slog('CMS_RESOLVER', 'threw: $e');
      }
      _slog(
        'CMS_RESOLVER',
        'available=$cmsResolverAvailable found=${cmsSession != null} kind=${cmsSession?.kind}',
      );

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
          apiUrl = 'https://def.ycnapi.com${apiUrl.startsWith('/') ? '' : '/'}$apiUrl';
        }
        session = await _resolveChannelUrl(apiUrl);
      }
    } else {
      session = StreamSession.failure('لا يوجد مصدر بث لتشغيله.');
    }

    if (!mounted) return;

    if (session == null || !session.ok || session.servers.isEmpty) {
      final message = session?.errorMessage ?? 'تعذر تشغيل البث.';
      _slog('SESSION_RESOLVE_FAILED', message);
      setState(() {
        _state = _LoadState.error;
        _errorMessage = message;
      });
      return;
    }

    _session = session;
    _slog(
      'SESSION_RESOLVED',
      'kind=${session.kind} url=${_safeLogUrl(session.servers.first.qualities.first.url)}',
    );
    if (session.kind == StreamKind.web) {
      await _openWebSource(
        session.servers.first.qualities.first.url,
        server: session.servers.first,
      );
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
    _syncHiddenSourceGraceTimer();
    _syncLoadingTicker();
    final content = GestureDetector(
      // Let platform WebView gestures go directly to the page/player.
      // The outer playback gesture layer is only needed for native video.
      onTap: _isWebSource ? null : _toggleControls,
      onDoubleTapDown: _isWebSource ? null : _handleDoubleTapDown,
      // onScale* subsumes single-finger pan (seek/volume) and two-finger
      // pinch (zoom) on one recognizer — GestureDetector doesn't allow
      // mixing onHorizontalDrag*/onVerticalDrag* with onScale* together.
      onScaleStart: _isWebSource ? null : _onScaleStart,
      onScaleUpdate: _isWebSource ? null : _onScaleUpdate,
      onScaleEnd: _isWebSource ? null : _onScaleEnd,
      child: Stack(
            fit: StackFit.expand,
            children: [
              if (_isWebSource && _webController != null)
                Opacity(
                  opacity: _shouldShowWebPage ? 1 : 0,
                  child: IgnorePointer(
                    // نمنع لمسات المستخدم أثناء الاكتشاف الصامت بالخلفية
                    // (المصدر لم "يجهز" بعد) — أي نقرة عشوائية هناك قد
                    // تضغط إعلاناً أو تنقّل الصفحة وتكسر منطق الاكتشاف.
                    // نسمح باللمس فقط لو: المصدر جاهز فعلاً، أو مطلوب
                    // تحقق بشري (captcha) يحتاج تفاعل المستخدم، أو المستخدم
                    // كشف الصفحة يدوياً بنفسه (زر "إظهار صفحة المصدر").
                    ignoring: !_shouldShowWebPage ||
                        (_state != _LoadState.ready &&
                            _webSessionState !=
                                _WebSessionState.humanVerificationRequired &&
                            !_webPageRevealedByUser),
                    child: WebViewWidget(controller: _webController!),
                  ),
                ),
              if (_isHiddenWebSourceActive && _hiddenSourceGraceElapsed)
                _buildHiddenWebSourceStatus(),
              if (_state == _LoadState.ready && !_isWebSource)
                Center(
                  child: Transform.scale(scale: _zoomScale, child: _buildVideo()),
                ),
              if (_isLoadingContent &&
                  _webSessionState != _WebSessionState.humanVerificationRequired)
                _buildLoading(),
              if (_webSessionState == _WebSessionState.humanVerificationRequired)
                _buildHumanVerificationBanner(),
              if (_state == _LoadState.error) _buildError(),
              if (_state == _LoadState.ready &&
                  !_isWebSource &&
                  _isBuffering &&
                  _bufferIndicatorVisible)
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
              // تأثير مستوحى من يوتيوب (بدون نسخ حرفي): لوحة نصف-دائرية
              // تلتصق بحافة الشاشة المناسبة وتنبض عند كل نقرة إضافية سريعة
              // بنفس الجهة، مع تراكم الثواني ("+20"، "+30"...) بدل أيقونة
              // ثابتة لا تتحرك.
              if (_seekFeedback != null)
                Align(
                  alignment: _seekFeedback == 'right'
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.36,
                    heightFactor: 0.6,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(_seekFeedbackAccumulated),
                      tween: Tween(begin: 0.86, end: 1.0),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.horizontal(
                            left: _seekFeedback == 'right'
                                ? const Radius.circular(120)
                                : Radius.zero,
                            right: _seekFeedback == 'left'
                                ? const Radius.circular(120)
                                : Radius.zero,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _seekFeedback == 'right'
                                  ? Icons.keyboard_double_arrow_right
                                  : Icons.keyboard_double_arrow_left,
                              color: Colors.white,
                              size: 38,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$_seekFeedbackAccumulated ثانية',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_centerToast != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _centerToast!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
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
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: _circleIconButton(
                        icon: _locked ? Icons.lock : Icons.lock_open,
                        tooltip: _locked ? 'إلغاء القفل' : 'قفل الشاشة',
                        onPressed: _toggleLock,
                      ),
                    ),
                  ),
                ),
              if (_state == _LoadState.ready && !_isWebSource && !_locked)
                Positioned(
                  top: 8,
                  left: 62,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: _circleIconButton(
                        icon: _fitModes[_fit]?.$3 ?? Icons.aspect_ratio,
                        tooltip: 'وضع عرض الفيديو (${_fitModes[_fit]?.$1 ?? ''})',
                        onPressed: _cycleFit,
                      ),
                    ),
                  ),
                ),
              // منقول من صف التحكم العلوي (Row داخل _buildControls) — كان
              // يتشارك نفس المساحة فعلياً مع زري القفل/وضع العرض أعلاه
              // فيظهر خلفهما. زاوية مستقلة (يمين الشاشة) تحل التصادم نهائياً.
              if (_state == _LoadState.ready && !_isWebSource && !_locked)
                Positioned(
                  top: 8,
                  right: 8,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: _circleIconButton(
                        icon: Icons.arrow_back,
                        tooltip: 'رجوع',
                        onPressed: _exit,
                      ),
                    ),
                  ),
                ),
              // Web players own their internal controls, so keep the
              // orientation action available as a Flutter overlay as well.
              if (_state == _LoadState.ready && _isWebSource)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _circleIconButton(
                    icon: _isLandscape
                        ? Icons.screen_lock_rotation
                        : Icons.screen_rotation,
                    tooltip: _isLandscape
                        ? 'التبديل إلى الوضع العمودي'
                        : 'التبديل إلى الوضع الأفقي',
                    onPressed: _toggleOrientation,
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
    );
    // في وضع ملء الشاشة نتجاوز SafeArea تماماً حتى يمتلئ الفيديو الشاشة
    // الحقيقية بالكامل (وإلا قد تُقتطع حافة الفيديو، ومعها أي ترجمة
    // مدمجة قرب أسفل الإطار، بسبب هوامش SafeArea المحجوزة). أزرار
    // التحكم تحتفظ بـ SafeArea خاصة بها داخل _buildControls لتفادي أي
    // نتوء بالشاشة.
    return Scaffold(
      backgroundColor: Colors.black,
      body: _fullscreen ? content : SafeArea(child: content),
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
      child: ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: _fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: width,
              height: height,
              child: VideoPlayer(controller),
            ),
          ),
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
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _loadingMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 2)),
                Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // طلب سابق: سواد كامل بلا نص. تعديل لاحق: نفس السواد، لكن مع نفس مؤشر
  // التحميل الدائري (AppTheme.accent) المستخدَم بـ_buildLoading() — بدون
  // نص أو زر — حتى يطمئن المستخدم أن التطبيق لسّه يجهّز الرابط ولم يتجمّد،
  // بدل شاشة سوداء صامتة تماماً. صفحة المصدر تبقى مخفية وممنوعة من اللمس
  // (نفس منطق _shouldShowWebPage/IgnorePointer بالـbuild أعلاه).
  // تعديل ثانٍ: أُضيف نص (_loadingMessage نفسه المستخدَم بـ_buildLoading،
  // يتغيّر تلقائياً مع الوقت) — المؤشر الدائري وحده لم يكن كافياً ليشعر
  // المستخدم أن التشغيل على وشك البدء فعلاً.
  Widget _buildHiddenWebSourceStatus() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3.2,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _loadingMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 2)),
                    Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
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
              color: Colors.black.withValues(alpha: 0.78),
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
    double size = 48,
    double iconSize = 24,
    Widget? child,
    bool bounce = false,
  }) {
    // خلفية أخف بكثير من قبل — التدرّج الأسود خلف شريط التحكم بأكمله
    // (راجع _buildControls) يكفي وحده لوضوح الأيقونات فوق أي فيديو، فلا
    // حاجة لخلفية دائرية داكنة إضافية خلف كل أيقونة (شكل يوتيوب النظيف).
    final button = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: 0.15),
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
    return bounce ? _BouncyPress(child: button) : button;
  }

  Widget _buildControls() {
    final isLive = _session?.isLive ?? false;
    final canSeek = _contentIsSeekable;
    final compactControls = MediaQuery.sizeOf(context).width < 600;
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
                  // زر الرجوع لم يعد هنا — انتقل لـPositioned مستقلة (راجع
                  // build()) عند top:8,right:8 لأنه كان يتشارك نفس منطقة
                  // الشاشة فعلياً مع زري القفل/وضع العرض (top:8,left:8/62)
                  // ويظهر خلفهما (مؤكَّد من المستخدم عبر لقطة شاشة حقيقية).
                  // نفس هذا الفراغ يحجز مساحة زر الرجوع العائم فلا يتراكب
                  // مع اسم الحلقة/الفيلم أدناه.
                  const SizedBox(width: 56),
                  if (isLive && !canSeek && !compactControls) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: Colors.white, size: 8),
                          SizedBox(width: 5),
                          Text('مباشر',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // اسم الحلقة/الفيلم — مثل يوتيوب، بجانب زر الرجوع. اختياري
                  // تماماً (راجع WatchScreen.title): يعتمد على تمرير الاسم
                  // فعلياً من الشاشة التي تفتح المشغّل (BinSheikh أو رابط
                  // محفوظ يدوياً) — غيابه لا يعطّل أي شيء، الصف يتصرّف
                  // بالضبط كما كان بالسابق (Spacer فقط).
                  if (widget.title != null && widget.title!.trim().isNotEmpty)
                    Expanded(
                      child: Text(
                        widget.title!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (isLive && !canSeek)
                    _circleIconButton(
                      icon: Icons.live_tv,
                      tooltip: 'القفز للبث المباشر',
                      onPressed: _jumpToLive,
                    ),
                  _circleIconButton(
                    icon: _isLandscape
                        ? Icons.screen_lock_rotation
                        : Icons.screen_rotation,
                    tooltip: _isLandscape
                        ? 'التبديل إلى الوضع العمودي'
                        : 'التبديل إلى الوضع الأفقي',
                    onPressed: _toggleOrientation,
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
                  const SizedBox(width: 12),
                  _circleIconButton(
                    icon: _isPlaying ? Icons.pause : Icons.play_arrow,
                    tooltip: _isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
                    size: 84,
                    iconSize: 46,
                    bounce: true,
                    onPressed: _togglePlay,
                  ),
                  const SizedBox(width: 12),
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
                        // مثل يوتيوب: خط رفيع جداً افتراضياً، تكبر الكرة
                        // وتظهر فقط أثناء السحب الفعلي (راجع _isScrubbingSlider) —
                        // غير ذلك خط نظيف بلا كرة ثابتة الظهور.
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: _isScrubbingSlider ? 3.5 : 2,
                          thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: _isScrubbingSlider ? 7 : 0),
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
                          onChangeStart: (_) {
                            _wasPlayingBeforeScrub = _isPlaying;
                            setState(() => _isScrubbingSlider = true);
                          },
                          onChanged: (value) => _controller
                              ?.seekTo(Duration(milliseconds: value.toInt())),
                          onChangeEnd: (_) {
                            setState(() => _isScrubbingSlider = false);
                            // ExoPlayer can drop playWhenReady after a seek
                            // past the buffered window on some sources —
                            // without this, dragging the slider silently
                            // pauses playback until the user taps play again.
                            if (_wasPlayingBeforeScrub) _controller?.play();
                          },
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
      backgroundColor: AppTheme.surface,
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
                  _fitModes[_fit]?.$1 ?? '',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _cycleFit();
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
