import 'package:cloud_functions/cloud_functions.dart';

import 'stream_models.dart';

/// يطلب جلسة بث موقّتة من Cloud Function باسم getStreamUrl.
/// يدعم شكلين من الاستجابة:
/// 1) الشكل الجديد المتعدد: { kind, isLive, servers: [{label, qualities:[{label,url}]}] }
/// 2) الشكل القديم المبسّط: { url, expiresIn } — يُحوَّل تلقائياً لسيرفر واحد بجودة واحدة
class StreamAuthService {
  static Future<StreamSession> requestSession(String channelId) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('getStreamUrl');
      final result = await callable.call({'channelId': channelId});
      final data = Map<String, dynamic>.from(result.data as Map);

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
    } on FirebaseFunctionsException catch (e) {
      return StreamSession.failure(_mapError(e));
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

  static String _mapError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'هذه القناة غير متاحة حالياً.';
      case 'permission-denied':
      case 'unauthenticated':
        return 'لا تملك صلاحية مشاهدة هذه القناة.';
      case 'resource-exhausted':
        return 'الخادم مشغول حالياً، حاول بعد قليل.';
      default:
        return 'تعذر تجهيز البث (${e.code}).';
    }
  }
}
