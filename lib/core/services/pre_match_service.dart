import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pre_match_info_model.dart';
import 'worker_config.dart';

sealed class PreMatchResult {}

class PreMatchSuccess extends PreMatchResult {
  final PreMatchInfo info;
  PreMatchSuccess(this.info);
}

class PreMatchUnavailable extends PreMatchResult {
  final String message;
  PreMatchUnavailable(this.message);
}

class PreMatchError extends PreMatchResult {
  final String message;
  PreMatchError(this.message);
}

/// يجلب معلومات ما قبل المباراة (آخر 5 مباريات لكل فريق + آخر مواجهات
/// مباشرة) عبر /getPreMatchInfo بالووركر. الكاش هناك مشترك بين كل
/// المستخدمين ولكل يوم واحد لكل زوج فرق — لا علاقة له بالمباراة المحددة،
/// لذلك يُبنى المفتاح من رقمي الفريقين فقط (وليس رقم المباراة).
class PreMatchService {
  PreMatchService._();

  static Future<PreMatchResult> fetchInfo({
    required String homeTeamId,
    required String awayTeamId,
  }) async {
    if (homeTeamId.isEmpty || awayTeamId.isEmpty) {
      return PreMatchUnavailable('معلومات الفريقين غير متوفرة لهذه المباراة.');
    }
    try {
      final response = await http
          .post(
            Uri.parse('$kWorkerBaseUrl/getPreMatchInfo'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'homeTeamId': homeTeamId,
              'awayTeamId': awayTeamId,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        return PreMatchError(
          (data['message'] as String?) ?? 'تعذر جلب معلومات ما قبل المباراة.',
        );
      }

      final raw = data['info'] as Map<String, dynamic>?;
      if (raw == null) {
        return PreMatchUnavailable(
          (data['message'] as String?) ?? 'لا توجد بيانات كافية بعد.',
        );
      }

      return PreMatchSuccess(PreMatchInfo.fromJson(raw));
    } catch (_) {
      return PreMatchError('تعذر الاتصال بالخادم. تحقق من الإنترنت.');
    }
  }
}
