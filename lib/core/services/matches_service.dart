import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/match_model.dart';

/// يقرأ جدول مباريات كرة القدم ليوم محدد من Firestore، بعد أن تكون
/// Cloud Function (syncMatchesHourly / refreshMatches) قد جلبتها من
/// API-Football وخزّنتها هناك.
///
/// لا يوجد أي اتصال مباشر بأي API خارجي من هنا، ولا أي مفتاح API داخل
/// التطبيق — التطبيق يقرأ فقط من مستند جاهز في مجموعة matches_daily.
/// هذا يحل مشكلة عدم موثوقية TheSportsDB (كان أحياناً يرجّع فاضياً رغم
/// وجود مباريات فعلاً)، ويمنع أيضاً أي احتمال لسرقة مفتاح API-Football
/// من داخل الـ APK.
class MatchesService {
  MatchesService._();

  static const _collection = 'matches_daily';

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static Future<List<MatchModel>> fetchMatches(DateTime date) async {
    final doc = await FirebaseFirestore.instance
        .collection(_collection)
        .doc(_dateKey(date))
        .get();

    if (!doc.exists) return [];

    final data = doc.data();
    final events = data?['events'] as List<dynamic>?;
    if (events == null || events.isEmpty) return [];

    // نفس دالة التحويل المستخدمة سابقاً مع TheSportsDB — الحقول اللي
    // تخزّنها الـ Cloud Function في Firestore بنفس التسمية والشكل تماماً
    // (idEvent, strLeague, strHomeTeam...)، فلا حاجة لأي دالة تحويل جديدة.
    final matches = events
        .whereType<Map<String, dynamic>>()
        .map(MatchModel.fromTheSportsDb)
        .toList();

    matches.sort((a, b) => a.kickoff.compareTo(b.kickoff));
    return matches;
  }
}
