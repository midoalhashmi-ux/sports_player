import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/match_stats_model.dart';
import 'worker_config.dart';

/// نتيجة جلب الإحصائيات — إما إحصائيات جاهزة، أو رسالة (لا إحصائيات
/// متاحة بعد)، أو خطأ اتصال.
sealed class MatchStatsResult {}

class MatchStatsSuccess extends MatchStatsResult {
  final MatchStats stats;
  MatchStatsSuccess(this.stats);
}

class MatchStatsUnavailable extends MatchStatsResult {
  final String message;
  MatchStatsUnavailable(this.message);
}

class MatchStatsError extends MatchStatsResult {
  final String message;
  MatchStatsError(this.message);
}

/// يجلب إحصائيات مباراة عبر نقطة /getMatchStats بالووركر، والتي تحتفظ
/// بكاش مشترك بين كل المستخدمين (راجع cloudflare-worker/src/index.js)
/// حتى لا يستهلك كل ضغطة زر طلب API-Football منفصل.
class MatchStatsService {
  MatchStatsService._();

  static Future<MatchStatsResult> fetchStats({
    required String fixtureId,
    required bool matchFinished,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$kWorkerBaseUrl/getMatchStats'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'fixtureId': fixtureId,
              'finished': matchFinished,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        return MatchStatsError(
          (data['message'] as String?) ?? 'تعذر جلب الإحصائيات.',
        );
      }

      final rawStats = data['statistics'] as List<dynamic>?;
      if (rawStats == null || rawStats.length < 2) {
        return MatchStatsUnavailable(
          (data['message'] as String?) ??
              'لا توجد إحصائيات متاحة لهذه المباراة بعد.',
        );
      }

      final teams = rawStats
          .whereType<Map<String, dynamic>>()
          .map(TeamStats.fromJson)
          .toList();

      return MatchStatsSuccess(MatchStats(home: teams[0], away: teams[1]));
    } catch (_) {
      return MatchStatsError('تعذر الاتصال بالخادم. تحقق من الإنترنت.');
    }
  }
}
