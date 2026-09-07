import 'dart:convert';

import 'package:http/http.dart' as http;

import 'worker_config.dart';

/// يجلب رابط البث الحقيقي لقناة محمية عبر نقطة /getStreamUrl بالووركر
/// (راجع cloudflare-worker/src/index.js). حلّت هذه النقطة محل Firebase
/// Cloud Function القديمة (كانت تحتاج خطة Blaze) — لا حاجة لأي تعديل
/// آخر عند تغيير المصدر، التغيير كله من لوحة التحكم.
class SecureStreamService {
  static Future<String?> getTemporaryStreamUrl(String channelId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$kWorkerBaseUrl/getStreamUrl'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'channelId': channelId}),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode >= 400) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['url'] as String?;
    } catch (_) {
      return null;
    }
  }
}
