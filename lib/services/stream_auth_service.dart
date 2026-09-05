import 'dart:convert';

import 'package:http/http.dart' as http;

import 'stream_models.dart';
import 'worker_config.dart';

/// يطلب جلسة بث موقّتة من نقطة /getStreamUrl على Cloudflare Worker
/// (بديل Firebase Cloud Functions — راجع cloudflare-worker/README.md).
/// يدعم شكلين من الاستجابة:
/// 1) الشكل الجديد المتعدد: { kind, isLive, servers: [{label, qualities:[{label,url}]}] }
/// 2) الشكل القديم المبسّط: { url, expiresIn } — يُحوَّل تلقائياً لسيرفر واحد بجودة واحدة
class StreamAuthService {
  static Future<StreamSession> requestSession(String channelId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$kWorkerBaseUrl/getStreamUrl'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'channelId': channelId}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        return StreamSession.failure(
          _mapError(data['error'] as String?, data['message'] as String?),
        );
      }

      final rawServers = data['servers'] as List?;
      if (rawServers != null && rawServers.isNotEmpty) {
        final servers = rawServers
            .whereType<Map>()
            .map((s) => StreamServerOption.fromMap(s))
            .where((s) => s.qualities.isNotEmpty)
            .toList();
        if (servers.isEmpty) {
          return StreamSession.failure('لم تصل جودات بث صالحة من الخادم.');
        }
        return StreamSession.success(
          kind: _kindFromString(data['kind'] as String?),
          isLive: data['isLive'] == true,
          servers: servers,
        );
      }

      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        return StreamSession.failure('لم يصل رابط بث صالح من الخادم.');
      }
      return StreamSession.success(
        kind: _kindFromString(data['kind'] as String?),
        isLive: data['isLive'] == true,
        servers: [
          StreamServerOption(
            label: 'السيرفر الرئيسي',
            qualities: [StreamQuality(label: 'تلقائي', url: url)],
          ),
        ],
      );
    } catch (_) {
      return StreamSession.failure(
          'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى.');
    }
  }

  static StreamKind _kindFromString(String? value) {
    switch (value) {
      case 'dash':
        return StreamKind.dash;
      case 'progressive':
        return StreamKind.progressive;
      case 'hls':
        return StreamKind.hls;
      default:
        return StreamKind.hls;
    }
  }

  static String _mapError(String? code, String? message) {
    switch (code) {
      case 'not-found':
        return 'هذه القناة غير متاحة حالياً.';
      case 'permission-denied':
      case 'unauthenticated':
        return 'لا تملك صلاحية مشاهدة هذه القناة.';
      case 'resource-exhausted':
        return 'الخادم مشغول حالياً، حاول بعد قليل.';
      default:
        return message ?? 'تعذر تجهيز البث.';
    }
  }
}
