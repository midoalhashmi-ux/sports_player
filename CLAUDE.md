# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## قبل أي تعديل على `watch_screen.dart`/`watch_screen_discovery.dart`

استخدم مهارة `stream-debug` (`.claude/skills/stream-debug/`) — فيها منهجية
التشخيص الوحيدة اللي أثبتت نجاحها بهذا المشروع (سجل تشخيص حقيقي مصدَّر من
التطبيق، لا تخمين من الكود). تحتوي أيضاً على مرجع آلة الحالة الكاملة
(`references/state-machine.md`) وأمثلة حقيقية لأخطاء سابقة
(`references/known-bugs.md`) — اقرأها قبل إعادة اكتشاف نفس المعمارية من
الصفر. **لا تشخّص أي مشكلة تشغيل بدون طلب سجل `sports_player_debug_log.txt`
مُصدَّر من التطبيق أولاً** — تخمينات بلا سجل ضاعت جهداً حقيقياً بتاريخ هذا
المشروع (راجع فكرة #2 المرفوضة بـ`افكار_مهمة.md`).

## قواعد حماية صارمة — اقرأها قبل أي تعديل

`project-protection-rules.md` يسرد ملفات/إعدادات ممنوع تعديلها بدون إذن
صريح من المستخدم: `lib/main.dart`, `lib/firebase_options.dart`,
`android/app/google-services.json`, `android/build.gradle` (الجذري
وبمجلد `app/` تحديداً `applicationId`/`minSdkVersion`/`targetSdkVersion`/
`compileSdkVersion`/`signingConfigs`), `codemagic.yaml`, ملفات التوقيع، أي
ترقية لحزمة **موجودة أصلاً** بـ`pubspec.yaml`، وأسماء حقول/مجموعات
Firestore المشتركة مع BinSheikh وAHMED-dashboard. أي تعديل يمس هذي
المناطق: توقف واشرح للمستخدم ولا تفترض الموافقة.

**قيد أمان ثابت (Auto Source Engine V3)**: يُقبل فقط روابط وسائط عامة
تعرضها الصفحة نفسها. اكتشاف DRM يفرض وضع WebView-فقط دائماً — لا استخراج
أو تجاوز لأي مفتاح تشفير أو محتوى مشفَّر مطلقاً.

## أوامر التطوير

```bash
flutter pub get                 # تثبيت التبعيات
flutter analyze                 # فحص ثابت — دائماً بعد أي تعديل على watch_screen*.dart
flutter test                    # كل الاختبارات
flutter test test/candidate_scoring_test.dart   # اختبار واحد
flutter test test/player_strategy_test.dart
```

للبناء الفعلي (APK محلي على جهاز المستخدم، Windows) راجع القسم الكامل
أسفل هذا الملف — فيه مسارات وإصدارات أدوات محدَّدة لجهاز بعينه، ضرورية
لتجنّب إعادة تشخيص نفس أخطاء البناء من الصفر.

## البنية المعمارية

هذا المستودع جزء من منظومة 3 مستودعات منفصلة تتشارك نفس مشروع Firebase
(`sports-stream-app-36a7a`) ونفس Cloudflare Worker
(`binsheikh-api.binsheikh.workers.dev`، كوده بمستودع BinSheikh
`cloudflare-worker/`):

- **BinSheikh** — تطبيق تصفّح المحتوى (الأقسام/القنوات/الأفلام/المسلسلات/
  الأنمي). لا يلمس روابط البث مباشرة — يفتح هذا التطبيق عبر `app_links`
  بمعرّف قناة/حلقة فقط.
- **sports_player** (هذا المستودع) — تطبيق منفصل وظيفته الوحيدة تشغيل
  الفيديو. فصله يتيح تحديثه بـPlay Store دون المساس بـBinSheikh، ويعزل
  منطق حل الروابط الحقيقية/تجاوز الحماية عن تطبيق المحتوى العام.
- **AHMED-dashboard** — لوحة تحكم HTML/JS خام يديرها فريق المحتوى.

روابط m3u8 الحقيقية **لا تُخزَّن ولا تُقرأ من Firestore مباشرة من هذا
التطبيق** — تُجلب فقط عبر `POST /getStreamUrl` بالووركر (يقرأ
`privateStreams` بصلاحيات خادم لا تصل لأي عميل).

### `lib/screens/watch_screen.dart` + `watch_screen_discovery.dart` — المحرّك الرئيسي

الشاشة الأكبر والأهم (~5700 سطر مجتمعتين) — آلة حالة كاملة لتشغيل
الفيديو: تجربة سيرفرات/جودات متعددة، تبديل بين تشغيل native (ExoPlayer عبر
`video_player`) وWebView، اكتشاف تلقائي لمصدر الفيديو من صفحة ويب بتتبّع
طلبات شبكة داخل WebView، وتسجيل أحداث تشخيصية (`_slog` →
`SessionLogService`) لكل خطوة. **متغيّرا حالة منفصلان لا يجب الخلط
بينهما**: `_LoadState` (`loading`/`error`/`ready`، يتحكم بما يُعرض
فعلياً) و`_WebSessionState` (أين وصلت خط أنابيب اكتشاف الويب، له 13 قيمة —
`nativePlaying` قيمة نهائية حارسة: بمجرد نجاح ExoPlayer، أي منطق لاحق
بدورة حياة WebView يجب يتحقق منها أولاً قبل أي تحديث حالة). التفاصيل
الكاملة بـ`.claude/skills/stream-debug/references/state-machine.md`.

### طبقة عزل استراتيجيات المشغّل (`lib/services/player_strategies/`)

`PlayerStrategy` مجرَّدة + تحتها `GenericPlayerStrategy`/
`VideoJsPlayerStrategy`/`JwPlayerStrategy` — كل نوع مشغّل ويب معروف
(video.js، JWPlayer/vidmoly) له منطق تقييم/استبعاد مرشّحين معزول فيزيائياً
عن الأنواع الأخرى، بدل صيغة تقييم مشتركة واحدة (`candidate_scoring.dart`)
كان إصلاح خاص بموقع/مشغّل معيّن فيها يقدر يكسر مواقع أخرى بالخطأ (نمط
تكرر 3 مرات فعلياً — راجع سجل #39/#40/#41 بـ`TECHNICAL.md`).
`PlayerStrategyRegistry.select()` يختار حسب أعلام الاكتشاف الموجودة أصلاً.

### خدمات أخرى مهمة بـ`lib/services/`

- `stream_auth_service.dart` — يطلب جلسة بث من الووركر، يدعم شكل استجابة
  متعدد السيرفرات/الجودات وشكل قديم مبسّط للتوافق الرجعي.
- `channel_source_resolver.dart` / `api_source_resolver.dart` — حل مصدر
  القناة (رابط مباشر مخزَّن أو مصدر API ديناميكي).
- `candidate_scoring.dart` — الصيغة المشتركة الأساسية لتقييم/استبعاد
  مرشّحي الفيديو المكتشَفين (`isNonMediaAsset` هو الاستبعاد الوحيد
  الموثوق — لا تعتمد على النقاط النهائية وحدها، راجع الملاحظة بآخر
  `TECHNICAL.md`).
- `hls_cache_proxy.dart` — وكيل HLS محلي بحد أقصى 3 اتصالات متزامنة (يمنع
  خوادم CDN المحمية من قطع الاتصال بسبب قصف طلبات متزامن) — **حسّاس
  جداً لأي تعديل**، راجع تحذيرات آخر `TECHNICAL.md` قبل لمسه (تراجع كامل
  مرة سابقاً بسبب تعليق تشغيل غير مختبَر).
- `session_log_service.dart` — يجمع سجل تشخيص نصي زمني قابل للتصدير، أساس
  كل تشخيص عن بعد بدون وصول فعلي لجهاز المستخدم.

### مراجع أعمق

- `TECHNICAL.md` — سجل مشاكل/حلول تراكمي (45+ حالة حقيقية موثّقة سطراً
  بسطر) + نظرة عامة على المنظومة الثلاثية. أضف صفاً جديداً هنا لأي إصلاح
  جوهري لاحق، ولا تُعِد تشخيص مشكلة موثّقة هنا من الصفر.
- `افكار_مهمة.md` — أفكار معمارية نوقشت بعمق لتحسين الاستقرار/السرعة
  (منفَّذ بعضها، والبعض مرفوض تقنياً مع سبب التحقّق الفعلي).

---

# دليل البناء المحلي (Windows) — sports_player

> اقرأ هذا قبل أي طلب بناء APK لهذا المشروع. كل سطر هنا خرج من مشكلة
> حقيقية واجهها المستخدم فعلياً على جهازه (وليس تخميناً) — راجع
> `TECHNICAL.md` (سجل #20 إلى #23) للتفاصيل الكاملة لكل إصلاح.

## بيئة جهاز المستخدم (Windows، حساب DELL)

- المستودع مستنسخ بمسار: `C:\Users\DELL\Downloads\sports_player`
- **Flutter الحقيقي المستخدم للبناء الفعلي** (مضبوط داخل Android Studio،
  مختلف عن أي `flutter` بـ PATH بالـ PowerShell العادي):
  ```
  C:\Users\DELL\Desktop\flutter\flutter\bin\flutter.bat
  ```
  إصداره: **Flutter 3.47.2 / Dart 3.13.2** (تأكَّد بـ`flutter.bat --version`
  فعلياً، لا تفترض رقماً آخر). **استخدم هذا المسار الكامل دائماً** بأي أمر
  بناء بدل الاعتماد على أمر `flutter` المجرّد — قد يشير لنسخة مختلفة
  تماماً بنفس الجهاز وتسبب نتائج غير متوقعة (حصل فعلياً).
- **جافا**: يحتاج **JDK 17** تحديداً (Gradle 8.14 بهذا المشروع لا يدعم
  جافا 25 التي تأتي مدمجة أحياناً مع Android Studio نفسه، ولا جافا 8
  القديمة التي قد يشير لها `JAVA_HOME` بالنظام). المثبَّت على هذا الجهاز:
  ```
  C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot
  ```
  يجب ضبط **كلا الأمرين** التاليين (أحدهما فقط لا يكفي — Kotlin daemon
  يتجاهل إعداد Flutter ويستخدم `JAVA_HOME` مباشرة):
  ```powershell
  flutter config --jdk-dir="C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot"
  [System.Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot', 'User')
  ```
  (بعد `SetEnvironmentVariable` لازم تُغلق نافذة PowerShell وتُفتح واحدة
  جديدة — التغيير لا ينعكس بنفس النافذة).

## أمر البناء الصحيح (بعد كل التعديلات المذكورة أدناه)

```powershell
cd C:\Users\DELL\Downloads\sports_player
git pull
C:\Users\DELL\Desktop\flutter\flutter\bin\flutter.bat build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

الناتج (3 ملفات صغيرة منفصلة بدل ملف واحد ضخم):
```
build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk   ← أجهزة قديمة 32-bit
build\app\outputs\flutter-apk\app-arm64-v8a-release.apk     ← ثبّت هذا على الهاتف (أغلب الأجهزة الحديثة)
build\app\outputs\flutter-apk\app-x86_64-release.apk        ← محاكيات فقط، تجاهله
```

لا تستخدم `--split-per-abi` بدون `--target-platform android-arm,android-arm64`
معه — بدونه Gradle يحاول أيضاً بناء `x86_64` وقد يتعارض مع إعدادات أخرى.

## مشكلة متكررة: `git pull` يفشل ويرفض التحديث

أدوات Flutter/Android Studio تُعدِّل هذي الملفات محلياً تلقائياً بعد أي
`pub get`/`build` (بدون أي تدخل من المستخدم): `pubspec.lock`,
`analysis_options.yaml`, `android/app/build.gradle`,
`android/gradle.properties`, وأحياناً ملفات `android/gradlew*`/
`android/.kotlin/` تظهر كـ"Untracked". هذا يمنع `git pull` برسالة
"Your local changes... would be overwritten by merge". **الحل دائماً**:
تأكد أولاً (`git diff <الملف>`) أن التغيير المحلي تلقائي/تافه (عادة نعم،
راجع الأمثلة الفعلية بـTECHNICAL.md #20-23)، ثم:
```powershell
git checkout -- <الملف الأول> <الملف الثاني> ...
git pull
```
لا تستخدم `git reset --hard`/`git clean` بشكل عام — فقط الملفات المحدَّدة
المذكورة برسالة الخطأ نفسها.

## أخطاء بناء حقيقية سبق حلّها — لا تُعِد تشخيصها من الصفر

| الخطأ (نص مطابق تقريباً) | السبب | الحل المطبَّق فعلاً |
|---|---|---|
| `Compilation error` بمهمة `:image_gallery_saver_plus:compileReleaseKotlin` | إصدار 3.0.5 غير متوافق مع Kotlin/Gradle حديثين | `pubspec.yaml`: `image_gallery_saver_plus: ^4.0.1` |
| `does not have a primitive operator '=='` بملف `google_fonts_variant.dart` | إصدار 6.3.0 فيه خطأ Dart compile حقيقي بكودها | `pubspec.yaml`: `google_fonts: ^8.2.1` |
| `SigningConfig "release" is missing required property "storeFile"` عند `:app:packageRelease` | `signingConfigs.release` بـ`build.gradle` يُملأ فقط لما `CI=true` (Codemagic فقط) | `signingConfig System.getenv()["CI"] ? signingConfigs.release : signingConfigs.debug` — بناء محلي يوقَّع بمفتاح debug (كافٍ للتجربة، لا يصلح لرفعه على Play Console) |
| `Conflicting configuration ... in ndk abiFilters ... cannot be present when splits abi filters are set` | `ndk.abiFilters` اليدوي بـ`build.gradle` يتعارض مع `--split-per-abi` | أُزيل `ndk.abiFilters`، استُبدل بـ`--target-platform android-arm,android-arm64` على سطر الأوامر (و`codemagic.yaml`) |
| MIUI/HyperOS: "لا يتوافق هذا التطبيق مع أحدث إصدار من أندرويد" عند التثبيت — استمرت حتى بعد حذف التطبيق بالكامل وإعادة التثبيت | مفتاح debug العشوائي (يختلف بين كل تثبيت Flutter) — ليس تعارض توقيع مع نسخة قديمة كما افتُرض أولاً | كيستور محلي حقيقي ثابت اختياري (`android/key.properties`، راجع القسم أدناه) بدل الاعتماد على debug |

كل هذي الإصلاحات مدفوعة فعلياً لفرع `claude/greeting-a1f5q5` — تأكد أن
`git log --oneline -1` يطابق أو يتقدّم على `e48cdb7` قبل ما تشخّص أي خطأ
من هذي القائمة من جديد.

## كيستور محلي حقيقي (يحل تحذير MIUI "غير متوافق" نهائياً)

لمرة واحدة فقط، من مجلد `android/`:
```powershell
cd C:\Users\DELL\Downloads\sports_player\android
keytool -genkeypair -v -keystore local-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias localrelease -storepass "اختر-كلمة-مرور" -keypass "نفس-كلمة-المرور" -dname "CN=Local Dev, OU=Dev, O=BinSheikh, L=City, S=State, C=SA"
copy key.properties.example key.properties
notepad key.properties
```
بـ`key.properties` غيّر `CHANGE_ME` بنفس كلمة المرور المستخدَمة بأمر
`keytool` أعلاه (بكلا الحقلين `storePassword`/`keyPassword`)، واحفظ.
بعدها أي `flutter build apk --release` محلي يوقَّع تلقائياً بهذا الكيستور
الثابت بدل debug العشوائي — لا حاجة لتكرار هذا مرة أخرى، الملف يبقى على
الجهاز (لا يُرفع لـ GitHub عمداً، `.gitignore`).

## ⚠️ التطبيق منشور فعلياً على Google Play Console

- أي بناء محلي (موقَّع بمفتاح debug) **لا يصلح للرفع على Play Console
  إطلاقاً** — للتجربة الشخصية فقط.
- بناء Codemagic الحقيقي (`CI=true`, يقرأ الكيستور الحقيقي من
  `android_signing: sports_player_release`) هو الوحيد الصالح للنشر.
- **لا تغيّر `compileSdk`/`targetSdk`/`minSdk` بـ`build.gradle`**، ولا رقم
  الإصدار (`version:` بـ`pubspec.yaml`) بدون طلب صريح من المستخدم —
  يؤثر مباشرة على التوافق مع سياسات Play الحالية والتحديثات المستقبلية.
- رفع تحديث حقيقي لـPlay Console يحتاج رفع `version:` بـ`pubspec.yaml`
  يدوياً أولاً (هذا مسؤولية المستخدم، مو جزءاً من إصلاحات البناء).

## قناة بديلة أسرع لتثبيت بدون تحذير Play Protect

بما إن التطبيق على Play Console، أفضل طريقة تثبيت **بدون** تحذير أندرويد
القياسي ("لم يتم فحص هذا التطبيق") هي رفع البناء لقناة **الاختبار
الداخلي (Internal Testing)** بلوحة Play Console بدل تثبيت APK مباشرة —
هذا تثبيت متجر Play حقيقي فلا يظهر أي تحذير إطلاقاً.
