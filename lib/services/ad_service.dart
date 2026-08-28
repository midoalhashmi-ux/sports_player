import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// يدير الإعلانات (بيني + بانر) ويقرأ إعداداتها من Firestore
/// (المستند settings/ads) حتى تقدر تتحكم فيها من لوحة التحكم بدون
/// تحديث التطبيق: تشغيل/إيقاف الإعلانات بالكامل، أو تغيير معرّفات
/// الوحدات الإعلانية.
///
/// شكل المستند المتوقع في Firestore:
/// settings/ads {
///   enabled: true,
///   interstitialAdUnitId: "ca-app-pub-xxxx/xxxx",
///   bannerAdUnitId: "ca-app-pub-xxxx/xxxx",
/// }
///
/// إذا لم يوجد المستند أو أي حقل، يستخدم معرّفات اختبار Google الرسمية
/// تلقائياً حتى لا يتعطل شيء قبل ما تضبط حسابك الحقيقي.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const _testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const _testBannerId = 'ca-app-pub-3940256099942544/6300978111';

  bool _initialized = false;
  bool _adsEnabled = true;
  String _interstitialAdUnitId = _testInterstitialId;
  String _bannerAdUnitId = _testBannerId;

  InterstitialAd? _interstitialAd;
  bool _interstitialLoading = false;

  bool get adsEnabled => _adsEnabled;
  String get bannerAdUnitId => _bannerAdUnitId;

  /// يهيّئ SDK ويجلب إعدادات الإعلانات من Firestore. استدعِها مرة واحدة
  /// عند بدء التطبيق (قبل أول استخدام لأي إعلان).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await MobileAds.instance.initialize();
    } catch (_) {
      // فشل تهيئة SDK (مثلاً بدون إنترنت) — نكمل بدون إعلانات بدل تعطيل
      // التطبيق كاملاً.
      _adsEnabled = false;
      return;
    }
    await _fetchConfig();
    if (_adsEnabled) _preloadInterstitial();
  }

  Future<void> _fetchConfig() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('ads')
          .get();
      final data = snapshot.data();
      if (data == null) return;
      _adsEnabled = data['enabled'] as bool? ?? true;
      final interstitialId = data['interstitialAdUnitId'] as String?;
      if (interstitialId != null && interstitialId.isNotEmpty) {
        _interstitialAdUnitId = interstitialId;
      }
      final bannerId = data['bannerAdUnitId'] as String?;
      if (bannerId != null && bannerId.isNotEmpty) {
        _bannerAdUnitId = bannerId;
      }
    } catch (_) {
      // تعذر الجلب — نكمل بالإعدادات الافتراضية (إعلانات اختبار مفعّلة)
    }
  }

  void _preloadInterstitial() {
    if (_interstitialLoading || _interstitialAd != null) return;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialLoading = false;
        },
        onAdFailedToLoad: (_) {
          _interstitialAd = null;
          _interstitialLoading = false;
        },
      ),
    );
  }

  /// يعرض الإعلان البيني إن كان جاهزاً، وينفّذ [onComplete] فور إغلاقه.
  /// لو الإعلانات موقوفة، أو الإعلان غير جاهز خلال [maxWait]، ينفّذ
  /// [onComplete] مباشرة حتى لا يتعلّق المستخدم منتظراً إعلاناً لن يظهر
  /// (البث لا يبدأ تحميله أو تشغيله إلا بعد استدعاء onComplete).
  Future<void> showInterstitialThenProceed(
    void Function() onComplete, {
    Duration maxWait = const Duration(seconds: 4),
  }) async {
    if (!_initialized) await initialize();

    if (!_adsEnabled) {
      onComplete();
      return;
    }

    final deadline = DateTime.now().add(maxWait);
    while (_interstitialAd == null &&
        _interstitialLoading &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 150));
    }

    final ad = _interstitialAd;
    if (ad == null) {
      // لا يوجد إعلان جاهز — لا نعطّل المستخدم، نكمل للبث مباشرة
      _preloadInterstitial();
      onComplete();
      return;
    }

    _interstitialAd = null;
    var completed = false;
    void complete() {
      if (completed) return;
      completed = true;
      onComplete();
      _preloadInterstitial(); // نجهّز الإعلان التالي مسبقاً
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        complete();
      },
    );
    await ad.show();
  }

  BannerAd createBannerAd({required void Function() onLoadFailed}) {
    return BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          onLoadFailed();
        },
      ),
    )..load();
  }
}
