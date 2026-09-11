# التوثيق التقني — sports_player (تطبيق المشغل)

> هذا الملف مرجع تقني شامل لهذا المستودع، بحيث يقدر أي مبرمج أو نموذج ذكاء
> اصطناعي آخر يفهم بنية المشروع كاملة بدون الحاجة لقراءة كل الكود من الصفر.
> **كل تعديل جوهري أو إصلاح مشكلة لاحق يُضاف كصف جديد في جدول "سجل المشاكل
> والحلول" بالأسفل** — سطر واحد مختصر لكل عمود، بدون كود أو شرح مطوّل
> (التفاصيل الكاملة موجودة برسالة الكوميت نفسها، هذا الجدول فهرس سريع فقط).

## 1. نظرة عامة على المنظومة الكاملة (3 مستودعات مترابطة)

هذا المشروع جزء من منظومة من 3 مستودعات منفصلة على GitHub تتشارك نفس
مشروع Firebase ونفس Cloudflare Worker:

| المستودع | الدور |
|---|---|
| **BinSheikh** | تطبيق المحتوى الرئيسي (Flutter/Android) — يعرض للمستخدم النهائي الأقسام/القنوات/الأفلام/المسلسلات/الأنمي/مباريات اليوم. |
| **sports_player** (هذا المستودع) | تطبيق Flutter/Android منفصل، وظيفته الوحيدة تشغيل الفيديو الفعلي. يُفتح من BinSheikh عبر `app_links` بمعرّف قناة/حلقة. فصله كتطبيق مستقل يتيح تحديثه في Play Store بدون أي حاجة لتحديث BinSheikh، ويعزل منطق حل الروابط الحقيقية/الحماية عن تطبيق المحتوى العام. |
| **AHMED-dashboard** | لوحة تحكم ويب ثابتة (HTML/JS/CSS خام، بدون أي أداة بناء) يديرها فريق المحتوى — إضافة/تعديل الأقسام والقنوات والروابط، ومتابعة إحصائيات المشاهدة. |

- **مشروع Firebase المشترك**: `sports-stream-app-36a7a` (نفس Firestore، نفس
  Auth) — راجع `lib/firebase_options.dart`.
- **Cloudflare Worker المشترك**: `https://binsheikh-api.binsheikh.workers.dev`
  (كوده المصدري داخل مستودع BinSheikh في `cloudflare-worker/`) — يخدم روابط
  البث الحقيقية ومباريات اليوم والتقييمات واستيراد المواقع.

## 2. هذا المستودع (sports_player)

- **الغرض**: تطبيق Flutter/Android، وظيفته الوحيدة تشغيل فيديو HLS/MP4 لقناة
  أو حلقة معيّنة يُمرَّر إليه معرّفها.
- **Flutter SDK المستخدم**: 3.27.0 (حسب `codemagic.yaml`).
- **التبعيات الأساسية** (`pubspec.yaml`):
  - `video_player` — التشغيل الأصلي (ExoPlayer على أندرويد)، يدعم HLS وMP4
    فقط عملياً (لا DASH/RTMP/MKV رغم ما كان مكتوباً سابقاً بالكود).
  - `webview_flutter` — لعرض صفحات بث كويب عند `streamType=web`.
  - `firebase_core` + `cloud_firestore`.
  - `http` — لطلبات StreamAuthService والتشخيص.
  - `wakelock_plus`, `google_mobile_ads`, `share_plus`, `url_launcher`,
    `package_info_plus`, `shared_preferences`, `image_gallery_saver_plus`.

### بنية `lib/`

- `main.dart` — نقطة الدخول: تهيئة Firebase + معالج أخطاء عام
  (`runZonedGuarded` + `FlutterError.onError` + `PlatformDispatcher.onError`)
  يسجّل أي خطأ غير ملتقط عبر `SessionLogService`.
- `screens/watch_screen.dart` (~4700 سطر) — **الشاشة الأهم والأكبر**. آلة
  حالة كاملة لتشغيل الفيديو: تجربة عدة سيرفرات/جودات (`_WebNetworkCandidate`)،
  التبديل بين تشغيل native (`video_player`) وWebView، اكتشاف تلقائي لمصدر
  الفيديو من صفحة ويب (`_autoDetectWebSource`) عبر تتبّع طلبات شبكة داخل
  WebView، وتسجيل أحداث تشخيصية عبر `SessionLogService` (`_slog`) لتحليلها
  لاحقاً من سجل مُصدَّر (راجع مهارة `stream-debug` إن وُجدت في
  `.claude/skills/`).
- `screens/home_screen.dart`, `add_url_screen.dart`, `contact_screen.dart`,
  `force_update_screen.dart`, `terms_privacy_screen.dart` — شاشات مساعدة.
- `services/stream_auth_service.dart` — يطلب جلسة بث من الووركر
  (`POST /getStreamUrl`)، يدعم شكل استجابة متعدد السيرفرات/الجودات وشكل قديم
  مبسّط (`{url, expiresIn}`) لتوافق رجعي.
- `services/channel_source_resolver.dart`, `api_source_resolver.dart` — حل
  مصدر القناة (رابط مباشر مخزَّن أو مصدر API ديناميكي).
- `services/session_log_service.dart` — يجمع سجلاً نصياً زمنياً لكل جلسة
  تشغيل، قابلاً للتصدير — هذا هو أساس التشخيص عن بعد بدون وصول فعلي لجهاز
  المستخدم.
- `services/native_cookie_service.dart`, `worker_config.dart`,
  `version_check_service.dart`, `feature_flags_service.dart`,
  `pip_service.dart`, `player_visibility_service.dart`,
  `saved_link_service.dart`, `ad_service.dart`.
- `theme/app_theme.dart` — خط Tajawal + الألوان الموحّدة.

## 3. تدفق تشغيل الفيديو (مختصر)

1. يُفتح `watch_screen` بمعرّف قناة/حلقة (`channelId`) من BinSheikh عبر
   `app_links`، أو يدوياً من `add_url_screen`.
2. `StreamAuthService.requestSession(channelId)` → `POST /getStreamUrl` على
   الووركر.
3. الووركر يتحقق من Firestore (`channels` + `privateStreams`) ويرجّع إما
   رابطاً واحداً أو عدة سيرفرات/جودات.
4. `watch_screen` يجرّب كل مصدر بالترتيب: تشغيل native أولاً
   (`video_player`/ExoPlayer)، ولو فشل أو كان `streamType=web` يحوّل لـ
   WebView مع اكتشاف تلقائي للمصدر الحقيقي من طلبات الشبكة.
5. كل خطوة تُسجَّل عبر `SessionLogService` — هذا هو السجل الذي يُصدَّر من
   التطبيق ويُستخدم للتشخيص.

## 4. الحماية الأمنية

روابط m3u8 الحقيقية **غير مخزّنة إطلاقاً** بهذا التطبيق ولا تُقرأ مباشرة من
Firestore — تُجلب فقط عبر `/getStreamUrl` بالووركر (الذي يقرأ
`privateStreams` بصلاحيات خاصة لا تصل لأي عميل).

## سجل المشاكل والحلول

| # | المشكلة | الحل | الكوميت |
|---|---|---|---|
| 1 | رابط بمسار مزدوج `//` (`vidtube.cam//`) لا يُكتشف كـ"غير وسائط" | تعميم `_isNonMediaAsset` ليطابق أي عدد شرطات، لا `/` فقط | `995a558` |
| 2 | حالة `nativePlaying` تُستبدل بصمت بعد نجاح التشغيل (يعيد اكتشاف الويب) | حارس مركزي داخل `_setWebSessionState` يرفض مغادرتها | `d6d1d28` |
| 3 | كود ميت + تحذيرات lint (3 ملفات غير مستخدمة، حقول ميتة...) | حذف/تنظيف + `analysis_options.yaml` (`flutter_lints`) | `3c9e51c` |
| 4 | لا معالج أخطاء عام — خطأ غير ملتقط يُسقط التطبيق بصمت | `runZonedGuarded`+`FlutterError.onError`+`PlatformDispatcher.onError` بـ`main.dart` | نفس `3c9e51c` |
| 5 | تعذّر تشخيص "Source error" من ExoPlayer بالسجل النصي وحده | تسجيل أحداث buffering/error + فحص HTTP Range تشخيصي عند فشل native | `1eae933`, `721cde3` |
| 6 | إخفاء صفحة المصدر (إعداد إلزامي) أقل موثوقية من إظهارها لمواقع JWPlayer/Video.js — Chromium لا يحتسب نقرة JS محاكاة كنقرة حقيقية لـautoplay | كشف مشغّلات عام بالخاصية (لا بالدومين) + كتم صوت أثناء التحضير بالإخفاء + رفض ادّعاء "جاهز" بدون دليل تشغيل حقيقي | `4b7cda6` |
| 7 | `_normalizeCandidate` يضيف `#` زائدة لكل رابط مصدر (حتى بلا fragment أصلاً) — يفسد مطابقة سجل المرشحين/منع التكرار | `uri.replace(fragment:'')` ↔ `uri.removeFragment()` (مؤكَّد باختبار فعلي على SDK 3.27.0) | `1387fc1` |
| 8 | فشل متكرر `ExoPlaybackException: Source error` لمصادر HLS حقيقية تعمل بنجاح داخل WebView (مؤكَّد بسجلَين حقيقيَين — grzcdn.com) — السبب: رابط المرشّح يصل لمرحلة التشغيل الأصلي أحياناً بـ`/` إضافية لم تكن موجودة وقت تسجيله، فيفشل بحث `_webCandidateRegistry` ويسقط `formatHintOverride` لـ`null`، فيحاول ExoPlayer تخمين نوع الملف من امتداد الرابط ويفشل لأنه لا ينتهي بـ`.m3u8` حرفياً | تمرير تلميح HLS صريح كلما كان `strongHls` (نمط الرابط، مثل مقطع `/hls/`) يثق بالمصدر أصلاً — كان محسوباً مسبقاً بنفس الدالة ولم يُستخدم هنا | `dfcf47f` |
| 9 | زر وضع العرض محدود بـ3 خيارات فقط — لا يكفي كل نِسب الشاشات | إضافة `fitWidth`/`fitHeight` (5 خيارات الآن) | `de0aaa4` |
| 10 | `didChangeAppLifecycleState` يتجاهل تشغيل WebView تماماً (شائع جداً — كل مواقع JWPlayer/Video.js المعروفة) — عند تصغير التطبيق يستمر صوت/فيديو الصفحة وتنقّلها الإعلاني بالخلفية بصمت | إيقاف/استئناف عناصر `<video>/<audio>` بالـWebView بنفس منطق المشغّل الأصلي | `de0aaa4` |
| 11 | تخزين مؤقت (buffering) بلا تقدّم أثناء المشاهدة الفعلية قد يستمر للأبد بدون أي مخرج للمستخدم غير الخروج يدوياً | مراقب: محاولة إنعاش (seekTo) بعد 20 ثانية، وإذا فشلت الانتقال لشاشة الخطأ الموجودة (بزر إعادة المحاولة) بعد 20 ثانية إضافية | `de0aaa4` |
