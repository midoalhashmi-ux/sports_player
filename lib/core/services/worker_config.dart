/// عنوان Cloudflare Worker (نفس الموجود بتطبيق المشغل sports_player) —
/// يُستخدم هنا فقط لجلب إحصائيات المباراة عبر /getMatchStats.
/// جلب النتائج نفسها لا يمر من هنا؛ التطبيق يقرأ مباشرة من Firestore
/// (matches_daily) عبر MatchesService.
const String kWorkerBaseUrl = 'https://binsheikh-api.binsheikh.workers.dev';
