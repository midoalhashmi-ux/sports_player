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

كل هذي الإصلاحات مدفوعة فعلياً لفرع `claude/greeting-a1f5q5` — تأكد أن
`git log --oneline -1` يطابق أو يتقدّم على `e48cdb7` قبل ما تشخّص أي خطأ
من هذي القائمة من جديد.

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
