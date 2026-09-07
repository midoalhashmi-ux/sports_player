// ============================================================================
// ⚠️ هذا الملف غير مُستخدَم حالياً — تم الانتقال إلى Cloudflare Workers
// (مجلد /cloudflare-worker) لتفادي اشتراط خطة Blaze وحساب الفوترة السعودي
// عبر CNTXT. الكود هنا محفوظ فقط كمرجع لو رجعت تحتاج Firebase Cloud
// Functions لاحقاً (بعد فتح حساب Blaze عبر CNTXT مثلاً) — لن يعمل أي شيء
// من هذا الملف إلا بعد "firebase deploy --only functions" يدوياً.
// ============================================================================

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

// مفتاح API-Football يُضبط مرة واحدة من سطر الأوامر (لا يوضع هنا كنص
// صريح ولا داخل تطبيق الموبايل إطلاقاً):
//   firebase functions:secrets:set API_FOOTBALL_KEY
const apiFootballKey = defineSecret("API_FOOTBALL_KEY");

/**
 * تُستدعى من تطبيق المشغل فقط. تستقبل channelId وتُرجع رابط m3u8 الحقيقي
 * المسجّل في مجموعة privateStreams (لا يقرأها تطبيق المحتوى ولا أي عميل آخر).
 *
 * تغيير رابط أي قناة يتم من لوحة التحكم مباشرة (لصق الرابط الجديد + حفظ)
 * ويعمل فوراً بدون أي حاجة لإعادة نشر هذه الدالة.
 */
exports.getStreamUrl = onCall(async (request) => {
  const channelId = request.data && request.data.channelId;
  if (!channelId || typeof channelId !== "string") {
    throw new HttpsError("invalid-argument", "channelId مطلوب.");
  }

  const [streamSnap, channelSnap] = await Promise.all([
    db.collection("privateStreams").doc(channelId).get(),
    db.collection("channels").doc(channelId).get(),
  ]);

  if (channelSnap.exists && channelSnap.data().status === "disabled") {
    throw new HttpsError("permission-denied", "هذه القناة موقوفة مؤقتاً.");
  }

  // احتياط: لو القناة مضبوطة كغير محمية، المشغل المفروض يجيب الرابط مباشرة
  // من channels.directUrl بدون المرور من هنا أصلاً. لكن لو انستدعيت الدالة
  // بالغلط لقناة غير محمية، نرجّع رابطها العادي بدل الفشل.
  if (channelSnap.exists && channelSnap.data().protected === false) {
    const directUrl = channelSnap.data().directUrl;
    if (directUrl) {
      return {url: directUrl, expiresIn: null};
    }
  }

  if (!streamSnap.exists) {
    throw new HttpsError(
        "not-found",
        "لم يتم تسجيل مصدر بث لهذه القناة بعد. أضفه من لوحة التحكم.",
    );
  }

  const url = streamSnap.data().url;
  if (!url || typeof url !== "string") {
    throw new HttpsError("not-found", "رابط البث لهذه القناة غير مضبوط.");
  }

  return {
    url,
    // مدة تقديرية للعرض في التطبيق فقط، وليست انتهاء صلاحية فعلي على الرابط نفسه
    // (الحماية الفعلية هي إخفاء privateStreams عن أي قراءة مباشرة من العملاء).
    expiresIn: 60 * 60 * 4,
  };
});

// ==========================================================================
// مباريات اليوم — API-Football بدل TheSportsDB
// ==========================================================================
//
// المشكلة مع TheSportsDB: نستخدم مفتاح الاختبار العام "3"، وهو غير موثوق
// للاستخدام اليومي — أحياناً يرجّع فاضياً رغم وجود مباريات فعلاً. الحل هو
// الانتقال إلى API-Football (تغطية أوسع بكثير + خطة مجانية فعلية 100
// طلب/يوم)، لكن لا يمكن استدعاؤها مباشرة من كود الموبايل (لو حُطّ مفتاحها
// داخل الـ APK، أي شخص يفكّك التطبيق يقدر يسرقه ويستهلك الحصة اليومية
// كاملة خلال دقائق). لذلك — بنفس أسلوب حماية روابط البث أعلاه — الجلب يتم
// من هنا فقط (Cloud Function تملك المفتاح كسرّ محمي)، ويُخزَّن الناتج في
// Firestore، والتطبيق يقرأ من Firestore مباشرة بدون أي مفتاح API إطلاقاً.
//
// نطلب اليوم كله بطلب واحد فقط (fixtures?date=YYYY-MM-DD يرجع كل الدوريات
// حول العالم في استجابة واحدة) — نفس فكرة "طلب واحد بدل تعداد كل دوري"
// المعتمدة سابقاً مع TheSportsDB، فقط بمصدر بيانات أوثق.
//
// نطبّع كل مباراة لنفس أسماء الحقول اللي كانت تُرجعها TheSportsDB
// (idEvent, strLeague, strHomeTeam...) — بهذا الشكل MatchModel.fromTheSportsDb
// في تطبيق فلاتر يبقى يعمل بدون أي تعديل، وملف الترجمة العربية للدوريات
// والفرق (football_ar_translations.dart) يبقى يعمل كما هو أيضاً.

const MATCHES_COLLECTION = "matches_daily";

function mapFixtureStatus(shortStatus) {
  const s = (shortStatus || "").toString().toUpperCase();
  if (["1H", "2H", "HT", "ET", "P", "LIVE", "BT"].includes(s)) return "LIVE";
  if (["FT", "AET", "PEN"].includes(s)) return "FT";
  if (["PST", "CANC", "ABD", "SUSP", "INT"].includes(s)) return "PST";
  return "NS"; // لم تبدأ بعد
}

function normalizeFixture(fx) {
  const fixture = fx.fixture || {};
  const league = fx.league || {};
  const teams = fx.teams || {};
  const goals = fx.goals || {};

  const dateIso = (fixture.date || "").toString();
  const dateEvent = dateIso.split("T")[0] || "";
  const timePart = dateIso.split("T")[1] || "00:00:00";
  const strTime = timePart.replace(/[+-]\d{2}:\d{2}$/, "").replace("Z", "");

  return {
    idEvent: String(fixture.id ?? ""),
    strLeague: league.name || "",
    strLeagueBadge: league.logo || null,
    strHomeTeam: (teams.home && teams.home.name) || "",
    strAwayTeam: (teams.away && teams.away.name) || "",
    strHomeTeamBadge: (teams.home && teams.home.logo) || null,
    strAwayTeamBadge: (teams.away && teams.away.logo) || null,
    dateEvent,
    strTime: strTime || "00:00:00",
    intHomeScore: goals.home ?? null,
    intAwayScore: goals.away ?? null,
    strStatus: mapFixtureStatus(fixture.status && fixture.status.short),
    strVenue: (fixture.venue && fixture.venue.name) || null,
  };
}

async function fetchAndStoreFixtures(dateStr) {
  const response = await fetch(
      `https://v3.football.api-sports.io/fixtures?date=${dateStr}`,
      {headers: {"x-apisports-key": apiFootballKey.value()}},
  );

  if (!response.ok) {
    throw new HttpsError(
        "unavailable",
        `تعذر الاتصال بـ API-Football (${response.status}).`,
    );
  }

  const body = await response.json();
  const events = (body.response || []).map(normalizeFixture);

  await db.collection(MATCHES_COLLECTION).doc(dateStr).set({
    events,
    updatedAt: FieldValue.serverTimestamp(),
    source: "api-football",
  });

  return events.length;
}

// جدولة تلقائية: كل ساعة تجلب مباريات اليوم الحالي (بتوقيت UTC) وتخزّنها.
// 24 طلب/يوم كحد أقصى من أصل 100 المسموحة بالخطة المجانية — هامش كبير
// يسمح أيضاً بزر "مزامنة الآن" اليدوي من لوحة التحكم دون خطر تجاوز الحد.
exports.syncMatchesHourly = onSchedule(
    {
      schedule: "every 60 minutes",
      secrets: [apiFootballKey],
      region: "us-central1",
    },
    async () => {
      const todayStr = new Date().toISOString().slice(0, 10);
      await fetchAndStoreFixtures(todayStr);
    },
);

// يستدعيها زر "مزامنة الآن" في لوحة التحكم لتحديث فوري بدون انتظار
// الجدولة التلقائية (مثلاً بعد إضافة دوري جديد أو للتأكد بعد شكوى مستخدم).
exports.refreshMatches = onCall(
    {secrets: [apiFootballKey]},
    async (request) => {
      const dateStr =
        (request.data && request.data.date) ||
        new Date().toISOString().slice(0, 10);
      const count = await fetchAndStoreFixtures(dateStr);
      return {ok: true, count, date: dateStr};
    },
);
