# الخادم الخلفي (Cloudflare Workers) — بديل Firebase Cloud Functions

هذا المجلد يقوم بنفس عمل Firebase Cloud Functions تماماً (حماية رابط البث +
مزامنة مباريات API-Football) لكن بدون الحاجة لخطة Blaze ولا حساب فوترة
سعودي عبر CNTXT. التسجيل في Cloudflare مجاني بإيميل فقط، ولا يطلب بطاقة
بنكية لخطة العمّال (Workers) المجانية.

اتبع الخطوات بالترتيب من كمبيوتر (مو الجوال).

## 1) إنشاء حساب خدمة Google (يعطي صلاحية الكتابة في Firestore)

هذه الخطوة **لا تحتاج خطة Blaze إطلاقاً** — إنشاء حسابات خدمة متاح مجاناً
على أي مشروع Firebase.

1. افتح https://console.cloud.google.com/iam-admin/serviceaccounts
2. تأكد إن المشروع المختار بالأعلى هو **sports-stream-app-36a7a**
3. اضغط **+ Create Service Account**
4. اسم مثل `worker-firestore-access` → Continue
5. في خطوة الصلاحيات (Grant this service account access)، اختر دور:
   **Cloud Datastore User** (ابحث عنه بالمربع) → Continue → Done
6. من قائمة حسابات الخدمة، اضغط على الحساب اللي أنشأته
7. تبويب **Keys** → **Add Key** → **Create new key** → نوع **JSON** → Create
8. بينزل ملف JSON على جهازك — احتفظ فيه، بتحتاج قيمتين منه بالخطوة 4.

## 2) إنشاء حساب Cloudflare (مجاني)

1. افتح https://dash.cloudflare.com/sign-up
2. سجّل بإيميلك — بدون أي بطاقة بنكية
3. بعد الدخول، لاحظ **اسمك الفرعي (subdomain)** — تحت "Workers & Pages"
   بيطلب منك تختار اسم فرعي فريد أول مرة (مثلاً `binsheikh`) —
   اختره الآن لأنك بتحتاجه لاحقاً بعنوان الـ Worker.

## 3) تثبيت أدوات النشر محلياً

في الطرفية (Terminal):

```
npm install -g wrangler
```

ثم سجّل دخول (بيفتح متصفح):

```
wrangler login
```

اضغط "Allow" في الصفحة اللي تفتح.

## 4) ضبط الأسرار الأربعة

انتقل لهذا المجلد بالتحديد (بعد فك ضغط الملف اللي استلمته):

```
cd cloudflare-worker
```

نفّذ الأوامر التالية **واحداً تلو الآخر**، وبعد كل أمر بيطلب منك تلصق
القيمة وتضغط Enter:

```
wrangler secret put API_FOOTBALL_KEY
```
الصق مفتاح API-Football (نفسه اللي أخذته من dashboard.api-football.com).

```
wrangler secret put GCP_SERVICE_ACCOUNT_EMAIL
```
افتح ملف JSON من الخطوة 1، وانسخ قيمة الحقل `"client_email"` بالضبط
(يشبه: `worker-firestore-access@sports-stream-app-36a7a.iam.gserviceaccount.com`).

```
wrangler secret put GCP_SERVICE_ACCOUNT_PRIVATE_KEY
```
افتح نفس ملف JSON، وانسخ قيمة الحقل `"private_key"` **كاملة بالضبط**
(تبدأ بـ `-----BEGIN PRIVATE KEY-----` وتنتهي بـ `-----END PRIVATE KEY-----`،
وتحتوي على عدة أسطر). الصقها كاملة كما هي.

```
wrangler secret put ADMIN_SYNC_SECRET
```
اخترع أنت كلمة سر عشوائية طويلة (مثلاً 20 حرف/رقم عشوائي) — هذي تحمي زر
"مزامنة الآن" بلوحة التحكم من أي استخدام غير مصرح. احفظها، بتحتاجها
بالخطوة 6.

## 5) النشر

```
wrangler deploy
```

بعد النشر بيطبع لك رابط شبيه بـ:
```
https://binsheikh-api.<اسمك-الفرعي>.workers.dev
```
انسخ هذا الرابط بالضبط.

## 6) تحديث الرابط والسر في المشروعين

**أ) تطبيق المشغل (sports_player):**
افتح `lib/services/worker_config.dart`، واستبدل:
```dart
const String kWorkerBaseUrl = 'https://binsheikh-api.YOUR-SUBDOMAIN.workers.dev';
```
بالرابط الحقيقي من الخطوة 5. احفظ، وأعد بناء التطبيق عبر Codemagic.

**ب) لوحة التحكم (admin-dashboard/app.js):**
افتح `admin-dashboard/app.js`، ولاحظ بالقريب من الأعلى:
```js
const WORKER_BASE_URL = 'https://binsheikh-api.YOUR-SUBDOMAIN.workers.dev';
const ADMIN_SYNC_SECRET = 'REPLACE-WITH-YOUR-OWN-SECRET';
```
استبدل القيمة الأولى بنفس رابط الخطوة 5، والثانية بنفس كلمة السر اللي
اخترتها بأمر `ADMIN_SYNC_SECRET` بالخطوة 4. احفظ وارفع ملفات لوحة التحكم
لنفس مكان استضافتها الحالي (Firebase Hosting أو غيره).

## 7) التحقق

- افتح لوحة التحكم → تبويب "المباريات" → اضغط "مزامنة الآن" — المفروض
  يرجع لك عدد مباريات بدون خطأ.
- افتح تطبيق المشغل وجرّب تشغيل أي قناة محمية — المفروض يشتغل البث عادي.

## ملاحظات

- المزامنة التلقائية كل ساعة تعمل من نفسها بمجرد النشر (مضبوطة بملف
  `wrangler.toml`) — لا تحتاج تسويها يدوياً.
- الخطة المجانية لـ Cloudflare Workers تسمح بـ 100,000 طلب/يوم — أكثر من
  كافية لمشروعك بمراحل بعيدة.
- لو احتجت تغيّر أي سرّ لاحقاً (مثلاً غيّرت مفتاح API-Football)، أعد نفس
  أمر `wrangler secret put <الاسم>` وألصق القيمة الجديدة، بدون حاجة لإعادة
  نشر باقي الكود.
