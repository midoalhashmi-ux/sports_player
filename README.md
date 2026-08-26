# sports_player — تطبيق المشغل المنفصل

تطبيق Flutter مستقل تماماً عن تطبيق المحتوى (sports_stream_app). مهمته الوحيدة:

1. استقبال رابط داخلي (Deep Link/Intent) من تطبيق المحتوى يحمل `channelId`.
2. طلب رابط بث موقّت من Cloud Function باسم `getStreamUrl` (**مبنية وشغالة** في مشروع التطبيق الرئيسي).
3. تشغيل رابط HLS (m3u8) المؤقت عبر `video_player`.

راجع ملف `README.md` الرئيسي لمشروع **sports_stream_app** لخارطة الطريق الكاملة والقرارات المتفق عليها — هذا الملف مرجع مختصر لهذا التطبيق فقط.

## قاعدة تسليم الملفات (إلزامية لأي نموذج يعمل هنا)
عند تنفيذ أي تعديل، قدّم الملفات الجديدة/المعدّلة كأرشيف **ZIP قابل للتحميل
مباشرة** بمساراتها الصحيحة داخل الأرشيف — وليس أكواد نصية داخل الرد. سمِّ
الأرشيف اسماً واضحاً يدل على الميزة/المرحلة. هذي القاعدة تنطبق على مستودعات
المشروع الثلاثة كلها (sports_player، CLOUDAPP2026، AHMED-dashboard).

## الحالة الحالية
- ✅ استقبال Deep Link (`app_links`) وتمرير `channelId`
- ✅ شاشة تشغيل بحالات: تحميل / خطأ + إعادة محاولة / تشغيل HLS
- ✅ `ChannelSourceResolver`: يقرأ حالة القناة، ويستخدم رابط مباشر للقنوات غير المحمية أو يمر عبر Cloud Function للمحمية
- ✅ Cloud Function `getStreamUrl` موجودة وتعمل (في مشروع sports_stream_app)
- ✅ تطبيق المحتوى يستدعي المشغل عبر Intent صريح باسم الحزمة (وليس فقط رابط داخلي عام) — راجع قسم "عقد الربط" في README الرئيسي
- ✅ تطبيق Android مسجّل في Firebase باسم `com.midoalhashmi.zoltrastream`، و`firebase_options.dart` محدّث بالقيم الحقيقية (2026-08-25)
- ⚠️ باقي فقط: بصمة SHA-1 لمفتاح التوقيع الفعلي (مطلوبة قبل النشر النهائي على Google Play — راجع القسم أدناه)

## اسم حزمة أندرويد (Application ID)
`com.midoalhashmi.zoltrastream`

تم اختياره لأنه اسم غير مستخدم في أي تطبيق آخر على Google Play (تم التحقق وقت الاختيار)، بما إن هذا التطبيق فقط هو من سيُرفع للمتجر. الاسم مضبوط بالفعل في:
- `android/app/build.gradle` (`namespace` و`applicationId`)
- `android/app/src/main/kotlin/com/midoalhashmi/zoltrastream/MainActivity.kt`

لو قررت اسماً مختلفاً لاحقاً، **قبل أول رفع فعلي للمتجر**، غيّره في هذين المكانين فقط (اسم الحزمة لا يمكن تغييره بعد أول نشر على Play دون اعتباره تطبيقاً جديداً بالكامل).

## ✅ تسجيل Firebase — مكتمل
تم تسجيل تطبيق Android جديد في Firebase Console باسم الحزمة `com.midoalhashmi.zoltrastream` بتاريخ 2026-08-25، وتحديث `lib/firebase_options.dart` بالقيم الحقيقية (`appId`, `apiKey`). نسخة `google-services.json` محفوظة في `android/app/` كمرجع فقط (غير مستخدمة عبر Gradle plugin، المشروع يعتمد على `firebase_options.dart` مباشرة مثل تطبيق المحتوى).

**باقي قبل النشر النهائي على Google Play:** أضف بصمة SHA-1 لمفتاح التوقيع الحقيقي (وليس مفتاح debug) في نفس صفحة التطبيق بـ Firebase Console → Project settings → Your apps → التطبيق بحزمة zoltrastream → Add fingerprint. بدونها بعض خدمات Firebase (مثل استدعاءات Cloud Functions من نسخة موقّعة للنشر) قد لا تعمل بشكل موثوق.

## عقد الربط مع تطبيق المحتوى
- تطبيق المحتوى يحاول أولاً فتح المشغل عبر **Intent صريح** موجّه بالضبط لـ `com.midoalhashmi.zoltrastream` (قراءة من `settings/player.androidPackage` في Firestore — قابلة للتغيير من لوحة التحكم بدون تحديث أي تطبيق).
- إذا فشل (المشغل غير مثبت)، يرجع لمحاولة الرابط الداخلي العام `sportsplayer://play?channelId=...` كخطة بديلة، ثم يعرض رسالة تحميل من المتجر إن فشل الاثنان.
- هذا يضمن فتح تطبيقك أنت تحديداً بدون تعارض مع أي تطبيق آخر مسجّل لنفس الـ scheme.

## خطوة يدوية متبقية
انسخ أيقونة التطبيق إلى:
`android/app/src/main/res/mipmap/ic_launcher.png`
(ملف صورة ثنائي لم يُدرج هنا تلقائياً — انسخها من مستودع تطبيق المحتوى أو استخدم أيقونة خاصة بالمشغل.)
