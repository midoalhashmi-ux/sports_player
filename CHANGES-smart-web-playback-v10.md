# V10 — Universal Player Intelligence

## الهدف

ترقية محرك Web Playback من الاعتماد على امتدادات `m3u8/mp4/mpd` إلى اكتشاف **طريقة تشغيل المحتوى** نفسها، مع دعم صفحات تحتوي على iframe يظهر أو يتغير بعد الضغط على Play.

## ما تم تغييره

- مراقبة إنشاء وتغيير عناصر `iframe` ديناميكياً عبر `MutationObserver` مع تصنيف عام لا يعتمد على اسم مزود محدد.
- اكتشاف iframe المحتمل أن يكون مشغل فيديو بناءً على الحجم، الظهور، خصائص اللاعب، وكلمات عامة مثل `embed/player/video/watch/stream`، مع استبعاد نطاقات الإعلانات المعروفة.
- إضافة **Iframe Promotion**: عند اكتشاف iframe قوي، يتم تحميل وثيقة iframe نفسها في WebView الرئيسي حتى يصبح سياق اللاعب قابلاً للمراقبة بدلاً من محاولة تجاوز Same-Origin Policy.
- الحفاظ على `Referer` للصفحة الأصلية عند ترقية iframe قدر الإمكان، مع الاستفادة من جلسة/كوكيز WebView الموجودة.
- إضافة مهلة رجوع آمنة للصفحة الأصلية إذا فشلت ترقية iframe ولم يظهر دليل تشغيل.
- توسيع دليل التشغيل ليشمل `PerformanceResourceTiming` وموارد الوسائط، وليس فقط `video.currentTime`.
- تصنيف عام للموارد: MP4/M4S/TS/M3U8/MPD/WebM وروابط manifest/stream/video/media/segment/chunk وغيرها، مع استبعاد analytics/ads/telemetry.
- استخدام الموارد المكتشفة كـ **Playback Evidence** وليس كضرورة لاستخراج رابط Native.
- تحسين `Smart Interaction`: بعد الضغط على Play، إذا لم يظهر `video` في الصفحة الأصلية لكن ظهر iframe أو نشاط وسائط، يعتبر ذلك hand-off ناجحاً ويترك المراقبة والترقية تكمل العمل.
- الإبقاء على DRM كما هو: لا يتم تجاوز DRM أو CAPTCHA أو أنظمة المصادقة.
- لم يتم تغيير Firestore أو API resolver أو AdService أو نموذج المصادر الأساسي.

## أمثلة تغطيها المعمارية

1. Sibnet: Player → MP4 + HTTP Range → يمكن تجربة Native.
2. Vidmoly: Player/iframe → Session/API → HLS segments → يمكن إبقاء Web Player إذا لم يكن Native مناسباً.
3. Mega أو لاعب مخصص: API/chunked/encrypted playback → Web Player بدون افتراض وجود MP4/M3U8 مباشر.

## ملاحظة البناء

تمت مراجعة جميع كتل JavaScript المضمنة باستخدام `node --check` بنجاح.
بيئة العمل الحالية لا تحتوي Flutter/Dart SDK، لذلك لم يتم تشغيل `flutter analyze` أو بناء APK/AAB محلياً هنا.
