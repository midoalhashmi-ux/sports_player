# إصلاح مصدر Web / SPA (حالة Rotana) — README التغييرات

## سبب المشكلة الفعلي

`ChannelSourceResolver` (الذي يقرأ `channels/{id}` من Firestore، ويتعرّف
بشكل صحيح على `streamType == 'web'` ويعيد الرابط الكامل ليُفتح في WebView)
كان **موجوداً لكن غير مستخدَم إطلاقاً**. دالة `_startSession()` في
`watch_screen.dart` كانت تتجاهله تماماً، وتتعامل مع `channelId` كسلسلة نصية
تُلصق مباشرة بعد `https://def.ycnapi.com/` ثم تمرَّر إلى محرك حل روابط HTTP
عام (`_resolveChannelUrl`) لا علاقة له بإعدادات لوحة التحكم.

لذلك عندما كانت لوحة التحكم تحفظ:

```
streamType = web
sourceUrl  = https://rotana.net/ar/channels?tz=480/channels#/live/rotana-comedy
```

كانت هذه القيم **لا تُقرأ أبداً**، وبدلاً منها كان النظام يحاول حلّ رابط HTTP
مبني عشوائياً، فيفشل التحليل التقليدي على `#/live/rotana-comedy` (لأن الجزء
بعد `#` لا يُرسَل إلى السيرفر أصلاً في أي طلب HTTP)، فيظهر "تعذر حل رابط
البث" — ليس بسبب Rotana تحديداً، بل بسبب أن المسار الصحيح لم يكن يُستدعى.

كانت هناك أيضاً محاولة إصلاح سابقة تفحص `rotana.net` بالاسم صراحة داخل
`_resolveChannelUrl` — وهذا بالضبط النوع من الحل الذي طُلب تجنبه (Rotana
كحالة اختبار وليس استثناءً بالاسم).

## الإصلاح

1. **ربط `ChannelSourceResolver` فعلياً** في `_startSession()`: أي قناة تُفتح
   عبر `channelId` تمر أولاً على المُحلّل المرتبط بلوحة التحكم/Firestore.
   عندما تكون `streamType = web`، تذهب القناة إلى WebView بالرابط الكامل
   كما هو (بما فيه أي `#hash`)، **دون أي محاولة حل HTTP على الإطلاق** —
   تماماً كما صُمم `ChannelSourceResolver` أصلاً.
   المسار القديم (`def.ycnapi.com` + `_resolveChannelUrl`) بقي كـ fallback
   فقط لأي حالة يتعذر فيها الوصول إلى Firestore، فلا ينكسر أي شيء كان يعمل
   سابقاً بهذا المسار.

2. **تعميم اكتشاف SPA/Hash Route** داخل `_resolveChannelUrl` (المسار
   الاحتياطي): أُزيل الفحص الخاص باسم `rotana.net` والكلمات المفتاحية
   الضيّقة (`/live/`, `/watch/`, `/channel/`)، واستُبدل بقاعدة عامة واحدة:
   *أي رابط يحمل `#fragment` غير فارغ يُعامَل كصفحة ويب تُفتح كاملة في
   WebView* — لأن هذا الجزء من الرابط لا يمكن لأي خادم استلامه عبر HTTP
   بغض النظر عن الموقع. هذا يجعل Rotana مجرد حالة تنجح لأن القاعدة عامة،
   وليس استثناءً بالاسم.

3. **تفعيل Referer/User-Agent من لوحة التحكم** (`channels.sourceHeaders`):
   كان الحقل موجوداً في لوحة التحكم (AHMED-dashboard) ويُحفظ في Firestore،
   لكن `sports_player` لم يكن يقرأه إطلاقاً. أُضيف حقل `headers` اختياري
   إلى `StreamSession` (افتراضيّاً فارغ، متوافق مع كل الاستدعاءات القديمة)،
   وصار `ChannelSourceResolver` يقرأ `sourceHeaders.referer` و
   `sourceHeaders['user-agent']` عند وجودهما ويمرّرهما، فيصلا إلى WebView
   والمشغل الأصلي عبر `_effectiveStreamHeaders()` الموجودة أصلاً. تركهما
   فارغين (كحال Rotana حالياً) لا يُسبب أي فشل — يُستخدَم عندها سلوك
   WebView/الشبكة الافتراضي تماماً كما كان.

## الملفات المعدَّلة

- `lib/screens/watch_screen.dart`
- `lib/services/channel_source_resolver.dart`
- `lib/services/stream_models.dart`

لم يُحذف أو يُعَد بناء أي جزء آخر من `sports_player`. كل محركات الاكتشاف
الموجودة سلفاً (Player Framework Intelligence لـ JW/Video.js، اكتشاف
DRM عبر `requestMediaKeySystemAccess`، Candidate Manager/State Machine،
API Resolver المحدود العمق، معالجة إعادة التوجيه 3xx، تحقق MP4 عبر
HEAD/Range GET) كانت مطبَّقة بالفعل في نسخة المشروع المرفوعة ولم تُمَس.

## القيود

- هذا الإصلاح لا يتجاوز DRM ولا يفكّ تشفيراً ولا يتحايل على أي حماية وصول،
  تماشياً مع القواعد المذكورة في `vidosorce.md` و`README-legendary-source-engine.md`.
- إذا كانت صفحة Rotana نفسها تتطلب تفاعلاً (ضغط زر تشغيل) أو تستخدم DRM،
  فسيبقى التشغيل داخل WebView (هذا هو السلوك الصحيح المطلوب أصلاً)، وليس
  عبر المشغل الأصلي.
- لم يُنفَّذ فحص تلقائي كامل عبر Codemagic (بيئة التنفيذ هنا لا تملك Flutter
  SDK)، لذا يُنصح ببناء تجريبي واحد على Codemagic قبل النشر النهائي.

## خطوات الاختبار

1. **Rotana (SPA/Web):** اضبط في لوحة التحكم لقناة تجريبية
   `Source Type = WEB` والرابط
   `https://rotana.net/ar/channels?tz=480/channels#/live/rotana-comedy` مع
   ترك Referer وUser-Agent فارغين. افتح القناة من التطبيق — يجب أن تُفتح
   WebView مباشرة بالرابط الكامل (بدون فقدان `#/live/...`) ولا تظهر رسالة
   "تعذر حل رابط البث".
2. **MP4 مباشر:** اضبط قناة أخرى برابط MP4 مباشر واختبر أنه يُكتشف ويُشغَّل
   عبر المشغل الأصلي (أو WebView كـ fallback إذا فشل HEAD/Range GET).
3. **HLS مع إعادة توجيه 302:** رابط m3u8 يمر عبر إعادة توجيه — يجب أن يتبع
   النظام التحويل تلقائياً ويصل للرابط النهائي.
4. **API (`def.ycnapi.com/api/channel/4`):** تأكد أن الاستجابة غير القابلة
   للفك (binary) لا تُسبب تعطلاً (crash)، وأن النظام لا يحاول فك تشفير غير
   معروف.
5. **Referer/User-Agent فارغين:** تأكد أن أي قناة (Web أو HLS) بدون Referer/
   User-Agent محددَين تعمل بلا مشاكل مرتبطة بهما تحديداً.
6. **fallback إلى WebView:** لأي قناة HLS يفشل فيها المشغل الأصلي، تأكد من
   عودة النظام إلى WebView دون تكرار لا نهائي.
