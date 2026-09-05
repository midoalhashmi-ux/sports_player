# مواصفة تقنية كاملة — تطبيق المشغل ( BinSheikh Player)

> هذا المستند وصف شامل ودقيق لكل ما يوجد فعلياً في كود تطبيق المشغل حالياً
> (وليس خطة مستقبلية) — بحيث يقدر أي نموذج ذكاء اصطناعي آخر (بدون أي اطلاع
> سابق على المشروع) أن يعيد بناء نفس التطبيق بنفس السلوك بالضبط من هذا
> الملف وحده. كل قسم يصف "ما هو موجود الآن" حرفياً، بما في ذلك أجزاء الكود
> الميتة/غير المستخدمة والأخطاء المكتشفة، لأن نموذجاً يعيد البناء يحتاج
> يعرفها أيضاً حتى لا يكرر نفس الالتباس أو يفترض أنها ميزات فعّالة.

---

## 1) نظرة عامة

- **الاسم الظاهر للمستخدم:** BinSheikh Player
- **اسم مجلد المشروع / pubspec name:** `sports_player`
- **الوصف في pubspec:** "BinSheikh player"
- **الغرض الوحيد لهذا التطبيق:** تشغيل بث الفيديو فقط. لا يعرض أي قوائم قنوات
  أو أقسام أو محتوى تصفّحي — كل ذلك مسؤولية "تطبيق المحتوى" (BinSheikh،
  المشروع الشقيق المنفصل تماماً). هذا التطبيق يُفتح إما:
  1. عبر رابط عميق/Intent قادم من تطبيق المحتوى يحمل `channelId` فقط
     (بدون أي رابط بث حقيقي)، أو
  2. مباشرة من داخله عبر شاشة رئيسية بسيطة لإضافة/تشغيل روابط خارجية
     يدخلها المستخدم بنفسه (ميزة "إضافة رابط").
- **applicationId (Android):** `com.midoalhashmi.zoltrastream`
  - ملاحظة تاريخية: كان هناك اسم حزمة سابق `com.midoalhashmi.sportsplayer2026`
    وما زال له مجلد Kotlin يتيم (`MainActivity.kt` فارغ بدون أي منطق) لم
    يُحذف بعد تغيير الاسم — راجع قسم "كود يتيم" أدناه.
- **minSdk:** 21 — **targetSdk/compileSdk:** يتبعان إصدار Flutter المُستخدم
  (`flutter.targetSdkVersion` / `flutter.compileSdkVersion`، غير مثبَّتين
  برقم صريح في build.gradle).
- **إصدار pubspec الحالي:** `1.0.0+1`
- **مشروع Firebase المشترك مع تطبيق المحتوى:** `sports-stream-app-36a7a`
  (نفس المشروع بالضبط تستخدمه التطبيقان معاً + لوحة التحكم).
- **البناء:** Codemagic، ملف `codemagic.yaml` بمهلة أقصى 90 دقيقة، Flutter
  `3.27.0` محدَّد صراحة (بعكس تطبيق المحتوى الذي يستخدم `stable`)، توقيع
  عبر مرجع Codemagic باسم `sports_player_release`، يبني APK عادي (مو App
  Bundle) — بتعليق صريح بالملف يوصي بالتحويل لـ appbundle عند النشر
  النهائي على Google Play.

---

## 2) حزم pubspec.yaml (كل حزمة وسبب وجودها)

```yaml
name: sports_player
version: 1.0.0+1
environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter: {sdk: flutter}
  cupertino_icons: ^1.0.6
  firebase_core: ^2.32.0
  cloud_firestore: ^4.15.5
  app_links: ^6.3.2          # استقبال الروابط العميقة (Deep Links)
  video_player: ^2.9.2       # تشغيل HLS/mp4 (لا يدعم DASH/RTMP/MKV فعلياً)
  http: ^1.2.2               # طلبات لـ Cloudflare Worker
  wakelock_plus: ^1.2.8      # إبقاء الشاشة مضاءة أثناء المشاهدة
  shared_preferences: ^2.3.2 # حفظ الروابط اليدوية محلياً
  path_provider: ^2.1.4      # مسار حفظ لقطة الشاشة على iOS
  image_gallery_saver_plus: ^3.0.5  # حفظ لقطة الشاشة في المعرض (أندرويد)
  google_mobile_ads: ^5.2.0  # إعلانات AdMob (بانر + بيني)
  share_plus: ^10.0.2        # مشاركة التطبيق
  url_launcher: ^6.3.1       # فتح متجر Google Play / روابط خارجية
  package_info_plus: ^8.0.0  # قراءة رقم إصدار التطبيق المثبَّت (للتحديث الإجباري)

dev_dependencies:
  flutter_test: {sdk: flutter}
  flutter_lints: ^3.0.0
```

**تحذير مهم عن التبعيات المفقودة:** ملفا `lib/services/youtube_resolver.dart`
و`lib/services/tube_resolver.dart` يستوردان `package:youtube_explode_dart/...`،
وهي حزمة **غير موجودة إطلاقاً في pubspec.yaml**. هذان الملفان لا يُستوردان من
أي مكان آخر في المشروع (كود ميت تماماً — راجع القسم 9)، فلا يمنعان البناء
حالياً، لكن لو حاول أي أحد استخدامهما سيفشل البناء فوراً حتى تُضاف الحزمة.

---

## 3) شجرة الملفات الكاملة مع دور كل ملف

```
sports_player-main/
├── codemagic.yaml
├── README.md
├── project-protection-rules.md      # قواعد حماية صارمة (راجع القسم 12)
├── task-status.md                    # سجل تتبّع حالة المهام (منفصل عن هذا المستند)
├── pubspec.yaml
├── android/
│   ├── build.gradle
│   ├── gradle.properties
│   ├── settings.gradle
│   └── app/
│       ├── build.gradle              # applicationId, minSdk=21, keystore
│       ├── src/main/AndroidManifest.xml   # أذونات + intent-filter الرابط العميق
│       └── src/main/kotlin/
│           ├── com/midoalhashmi/zoltrastream/MainActivity.kt   # النشاط الفعلي (PiP)
│           └── com/midoalhashmi/sportsplayer2026/MainActivity.kt  # يتيم، غير مستخدم
└── lib/
    ├── main.dart                     # الإقلاع (Boot) + توجيه الروابط
    ├── firebase_options.dart         # إعدادات Firebase (Android فقط)
    ├── widgets/
    │   └── force_update_gate.dart    # حجب كامل للشاشة أثناء تحديث إجباري
    ├── screens/
    │   ├── home_screen.dart          # الشاشة الرئيسية (روابط محفوظة)
    │   ├── add_url_screen.dart       # نموذج إضافة رابط خارجي يدوي
    │   ├── watch_screen.dart         # شاشة المشاهدة/المشغل الكاملة (الأهم)
    │   ├── contact_screen.dart       # "اتصل بنا"
    │   └── terms_privacy_screen.dart # الشروط والخصوصية + زر خصوصية الإعلانات
    └── services/
        ├── worker_config.dart          # رابط Cloudflare Worker الثابت
        ├── stream_models.dart          # نماذج جلسة/سيرفر/جودة البث
        ├── stream_auth_service.dart    # يطلب جلسة بث من /getStreamUrl
        ├── channel_source_resolver.dart# يقرر: مباشر أم عبر التوكن المحمي
        ├── saved_link_service.dart     # تخزين الروابط اليدوية (SharedPreferences)
        ├── ad_service.dart             # AdMob + UMP (الأكبر، 320 سطر)
        ├── version_check_service.dart  # التحديث الإجباري (settings/player)
        ├── feature_flags_service.dart  # ⚠️ كود ميت (youtubeEnabled، غير مستخدم)
        ├── pip_service.dart            # ⚠️ كود ميت من جهة Dart (القناة موجودة أصلاً بـ Kotlin)
        ├── youtube_id_extractor.dart   # ⚠️ كود ميت (ميزة يوتيوب أُزيلت بالكامل)
        ├── youtube_resolver.dart       # ⚠️ كود ميت + حزمة غير مضافة أصلاً
        └── tube_resolver.dart          # ⚠️ كود ميت، نسخة مكرّرة أقدم من الملف السابق
```

---

## 4) تسلسل الإقلاع (`lib/main.dart`)

1. `WidgetsFlutterBinding.ensureInitialized()` ثم `runApp(_BootApp())`.
2. `_BootAppState._initialize()`:
   - `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.
   - وبالتوازي (بدون انتظار — `unawaited`): يبدأ `AdService.instance.initialize()`
     فوراً بعد جاهزية Firebase، **قبل** بناء أي واجهة. السبب الموثَّق بتعليق
     طويل في الكود: لو الدخول كان عبر رابط عميق مباشر لشاشة المشاهدة
     (وليس عبر الشاشة الرئيسية)، كانت تهيئة الإعلانات تبدأ فقط عند فتح
     شاشة المشاهدة نفسها (مهلة انتظار قصيرة 4 ثوانٍ من بداية باردة) فتفشل
     غالباً في اللحاق بعرض الإعلان البيني في الوقت المناسب.
   - بالتوازي أيضاً: `AppLinks().getInitialLink()` — يتحقق هل التطبيق فُتح
     عبر رابط قادم من تطبيق المحتوى **قبل** بناء أي واجهة، حتى يقرر من أول
     لحظة: عرض شاشة المشاهدة مباشرة كشاشة وحيدة (بدون أي splash أو شاشة
     رئيسية خلفها إطلاقاً)، أو المرور بمسار الشاشة الرئيسية العادي.
3. لا توجد أي شاشة Splash في هذا التطبيق إطلاقاً (بعكس تطبيق المحتوى) —
   إما `_LoadingApp` (سبينر أسود بسيط أثناء التهيئة) أو مباشرة `PlayerApp`.
4. `PlayerApp` (StatefulWidget):
   - `MaterialApp` بعنوان `'BinSheikh Player'`، `ThemeData.dark(useMaterial3: true)`،
     `locale: Locale('ar')` (بدون `localizationsDelegates` — بعكس تطبيق
     المحتوى الذي يضيفها صراحة؛ لم يُلاحَظ نفس عطل الاتجاه هنا في هذا الملف).
   - `home:` يُحسب من `initialUri` عند أول إقلاع فقط: لو الرابط يحمل
     `channelId` أو `url` كـ query parameter → يبني `WatchScreen` ويجعلها
     الشاشة الوحيدة (`initialWatchScreen`)؛ وإلا → `HomeScreen` العادية.
   - `_PlayerAppState` تستمع أيضاً لروابط تصل **أثناء تشغيل التطبيق**
     (`AppLinks().uriLinkStream`) — رابط الإقلاع الأول عولج مسبقاً في
     `_BootAppState` فلا يُعاد معالجته هنا.
   - `_handleRuntimeUri`: عند وصول رابط جديد أثناء العمل (تبديل قناة من
     تطبيق المحتوى مثلاً)، يستخدم
     `navigatorKey.currentState?.pushAndRemoveUntil(...، (route) => false)`
     بانتقال **فوري بلا أنيميشن** (`transitionDuration: Duration.zero`)
     ليفرّغ المكدس بالكامل ويجعل شاشة المشاهدة الجديدة الوحيدة — بهذا
     يبقى زر الخروج متسقاً دائماً (يغلق المشغل بالكامل ويرجع لتطبيق
     المحتوى، وليس "يعلّق" على شاشة داخلية).

### شكل الرابط العميق المتوقَّع
- الـ scheme: `sportsplayer://play?channelId=<id>` (يمكن أيضاً `?url=<رابط مشفّر>`
  بدل `channelId`، ويُفكّ بـ `Uri.decodeFull`).
- مسجَّل في `AndroidManifest.xml` عبر `intent-filter` بـ
  `android:scheme="sportsplayer" android:host="play"`.

---

## 5) شاشة المشاهدة (`watch_screen.dart`) — الأهم والأكبر (~1160 سطر)

### الإنشاء
`WatchScreen({channelId, externalUrl, externalUserAgent})` — تُفتح بأحد
مسارين حصراً:
1. من `HomeScreen._play(link)` بتمرير `externalUrl` + `externalUserAgent`
   (رابط أدخله المستخدم يدوياً من "إضافة رابط").
2. من رابط عميق خارجي بتمرير `channelId` فقط (القناة من تطبيق المحتوى).

### تسلسل بدء التشغيل (initState)
```
initState()
  → _checkUpdateThenStartPlayback()   [أُضيف لاحقاً — راجع القسم 7]
      → VersionCheckService.checkForceUpdate()
      → لو forceUpdate != null: توقف تماماً، لا شيء آخر يعمل
      → غير ذلك: _prepareAndStartPlayback()
          → لو فيه instance سابق نشط (_activeInstance ثابت على مستوى الكلاس):
              يستدعي عليه _stopBeforeInterstitial() (كتم الصوت + إيقاف مؤقت،
              بانتظار فعلي قبل المتابعة) — يمنع "صوت خلف الإعلان" عند
              تبديل قناة سريع بينما المشغل يعمل بالفعل بالخلفية.
          → يسجّل نفسه instance نشط جديد (_activeInstance = this)
          → WidgetsBinding.instance.addObserver(this)  [لمراقبة دورة حياة التطبيق]
          → _scheduleHide()  [مؤقّت إخفاء أزرار التحكم بعد 4 ثوانٍ]
          → AdService.instance.showInterstitialThenProceed(callback)
              → لو نجح/فشل/انتهت المهلة: ينفّذ callback الذي يستدعي _startSession()
```

### تحديد مصدر البث (`_startSession` → يبني `StreamSession`)
- لو `externalUrl` موجود: جلسة مباشرة بسيرفر واحد وجودة واحدة (كما هو).
- لو `channelId` موجود: `ChannelSourceResolver.resolve(channelId)`:
  1. يقرأ `channels/{channelId}` من Firestore.
  2. لو الحقل `protected == false` صراحة (قناة غير محمية):
     - لو `status == 'disabled'` → فشل فوري ("هذه القناة متوقفة مؤقتاً").
     - وإلا: يبني الجلسة مباشرة من الحقل `servers` (قائمة سيرفرات/جودات)
       إن وُجد، أو من `directUrl` كسيرفر واحد جودة "تلقائي" واحدة.
     - **لا يمر بالخادم الخلفي إطلاقاً** لهذا النوع من القنوات.
  3. غير ذلك (الافتراضي، أي قناة بدون `protected: false` صريحة تُعامَل
     كمحمية): يستدعي `StreamAuthService.requestSession(channelId)`.
  4. أي استثناء أثناء قراءة Firestore يُبتلَع ويكمل مباشرة للمسار المحمي
     (fail-safe نحو الأكثر أماناً، وليس الأقل).
- لو لا `channelId` ولا `externalUrl`: فشل ("لا يوجد مصدر بث لتشغيله").

### `StreamAuthService.requestSession` (الخادم الخلفي)
- POST إلى `$kWorkerBaseUrl/getStreamUrl` بجسم `{"channelId": ...}`، مهلة 15 ثانية.
- يدعم شكلي استجابة:
  - **جديد (متعدد السيرفرات):** `{kind, isLive, servers: [{label, qualities: [{label, url}]}]}`.
  - **قديم (مبسّط):** `{url, expiresIn}` → يُحوَّل تلقائياً لسيرفر واحد "السيرفر
    الرئيسي" بجودة واحدة "تلقائي".
- أخطاء HTTP ≥ 400 تُترجم لرسائل عربية حسب حقل `error`:
  `not-found` → "هذه القناة غير متاحة حالياً"، `permission-denied`/`unauthenticated`
  → "لا تملك صلاحية مشاهدة هذه القناة"، `resource-exhausted` → "الخادم
  مشغول حالياً، حاول بعد قليل"، غير ذلك → رسالة `message` من الخادم أو نص عام.
- **ما يصل فعلياً من الخادم لأي قناة محمية اليوم ليس رابط m3u8 الحقيقي**،
  بل رابط بروكسي HLS موقّت من نفس الـ Worker (`/hls/{channelId}/playlist.m3u8?exp=...&sig=...`)
  — راجع القسم 8 لتفاصيل هذا البروكسي؛ رابط `privateStreams/{id}.url` الحقيقي
  لا يصل لجهاز المستخدم إطلاقاً ولا حتى لحظة واحدة.

### التشغيل الفعلي (`_playServerQuality`)
- يتخلّص من أي `VideoPlayerController` سابق (`removeListener` ثم `dispose`).
- `VideoPlayerController.networkUrl(uri, httpHeaders: _headers ?? {})` —
  `_headers` تُبنى فقط لو `externalUserAgent` مُمرَّر (`{'user-agent': ...}`).
- `initialize()` → `setPlaybackSpeed(_playbackSpeed)` → `setVolume(...)` →
  `play()` → `WakelockPlus.enable()`.
- عند أي استثناء: `_describePlaybackError(error)` يحاول تصنيف السبب من نص
  رسالة الخطأ نفسها (لا توجد طريقة أدق من `video_player`):
  - `socketexception`/`failed host lookup`/`network is unreachable`/
    `unable to connect`/`connection refused` → "تعذر الاتصال بالخادم...".
  - `timeout`/`timed out` → "انتهت مهلة الاتصال بالخادم...".
  - `404`/`403`/`410`/`gone`/`forbidden` → "انتهت صلاحية هذا الرابط...".
  - `unrecognized`/`unsupported`/`source error`/`parsererror`/`format` →
    "صيغة هذا المصدر غير مدعومة...".
  - غير ذلك → "تعذر تشغيل هذا المصدر. جرّب سيرفر أو جودة أخرى.".

### حالة الشاشة (`_LoadState`): `loading` / `error` / `ready`
- **loading:** سبينر + نص "جارٍ التحقق من صلاحية المشاهدة…".
- **error:** أيقونة خطأ + رسالة + أزرار (إعادة المحاولة، تغيير السيرفر إن
  وُجد أكثر من سيرفر، رجوع).
- **ready:** الفيديو + طبقة تحكمات متحركة الشفافية.

### أدوات التحكم أثناء التشغيل (كلها داخل `_buildControls`)
- **الشريط العلوي:** رجوع، شارة "مباشر" (حمراء) أو تسمية الجودة الحالية
  إن لم يكن مباشراً، زر كتم الصوت، Slider مستوى الصوت (0-100)، زر "المزيد".
- **زر قفل الشاشة:** يبقى ظاهراً دائماً (فوق كل شيء، أعلى يسار) حتى أثناء
  القفل — لضمان قدرة المستخدم دائماً على إلغاء القفل. القفل يعطّل
  `_toggleControls` بالكامل.
- **منتصف الشاشة:** تشغيل/إيقاف مؤقت (زر كبير)، وتراجع/تقديم 10 ثوانٍ
  (يظهران فقط لو `!isLive`).
- **الشريط السفلي:** لغير المباشر — وقت حالي + Slider تقدّم (قابل للسحب،
  `onChanged` ينادي `seekTo` مباشرة) + المدة الكلية؛ للمباشر: مسافة فارغة
  (`Spacer`) بدل الشريط. زر ملء الشاشة في الحالتين.
- **قائمة "المزيد" (Bottom Sheet):** وضع العرض (`contain`/`cover` تبديل)،
  الجودة والسيرفر (تظهر فقط لو أكثر من سيرفر أو أكثر من جودة)، سرعة
  التشغيل (0.5x حتى 2x بخطوات: 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2)، التقاط صورة.

### الإيماءات (Gestures)
- **نقر مزدوج:** يمين الشاشة = تقديم 10 ثوانٍ، يسار = تراجع 10 ثوانٍ (غير
  فعّال في المباشر) + أيقونة تأكيد تظهر وتختفي بعد نصف ثانية بمحاذاة الحافة.
- **سحب أفقي:** تقديم/تراجع بالثواني (كل 28 بكسل = 5 ثوانٍ) — غير فعّال بالمباشر.
- **سحب رأسي (أي مكان بالشاشة):** تحكم بمستوى الصوت فقط (0-100٪ حسب نسبة
  ارتفاع الشاشة المسحوبة). **ملاحظة موثَّقة صراحة بالكود:** كان مقسّماً
  سابقاً يمين/يسار (يمين = صوت، يسار = سطوع الشاشة)، لكن جزء السطوع لم
  يكن منفّذاً فعلياً (كان يرجع بلا أي تأثير) — أُزيل التقسيم بالكامل
  وأصبح السحب الرأسي في أي مكان يتحكم بالصوت فقط. **لا توجد ميزة تحكم
  بسطوع الشاشة في هذا التطبيق حالياً.**
- **نقرة واحدة:** إظهار/إخفاء طبقة التحكمات (معطّلة أثناء القفل).

### مؤشر "الاتصال بطيء"
- عند بدء تخزين مؤقت (buffering)، مؤقّت 6 ثوانٍ: لو استمر التخزين المؤقت
  بعد 6 ثوانٍ متواصلة، تظهر شارة صغيرة (أسفل يمين، وليس منتصف الشاشة) بنص
  "اتصال بطيء". **لا تُقاس سرعة الشبكة فعلياً** (video_player لا يوفرها) —
  فقط مدة الانتظار كمؤشر تقريبي. كل عملية seek يدوية (تقديم/تراجع/سحب)
  تُلغي المؤقّت وتبدأ عدّاً جديداً بدل التراكم على نفس المؤقّت القديم.

### دورة حياة التطبيق (`didChangeAppLifecycleState`)
- `paused`/`inactive`/`detached`/`hidden`: لو كان يعمل فعلاً → `pause()` +
  تسجيل `_wasPlayingBeforeBackground = true`.
- `resumed`: لو كان يعمل قبل الانقطاع → `play()` تلقائياً. **هذا بالتحديد
  ما يجعل التشغيل يستأنف تلقائياً بعد إغلاق إعلان AdMob البيني** (عرض
  الإعلان يُخرج النشاط مؤقتاً فيُطلق نفس مسار paused/resumed هذا) بدون
  حاجة لضغط تشغيل يدوي بعد كل إعلان.

### التقاط لقطة شاشة
- `RepaintBoundary` حول عنصر الفيديو → `toImage` → PNG bytes.
- أندرويد/iOS: `ImageGallerySaverPlus.saveImage` (يحفظ في معرض الصور).
- غير ذلك: يُحفظ في `getApplicationDocumentsDirectory()`.

### الخروج (`_exit`)
- لو فيه شاشة سابقة بالمكدس (`Navigator.canPop()`): يرجع لها عادي.
- وإلا (فُتح التطبيق مباشرة عبر رابط، شاشة المشاهدة هي الوحيدة):
  `SystemNavigator.pop()` — يغلق تطبيق المشغل بالكامل ويرجع المستخدم
  مباشرة لتطبيق المحتوى، بدل التعليق على شاشة داخلية فارغة.

### `dispose()`
- يمسح `_activeInstance` إن كان هو، يزيل مراقب دورة الحياة، يلغي كل
  المؤقّتات، يوقف الفيديو، `WakelockPlus.disable()`، يعيد النظام لوضع
  `edgeToEdge` والاتجاهات الافتراضية (يخرج من ملء الشاشة تلقائياً).

---

## 6) الشاشة الرئيسية (`home_screen.dart`)

- تُفتح فقط لو لم يُفتح التطبيق عبر رابط عميق. **لا تعرض أي قنوات من
  تطبيق المحتوى** — فقط "الروابط المحفوظة" التي أضافها المستخدم يدوياً.
- `AppBar`: عنوان "BinSheikh Player" + زر "إضافة رابط بث" (أعلى).
- `FloatingActionButton.extended`: "إضافة رابط" (يفتح `AddUrlScreen`، وعند
  النجاح `_reload()` القائمة).
- **زر "الاشتراك المميز":** مخفي بالكامل افتراضياً. يظهر فقط لو
  `settings/player.premiumEnabled == true` **و** `premiumUrl` غير فارغ
  (كلاهما شرط معاً). النص القابل للتخصيص من `premiumButtonText` (افتراضي:
  "الاشتراك المميز"). أي فشل بجلب الإعدادات → يبقى مخفياً (fail-safe نحو
  الإخفاء، بعكس رابط المتجر الذي له قيمة احتياطية ثابتة).
- **القائمة (Drawer):** اتصل بنا، مشاركة التطبيق (`Share.share` برسالة
  ثابتة + رابط المتجر)، قيّم التطبيق (يفتح `storeUrl` في المتصفح/المتجر)،
  الشروط والخصوصية.
- **رابط المتجر الاحتياطي الثابت (Hardcoded):**
  `https://play.google.com/store/apps/details?id=com.midoalhashmi.zoltrastream`
  — يُستبدل لو `settings/app.storeUrl` مضبوط في Firestore.
- **بانر إعلاني:** أسفل الشاشة الرئيسية فقط (لا يظهر إطلاقاً في شاشة
  المشاهدة). يُحمَّل فقط بعد نجاح `AdService.instance.initialize()`
  وبعد تأكيد `onAdLoaded` فعلياً (وليس فور الإنشاء) — تعليق بالكود يوثّق
  أن هذا إصلاح لخطأ سابق كان البانر لا يظهر رغم نجاح تحميله لعدم استدعاء
  `setState` في اللحظة الصحيحة.
- **الروابط المحفوظة:** قائمة بطاقات (`ListView.separated`)، كل بطاقة:
  عنوان، الرابط (سطر واحد مع `...`)، ضغطة = فتح `WatchScreen` بهذا الرابط،
  أيقونة حذف.

---

## 7) التحديث الإجباري (`version_check_service.dart` + `force_update_gate.dart`)

> هذه الميزة كانت **موجودة بالكود لكن معطّلة فعلياً** (الخدمة لم تُستدعَ من
> أي مكان) حتى أُصلحت لاحقاً بربطها فعلياً بشاشتي الدخول. الوصف أدناه
> يعكس الحالة **بعد** الإصلاح.

### `VersionCheckService.checkForceUpdate()`
- يقرأ `settings/player` من Firestore، حقل `minVersion` (نص "1.2.3").
- لو الحقل فارغ/غير موجود، أو تعذّر الجلب (بدون إنترنت) → `null` (لا حجب).
- يقارن رقم الإصدار المثبَّت فعلياً على الجهاز (عبر `package_info_plus`)
  برقم `minVersion` جزءاً بجزء (وليس كنص): أي جزء غير رقمي يُعامَل كصفر
  بدل رمي استثناء يوقف الفحص كاملاً.
- لو المثبَّت أقل: يحتاج أيضاً حقل `updateUrl` (رابط فعلي) وإلا يرجع
  `null` أيضاً — **لا تُعرض شاشة حجب بدون زر فعّال أبداً.**
- عند الحاجة الفعلية للتحديث، يرجع `ForceUpdateInfo(requiredVersion,
  currentVersion, updateUrl)`.

### `ForceUpdateGate` (ودجت مشترك، `lib/widgets/force_update_gate.dart`)
- ثلاث حالات فقط:
  1. أثناء الفحص: `Scaffold` أسود بسيط + `CircularProgressIndicator`.
  2. تحديث مطلوب: `PopScope(canPop: false)` (يمنع زر الرجوع تماماً) يحيط
     بـ `Scaffold` أسود: أيقونة `system_update`، نص "يوجد تحديث جديد"،
     نص فرعي "يجب تحديث التطبيق للمتابعة. لا يمكن استخدام التطبيق قبل
     إتمام التحديث."، **زر "تحميل" واحد فقط** (لا يوجد أي زر آخر، لا
     تجاهل، لا إغلاق) يفتح `updateUrl` عبر `launchUrl(... externalApplication)`.
  3. غير ذلك: يعرض `child` (الشاشة الفعلية) فوراً.
- **يُستخدم في نقطتين فقط** (وليس في `main.dart` المحمي): تُغلَّف
  `Widget build()` في كل من `HomeScreen` و`WatchScreen` بـ
  `ForceUpdateGate(child: _buildScaffold(context))`.
- **في `WatchScreen` تحديداً:** الحجب البصري وحده لا يكفي، لأن `initState`
  يبدأ التشغيل الفعلي بغض النظر عن ما يُعرض في `build()`. لذلك `initState`
  نفسه يستدعي أولاً `VersionCheckService.checkForceUpdate()` (فحص مستقل
  ثانٍ)، ولا يستدعي `_prepareAndStartPlayback()` (وبالتالي لا تحميل ولا
  تشغيل بث ولا إعلان) إلا لو رجع `null`. الفحصان (في `initState` وفي
  `ForceUpdateGate` الداخلي) مستقلان ومتكرّران عمداً لضمان اتساق النتيجة
  في المكانين — تكلفته قراءة Firestore إضافية واحدة فقط، بلا أي أثر جانبي.

---

## 8) الإعلانات (`ad_service.dart`, AdMob فقط، 320 سطر)

- **لا تُقرأ إعدادات الإعلانات إلا من `settings/ads`:**
  ```
  settings/ads {
    enabled: bool,
    admob: {
      appId: string,          // للمطابقة فقط (راجع أدناه) — لا يُستخدم لتغيير AndroidManifest
      bannerId: string,
      interstitialId: string,
      rewardedId: string      // محفوظ لمستقبل، لا توجد شاشة إعلان مكافئ حالياً
    }
  }
  ```
- **دعم AdMob فقط حالياً** رغم أن لوحة التحكم قد تحفظ حقولاً لشبكات أخرى
  (applovin/unity) — لا تُقرأ من هنا لعدم إضافة حزم SDK الخاصة بها بعد.
- **معرّفات الاختبار الافتراضية (Google الرسمية):**
  - `interstitial`: `ca-app-pub-3940256099942544/1033173712`
  - `banner`: `ca-app-pub-3940256099942544/6300978111`
  - `appId` (يطابق ما في AndroidManifest): `ca-app-pub-3940256099942544~3347511713`
- **حارس "نصف التهيئة" (مهم جداً لفهم سلوك الإعلانات):** معرّف تطبيق AdMob
  (App ID) **لا يمكن** تغييره إلا من `AndroidManifest.xml` وقت البناء —
  لا يمكن قراءته من Firestore وتطبيقه في وقت التشغيل. لذلك: إذا حقل
  `admob.appId` في لوحة التحكم لا يزال يساوي معرّف الاختبار (فارغ أو مطابق
  حرفياً)، **تُتجاهَل تماماً** أي أكواد وحدات إعلانية حقيقية أُدخلت
  (`bannerId`/`interstitialId`) وتُستخدم معرّفات الاختبار للجميع، حتى لو
  كانت مدخلة فعلاً في اللوحة. هذا يمنع فشلاً صامتاً ونصفياً (بانر يعمل
  والبيني لا، أو العكس) لأن Google ترفض بثبات طلب إعلان لوحدة حقيقية لا
  تنتمي لمعرّف تطبيق غير مُهيَّأ فعلياً بنفس القيمة الحقيقية.
- **UMP (User Messaging Platform) إلزامي قبل أي تهيئة:** `initialize()`
  يستدعي أولاً `_requestConsentAndShowFormIfRequired()` (يحدّث معلومات
  الموافقة، يعرض نموذج الموافقة تلقائياً إن كان مطلوباً — أساساً لمستخدمي
  المنطقة الاقتصادية الأوروبية/بريطانيا). فقط لو رجعت `canRequestAds() ==
  true` يبدأ `MobileAds.instance.initialize()` ثم يجلب `_fetchConfig()`
  من Firestore. خارج أوروبا (كالسعودية) عادةً لا يظهر أي نموذج موافقة
  وتكمل هذه الخطوة مباشرة.
- **`Future<void>? _initFuture` (وليس علامة `bool` بسيطة):** لأن
  `initialize()` تُستدعى من مكانين مختلفين (`main.dart` عند الإقلاع،
  و`HomeScreen.initState`) بفارق زمني بسيط — علامة بسيطة كانت تجعل
  الاستدعاء الثاني يظن التهيئة اكتملت فوراً بينما لا تزال جارية فعلياً.
  تخزين الـ `Future` نفسه يضمن أن كل استدعاء ينتظر نفس العملية الجارية.
- **الإعلان البيني (Interstitial):**
  - حد أدنى 3 دقائق بين إعلانين متتاليين (`_minGapBetweenInterstitials`) —
    يمنع الإزعاج بإعلان جديد في كل تبديل قناة سريع.
  - `showInterstitialThenProceed(onComplete, {maxWait: 6 ثوانٍ})`: لو
    الإعلانات موقوفة، أو لم يمرّ الحد الأدنى بعد، أو لم يجهز الإعلان خلال
    مهلة الانتظار → ينفّذ `onComplete` مباشرة **بدون** تعليق المستخدم
    منتظراً إعلاناً لن يظهر (البث لا يبدأ تحميله أو تشغيله حتى استدعاء
    `onComplete`).
  - يُحمَّل الإعلان التالي مسبقاً (`_preloadInterstitial`) فور إغلاق أي
    إعلان أو فشل عرضه.
- **البانر:** `createBannerAd` يستدعي `onAdLoaded`/`onLoadFailed` — لا
  يُسنَد للعرض إلا بعد `onAdLoaded` فعلياً.
- **خيارات خصوصية الإعلانات:** `showPrivacyOptionsFormIfAvailable()` يُستدعى
  من زر بشاشة "الشروط والخصوصية" — يعرض نموذج خصوصية الإعلانات فقط لو
  `getPrivacyOptionsRequirementStatus() == required`.

### AndroidManifest — إعدادات الإعلانات
```xml
<uses-permission android:name="com.google.android.gms.permission.AD_ID"/>
<!-- ... -->
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-3940256099942544~3347511713"/>
```
تعليق صريح بالكود يوضح: هذا معرّف اختبار Google الرسمي، آمن للتجربة، ويجب
استبداله يدوياً بمعرّف AdMob الحقيقي قبل النشر النهائي (البانر/البيني
يُقرآن ديناميكياً من `settings/ads` ولا يحتاجان إعادة بناء، لكن هذا الحقل
تحديداً يحتاج إعادة بناء دائماً).

---

## 9) القنوات غير المحمية vs المحمية (النموذج الأمني الكامل)

### القناة **المحمية** (الافتراضي، أي قيمة غير `protected: false` صراحة)
- رابط البث الحقيقي (m3u8) يُخزَّن **فقط** في `privateStreams/{channelId}`،
  وهذه المجموعة **ممنوعة القراءة تماماً** من أي عميل (تطبيق محتوى أو
  مشغل) — راجع `firestore.rules` في القسم الخاص بتطبيق المحتوى. الوصول
  الوحيد لها هو عبر الخادم الخلفي (Cloudflare Worker) الذي يملك بيانات
  اعتماد حساب خدمة Google منفصلة تتجاوز قواعد Firestore هذه.
- المشغل يطلب من `/getStreamUrl` بالـ Worker، ويحصل على **رابط بروكسي HLS
  موقّت** (وليس الرابط الحقيقي مطلقاً):
  `https://<worker>/hls/{channelId}/playlist.m3u8?exp=<انتهاء>&sig=<توقيع>`.
- التوكن: HMAC-SHA256 (`HLS_TOKEN_SECRET` سرّ في الـ Worker)، صلاحية **4
  دقائق فقط** لكل توكن (`HLS_TOKEN_TTL_SECONDS = 240`). التحقق يقارن
  بوقت ثابت (`timing-safe comparison`) لتفادي هجمات التوقيت.
- الـ Worker نفسه يعمل كبروكسي: يجلب `playlist.m3u8` الحقيقي من المصدر
  (بدون كشفه للعميل)، ويعيد كتابة كل سطر رابط داخله ليمر عبر نفس الـ
  Worker بنفس التوكن (`rewriteHlsPlaylist`)، بما في ذلك ملفات الـ segments
  (.ts/.m4s) التي تُبثّ مباشرة (streamed) بدون تحميلها كاملة بالذاكرة.
- **النتيجة: لا يصل رابط المصدر الحقيقي لجهاز المستخدم إطلاقاً ولا حتى
  لحظة واحدة، ولا حتى داخل حركة الشبكة القابلة للفحص.**

### القناة **غير المحمية** (`channels/{id}.protected == false` صراحة)
- تُقرأ مباشرة من مستند القناة نفسه في `channels` (مجموعة عامة القراءة):
  إما حقل `servers` (قائمة سيرفرات/جودات كاملة)، أو `directUrl` كخيار
  أبسط (سيرفر واحد "مباشر" بجودة واحدة "تلقائي").
- **لا يمر أي طلب على الخادم الخلفي إطلاقاً لهذا النوع.**
- لو `status == 'disabled'` تُرفض القناة فوراً حتى لو غير محمية (فحص أُضيف
  لاحقاً — كان غائباً سابقاً فتستمر القنوات المعطَّلة بالعمل رغم التعطيل).

---

## 10) تخزين محلي (SharedPreferences)

- **`favorite_channel_ids`** — لا يُستخدم في هذا التطبيق (موجود فقط في
  تطبيق المحتوى عبر `FavoritesService` هناك؛ المشغل لا يملك مفهوم مفضلة).
- **`saved_links_v1`** (في هذا التطبيق): قائمة نصوص JSON، كل عنصر
  `{id, title, url, userAgent}` — الروابط اليدوية المضافة من "إضافة رابط".

---

## 11) عقد الربط الكامل مع تطبيق المحتوى

1. تطبيق المحتوى يحاول **Intent صريح** أولاً (`AndroidIntent` بحزمة
   `android_intent_plus`) موجّه بالضبط لـ `settings/player.androidPackage`
   (القيمة الحالية المتوقَّعة: `com.midoalhashmi.zoltrastream`) — يضمن فتح
   هذا المشغل تحديداً بدون نافذة اختيار أو تعارض مع أي تطبيق آخر مسجَّل
   لنفس الـ scheme.
2. لو فشل (المشغل غير مثبَّت، أو اسم الحزمة غير مضبوط، أو الجهاز رفض
   الـ Intent الصريح): يجرّب رابطاً داخلياً عاماً
   `sportsplayer://play?channelId=<id>` عبر `url_launcher` كخطة بديلة.
3. لو فشل الاثنان: حوار "تطبيق المشغل مطلوب" بزر "تحميل المشغل" (يفتح
   `settings/player.storeUrl`).
4. **لا يُرسَل أي رابط بث أو توكن من تطبيق المحتوى للمشغل إطلاقاً — فقط
   `channelId` النصي.** المشغل هو من يطلب جلسة البث الفعلية بنفسه لاحقاً.

---

## 12) قواعد حماية المشروع (project-protection-rules.md) — إلزامية لأي نموذج

هذا الملف موجود فعلياً في المستودع ويجب اتّباعه حرفياً عند أي تعديل مستقبلي:

- **ملفات محمية (تحتاج إذناً صريحاً مسبقاً قبل أي لمس):**
  `lib/main.dart`، `lib/firebase_options.dart`،
  `android/app/google-services.json`، `android/build.gradle`،
  `android/app/build.gradle` (وتحديداً `applicationId`, `minSdkVersion`,
  `targetSdkVersion`, `compileSdkVersion`, `signingConfigs`)،
  `android/gradle/wrapper/gradle-wrapper.properties`، `codemagic.yaml`،
  ملفات التوقيع (`key.properties`, `.jks`/`.keystore`)، أرقام إصدارات
  الحزم **الموجودة أصلاً** في `pubspec.yaml`، وأسماء حقول/مجموعات Firestore
  المشتركة (`channels`, `settings/ads`, `settings/app`, `settings/legal`,
  `contact_messages`, إلخ — لأن ثلاثة مشاريع منفصلة تتفق على نفس الأسماء
  بالضبط).
- **ممنوع دون إذن صريح:** ترقية/إضافة/حذف أي حزمة، تغيير SDK/كومبايل/
  توقيع/applicationId، تعديل codemagic.yaml، اقتراح ترقية Flutter SDK نفسه.
- **التسليم:** ملف بملف فقط (مسار كامل لكل ملف)، وليس تفريغ المشروع كامل.
- **أي تعديل يمسّ بنداً محمياً:** التوقّف والشرح بالضبط أي ملف/سطر ولماذا،
  وانتظار "نعم" صريحة قبل التسليم — لا يُفترض القبول أبداً.
- الاسم المرجعي للـ keystore على Codemagic: `sports_player_release`.

---

## 13) أندرويد — تفاصيل AndroidManifest.xml كاملة

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
<uses-permission android:name="com.google.android.gms.permission.AD_ID"/>

<application android:label="BinSheikh Player" android:networkSecurityConfig="@xml/network_security_config">
  <activity android:name=".MainActivity"
      android:exported="true" android:launchMode="singleTop"
      android:supportsPictureInPicture="true" android:resizeableActivity="true">
    <intent-filter> <!-- الإطلاق العادي --> </intent-filter>
    <intent-filter>
      <action android:name="android.intent.action.VIEW" />
      <category android:name="android.intent.category.DEFAULT" />
      <category android:name="android.intent.category.BROWSABLE" />
      <data android:scheme="sportsplayer" android:host="play" />
    </intent-filter>
  </activity>
  <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
      android:value="ca-app-pub-3940256099942544~3347511713"/>
</application>
```
- يوجد `network_security_config` مخصص (لدعم HTTP غير المشفّر لبعض
  مصادر البث القديمة على الأرجح — راجع الملف الفعلي في
  `android/app/src/main/res/xml/network_security_config.xml`).
- `supportsPictureInPicture="true"` و`resizeableActivity="true"` مفعّلان
  على مستوى AndroidManifest، والقناة الأصلية (MethodChannel) لدعم PiP
  **موجودة وتعمل فعلياً** في `MainActivity.kt` (أندرويد 8+ فقط عبر فحص
  `Build.VERSION_CODES.O`) — لكن **لا يوجد أي زر أو استدعاء من طرف
  Dart/Flutter يستخدمها حالياً** (`pip_service.dart` غير مستورَد من أي
  شاشة). أي أن دعم PiP جاهز على مستوى النظام لكنه **غير قابل للاستخدام
  فعلياً من واجهة المستخدم اليوم.**

---

## 14) كود يتيم/ميت — قائمة كاملة (مهم لأي نموذج يعيد البناء)

| الملف | لماذا يتيم |
|---|---|
| `lib/services/youtube_id_extractor.dart` | ميزة تشغيل يوتيوب أُزيلت بالكامل من التطبيق (موثَّق في `task-status.md`: "تشغيل YouTube — ✅ منجز. أزيلت ميزة YouTube بالكامل، بما فيها شاشة التشغيل والمكتبة ومسارات الإعداد."). الملف باقٍ لكن غير مستورَد من أي مكان. |
| `lib/services/youtube_resolver.dart` | نفس السبب، ويستورد حزمة `youtube_explode_dart` **غير الموجودة في pubspec.yaml إطلاقاً** — لن يُبنى لو استُخدم. |
| `lib/services/tube_resolver.dart` | نسخة مكرّرة **أقدم** من `youtube_resolver.dart` (نفس اسم الصنف `YoutubeResolver`، منطق أبسط بدون دعم بث القناة المباشر بمعرّف غير صريح، ونفس مشكلة الحزمة المفقودة). كلاهما يتيم بالكامل. |
| `lib/services/feature_flags_service.dart` | يقرأ `settings/features.youtubeEnabled` — بلا فائدة الآن بعد إزالة يوتيوب بالكامل. غير مستورَد من أي شاشة. |
| `lib/services/pip_service.dart` | القناة الأصلية بـ Kotlin تعمل فعلياً، لكن لا شاشة تستدعيها من طرف Dart. غير مستورَد من أي شاشة. |
| `android/.../com/midoalhashmi/sportsplayer2026/MainActivity.kt` | من اسم الحزمة القديم قبل التغيير لـ `zoltrastream`؛ ملف فارغ (`class MainActivity : FlutterActivity()` بلا أي منطق إضافي) لم يُحذف بعد نقل اسم الحزمة. |

**توصية لأي نموذج يعيد البناء:** لا تُنشئ هذه الملفات إطلاقاً ضمن إعادة
البناء إلا إذا طُلبت ميزة يوتيوب أو PiP فعلياً من جديد — وفي هذه الحالة
استخدم فقط `youtube_resolver.dart` (الأحدث والأشمل) وليس `tube_resolver.dart`،
مع إضافة حزمة `youtube_explode_dart` فعلياً إلى `pubspec.yaml` أولاً.

---

## 15) ملاحظات وأخطاء معروفة مكتشفة في الكود الحالي

- **`main.dart` لا يستخدم `localizationsDelegates` صراحة** بعكس تطبيق
  المحتوى (الذي يحتاجها لإصلاح اتجاه RTL) — لم يُلاحَظ نفس عطل الاتجاه
  موثَّقاً هنا، لكن قد يستحق نفس الإصلاح مستقبلاً للاتساق.
- **مجلد `sportsplayer2026` اليتيم** يُبنى فعلياً ضمن مصادر Kotlin (Gradle
  يُصرّف كل ملفات `kotlin/` بغض النظر عن تطابق اسم الحزمة مع
  `applicationId`)، لكنه لا يُستخدم كنقطة دخول فعلية — تنظيف اختياري
  (يحتاج إذناً صريحاً لأنه ضمن مسار Android).
- **لا يوجد فحص لتوفر PiP أو زر تفعيله في أي شاشة** رغم وجود القناة
  الأصلية الكاملة — الميزة معطّلة فعلياً من ناحية الاستخدام رغم اكتمال
  نصف تنفيذها.

---

## 16) حالة الإنجاز (من task-status.md وقت كتابة هذا المستند)

- **مكتمل:** Network Security Config، توحيد اسم التطبيق "BinSheikh Player"،
  حذف شاشة Splash غير المستخدمة، تعليق `video_player` في pubspec (لاحظ:
  لاحقاً أُعيد استخدامه فعلياً لأنه أساس التشغيل الحالي — أي أن هذه
  الملاحظة القديمة في `task-status.md` قد تكون متجاوَزة زمنياً بالكود
  الفعلي؛ اعتمد الكود لا الملاحظة القديمة عند التعارض)، إزالة ميزة يوتيوب
  بالكامل، إصلاح صوت خلف الإعلان البيني، ربط التحديث الإجباري فعلياً
  (2026-09-05، راجع القسم 7).
- **معلَّق/غير معروف الحالة:** معرّف AdMob الحقيقي (الإعلانات موقوفة مؤقتاً
  بانتظار الحساب الحقيقي)، بصمة SHA-1 لمفتاح التوقيع الفعلي، App Bundle
  بدل APK، سياسة خصوصية مستضافة برابط عام، نموذج Data Safety بـ Play
  Console، Adaptive Icon بطبقتين، ربط `proguard-rules.pro` فعلياً بـ
  `build.gradle` (الملف موجود وصحيح لكن غير مُستدعى من `build.gradle`)،
  التحقق اليدوي من `targetSdkVersion` وقت البناء.

---

## 17) إرشادات ختامية لأي نموذج يعيد بناء هذا التطبيق من الصفر

1. ابدأ بـ Firebase + Firestore (نفس مشروع تطبيق المحتوى تماماً —
   المشروعان يتشاركان نفس قاعدة البيانات، فلا تُنشئ مشروع Firebase منفصل).
2. نفّذ `ChannelSourceResolver` + `StreamAuthService` + الخادم الخلفي
   (Cloudflare Worker، راجع القسم 8 ومستند تطبيق المحتوى للتفاصيل الكاملة
   لمنطق التوكن والبروكسي) **قبل** شاشة المشاهدة — الشاشة تعتمد عليهما.
3. اجعل `ForceUpdateGate` أول ودجت يُبنى من كل شاشة دخول (Home وWatch)،
   ونفّذ فحص التحديث الإجباري **داخل `initState`** أيضاً لأي شاشة قد تبدأ
   عملاً حقيقياً (تحميل بث، طلب شبكة) فور إنشائها — الحجب البصري وحده لا
   يكفي لإيقاف آثار جانبية بدأت من `initState`.
4. لا تُنشئ أي ميزة يوتيوب أو PiP ما لم تُطلب صراحة — الكود القديم موجود
   لكنه ميت عمداً بعد قرار إزالة الميزتين (راجع القسم 14).
5. التزم بـ `project-protection-rules.md` حرفياً (القسم 12) عند أي تعديل
   على مشروع فعلي قائم.
