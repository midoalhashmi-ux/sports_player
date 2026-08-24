# sports_player — تطبيق المشغل المنفصل

هذا تطبيق Flutter مستقل تماماً عن تطبيق المحتوى (sports_stream_app). مهمته الوحيدة:

1. استقبال رابط داخلي (Deep Link) بصيغة `sportsplayer://play?channelId=<id>` من تطبيق المحتوى.
2. طلب رابط بث موقّت من Cloud Function باسم `getStreamUrl` (لم تُبنَ بعد — الخطوة 6 من خارطة طريق المشروع الرئيسي).
3. تشغيل رابط HLS (m3u8) المؤقت عبر `video_player`.

راجع ملف `README.md` الرئيسي لمشروع **sports_stream_app** لخارطة الطريق الكاملة والقرارات المتفق عليها — هذا الملف مرجع مختصر لهذا التطبيق فقط.

## الحالة الحالية
- ✅ استقبال Deep Link (`app_links`) وتمرير `channelId`
- ✅ شاشة تشغيل بحالات: تحميل / خطأ + إعادة محاولة / تشغيل HLS
- ✅ ربط Firebase بنفس مشروع `sports-stream-app-36a7a`
- ❌ Cloud Function `getStreamUrl` غير موجودة بعد — التشغيل الفعلي لن يعمل حتى إنجازها

## اسم حزمة أندرويد (Application ID)
`com.midoalhashmi.sportsplayer2026` — غيّره في `android/app/build.gradle`،
مسار حزمة Kotlin، وملف `AndroidManifest.xml` لو تبي اسم مختلف.

## خطوة يدوية متبقية
انسخ أيقونة التطبيق إلى:
`android/app/src/main/res/mipmap/ic_launcher.png`
(ملف صورة ثنائي لم يُدرج هنا تلقائياً — انسخها من مستودع تطبيق المحتوى أو استخدم أيقونة خاصة بالمشغل.)
