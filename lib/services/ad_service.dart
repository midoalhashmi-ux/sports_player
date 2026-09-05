import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// يدير الإعلانات (بيني + بانر) ويقرأ إعداداتها من Firestore
/// (المستند settings/ads) حتى تقدر تتحكم فيها من لوحة التحكم بدون
/// تحديث التطبيق: تشغيل/إيقاف الإعلانات بالكامل، أو تغيير معرّفات
/// الوحدات الإعلانية.
///
/// شكل المستند المتوقع في Firestore (نفس ما تحفظه لوحة التحكم):
/// settings/ads {
///   enabled: true,
///   admob: {
///     appId: "ca-app-pub-xxxx~xxxx",       // ملاحظة: لا يُستخدم من هنا،
///                                           // راجع الشرح أسفل initialize()
///     bannerId: "ca-app-pub-xxxx/xxxx",
///     interstitialId: "ca-app-pub-xxxx/xxxx",
///     rewardedId: "ca-app-pub-xxxx/xxxx",  // محفوظ للاستخدام المستقبلي،
///                                           // لا توجد شاشة تعرض إعلان
///                                           // مكافئ حالياً
///   },
/// }
///
/// حالياً هذه الخدمة تدعم AdMob فقط (الحزمة المضافة فعلياً في
/// pubspec.yaml). حقول applovin/unity في اللوحة محفوظة في قاعدة
/// البيانات لكن لا تُقرأ من هنا إلى أن تُضاف حزم SDK الخاصة بها.
///
/// إذا لم يوجد المستند أو أي حقل، يستخدم معرّفات اختبار Google الرسمية
/// تلقائياً حتى لا يتعطل شيء قبل ما تضبط حسابك الحقيقي.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const _testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const _testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  // نفس القيمة الموجودة حالياً في AndroidManifest.xml — إذا غيّرتها هناك
  // مستقبلاً لمعرّف تطبيقك الحقيقي، غيّرها هنا أيضاً بنفس القيمة الجديدة.
  static const _testAppId = 'ca-app-pub-3940256099942544~3347511713';

  bool _adsEnabled = true;
  String _interstitialAdUnitId = _testInterstitialId;
  String _bannerAdUnitId = _testBannerId;

  InterstitialAd? _interstitialAd;
  bool _interstitialLoading = false;

  // حد أدنى بين إعلانين بينيين متتاليين — يمنع إزعاج المستخدم بإعلان
  // جديد في كل تبديل قناة سريع (كان يظهر في كل مرة بدون أي حد زمني).
  DateTime? _lastInterstitialShownAt;
  static const _minGapBetweenInterstitials = Duration(minutes: 3);

  bool get adsEnabled => _adsEnabled;
  String get bannerAdUnitId => _bannerAdUnitId;

  // Future مشترك واحد للتهيئة بدل علامة true/false بسيطة. المشكلة مع
  // علامة بسيطة (`_initialized = true` في أول سطر): لو استُدعيت
  // initialize() من مكانين (main.dart عند الإقلاع، وWatchScreen عند فتح
  // شاشة المشاهدة) بفارق زمني بسيط جداً، الاستدعاء الثاني كان يرى العلامة
  // "true" ويظن أن التهيئة خلصت فعلياً ويقفز مباشرة لحلقة انتظار الإعلان،
  // بينما التهيئة الحقيقية (UMP + SDK + قراءة الإعدادات) لسه شغّالة في
  // الخلفية والإعلان لم يبدأ تحميله بعد أصلاً — فتخرج حلقة الانتظار فوراً
  // بدون أي انتظار حقيقي. بتخزين الـ Future نفسه، أي استدعاء لاحق ينتظر
  // نفس العملية الجارية فعلياً حتى تكتمل بالكامل قبل ما يكمل.
  Future<void>? _initFuture;

  /// يهيّئ SDK ويجلب إعدادات الإعلانات من Firestore. آمن الاستدعاء أكثر
  /// من مرة ومن أكثر من مكان — كل استدعاء ينتظر نفس عملية التهيئة الفعلية
  /// (تُنفَّذ مرة واحدة فقط) بدل تكرارها أو تجاوزها قبل اكتمالها.
  Future<void> initialize() {
    return _initFuture ??= _runInitialize();
  }

  Future<void> _runInitialize() async {
    // خطوة إلزامية من Google قبل أي تهيئة/عرض إعلان: تحديث معلومات
    // الموافقة عبر UMP SDK، وعرض نموذج الموافقة تلقائياً إن كان مطلوباً
    // (المستخدمون في المنطقة الاقتصادية الأوروبية/بريطانيا أساساً حسب
    // إعدادات موافقة الإعلانات في AdMob Console). لا نبدأ تهيئة SDK
    // الإعلانات ولا تحميل أي إعلان قبل أن يسمح UMP بذلك صراحة.
    //
    // ملاحظة: خارج أوروبا/بريطانيا (مثل السعودية) عادةً UMP لا يطلب عرض
    // أي نموذج موافقة إطلاقاً وتكمل هذه الخطوة مباشرة — فعدم ظهور نموذج
    // الموافقة أثناء الاختبار غالباً طبيعي وليس خطأ.
    final canRequestAds = await _requestConsentAndShowFormIfRequired();
    if (!canRequestAds) {
      // إمّا المستخدم لم يوافق بعد، أو تعذّر تحديد حالة الموافقة — لا نهيئ
      // الإعلانات إطلاقاً بدل عرضها بدون تفويض واضح من UMP.
      _adsEnabled = false;
      debugPrint('[AdService] توقفت الإعلانات: فشل UMP في تأكيد إمكانية '
          'طلب الإعلانات (غالباً مشكلة اتصال بالإنترنت وقت فتح التطبيق).');
      return;
    }

    try {
      await MobileAds.instance.initialize();
    } catch (error) {
      // فشل تهيئة SDK (مثلاً بدون إنترنت) — نكمل بدون إعلانات بدل تعطيل
      // التطبيق كاملاً.
      _adsEnabled = false;
      debugPrint('[AdService] توقفت الإعلانات: فشلت تهيئة SDK نفسه ($error).');
      return;
    }
    await _fetchConfig();
    if (!_adsEnabled) {
      debugPrint('[AdService] الإعلانات موقوفة من لوحة التحكم.');
      return;
    }
    debugPrint('[AdService] التهيئة تمت بنجاح '
        '(bannerId: $_bannerAdUnitId, interstitialId: '
        '$_interstitialAdUnitId).');
    _preloadInterstitial();
  }

  /// يطلب تحديث حالة الموافقة (UMP) ويعرض نموذج الموافقة تلقائياً لو كان
  /// مطلوباً حسب منطقة/إعدادات المستخدم. يرجع true فقط لو أصبح مسموحاً
  /// فعلياً طلب الإعلانات بعد انتهاء المسار بالكامل (سواء لأن الموافقة
  /// غير مطلوبة أصلاً في منطقة المستخدم، أو لأنه وافق فعلاً).
  Future<bool> _requestConsentAndShowFormIfRequired() async {
    final completer = Completer<bool>();
    final params = ConsentRequestParameters();

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
            // formError != null يعني فشل تحميل/عرض النموذج (مشكلة شبكة
            // مثلاً) — نتحقق من canRequestAds() على أي حال، لأن SDK نفسه
            // يمنع الإعلانات المخصّصة تلقائياً دون موافقة صريحة.
          });
        } catch (_) {
          // نتجاهل ونكمل للتحقق من canRequestAds أدناه
        }
        if (!completer.isCompleted) {
          final canRequest = await ConsentInformation.instance.canRequestAds();
          completer.complete(canRequest);
        }
      },
      (error) {
        // فشل تحديث معلومات الموافقة (بدون إنترنت مثلاً) — لا نعرض أي
        // إعلان في هذه الحالة حتى لا نخالف السياسة.
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    return completer.future;
  }

  /// يعيد عرض نموذج خيارات الخصوصية يدوياً (زر "خصوصية الإعلانات" مثلاً
  /// في شاشة الإعدادات) حتى يقدر المستخدم تغيير موافقته لاحقاً — مطلوب
  /// من سياسة UMP بالإضافة إلى العرض التلقائي الأول. لا يفعل شيئاً لو
  /// النموذج غير مطلوب لهذا المستخدم أصلاً.
  Future<void> showPrivacyOptionsFormIfAvailable() async {
    final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
    if (status != PrivacyOptionsRequirementStatus.required) return;
    try {
      await ConsentForm.showPrivacyOptionsForm((_) {});
    } catch (_) {
      // تجاهل — الزر تحسين إضافي، لا يجب أن يعطّل الشاشة عند الفشل
    }
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
      final admob = data['admob'] as Map<String, dynamic>?;

      // حارس مهم: معرّف تطبيق AdMob (App ID) لا يمكن تغييره إلا من
      // AndroidManifest.xml وقت البناء (راجع الشرح هناك) — أي أن معرّف
      // التطبيق المُثبَّت فعلياً على الجهاز الآن قد يكون لا يزال معرّف
      // اختبار Google، حتى لو أدخلت من لوحة التحكم أكواد وحدات إعلانية
      // حقيقية (بانر/بيني) تنتمي لتطبيقك الحقيقي في حساب AdMob. جوجل
      // ترفض بثبات أي طلب إعلان لوحدة حقيقية لا تنتمي لمعرّف التطبيق
      // المُهيَّأ فعلياً — وهذا يُنتج عطلاً صامتاً ودائماً (وليس عرضياً)
      // في أي وحدة أُدخل لها كود حقيقي بينما باقي الوحدات لا تزال
      // افتراضية، بالضبط كحالة "البانر يعمل والبيني لا يعمل".
      //
      // لتفادي هذه الحالة النصف-مُهيَّأة: نطابق حقل "معرّف التطبيق" الذي
      // تُدخله في لوحة التحكم (حقل توثيقي بحت لغرض هذه المطابقة تحديداً)
      // مع معرّف الاختبار المعروف. طالما لم يُدخَل معرّف حقيقي مختلف عن
      // معرّف الاختبار، نتجاهل أي أكواد وحدات حقيقية مُدخلة ونستخدم وحدات
      // الاختبار للجميع — بهذا تبقى الإعلانات دائماً متسقة وتعمل (ولو
      // كإعلانات اختبار) بدل أن تفشل جزئياً وبصمت. بمجرد ما تحدّث معرّف
      // التطبيق في AndroidManifest.xml لمعرّفك الحقيقي وتحدّث نفس القيمة
      // هنا في اللوحة وتبني نسخة جديدة، تُطبَّق تلقائياً كل الأكواد
      // الحقيقية المُدخلة مسبقاً بدون أي تعديل إضافي.
      final configuredAppId = (admob?['appId'] as String?)?.trim() ?? '';
      final appIdIsStillTest =
          configuredAppId.isEmpty || configuredAppId == _testAppId;

      if (!appIdIsStillTest) {
        final interstitialId = admob?['interstitialId'] as String?;
        if (interstitialId != null && interstitialId.trim().isNotEmpty) {
          _interstitialAdUnitId = interstitialId.trim();
        }
        final bannerId = admob?['bannerId'] as String?;
        if (bannerId != null && bannerId.trim().isNotEmpty) {
          _bannerAdUnitId = bannerId.trim();
        }
      }
      // appIdIsStillTest == true → نبقي على _interstitialAdUnitId /
      // _bannerAdUnitId الافتراضيين (معرّفات اختبار Google)، حتى لو فيه
      // أكواد حقيقية مكتوبة في اللوحة، لتفادي التطابق الخاطئ أعلاه.
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
          debugPrint('[AdService] الإعلان البيني جاهز ✓.');
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _interstitialLoading = false;
          debugPrint('[AdService] فشل تحميل الإعلان البيني: '
              '[${error.code}] ${error.message}');
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
    Duration maxWait = const Duration(seconds: 6),
  }) async {
    await initialize();

    if (!_adsEnabled) {
      onComplete();
      return;
    }

    final lastShown = _lastInterstitialShownAt;
    if (lastShown != null &&
        DateTime.now().difference(lastShown) < _minGapBetweenInterstitials) {
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
    _lastInterstitialShownAt = DateTime.now();
    await ad.show();
  }

  BannerAd createBannerAd({
    required void Function(BannerAd ad) onAdLoaded,
    required void Function() onLoadFailed,
  }) {
    return BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('[AdService] إعلان البانر ظهر بنجاح ✓');
          onAdLoaded(ad as BannerAd);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AdService] فشل تحميل إعلان البانر: '
              '[${error.code}] ${error.message}');
          ad.dispose();
          onLoadFailed();
        },
      ),
    )..load();
  }
}
