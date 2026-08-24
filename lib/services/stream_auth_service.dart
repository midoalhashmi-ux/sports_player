import 'package:cloud_functions/cloud_functions.dart';

/// يطلب رابط بث موقّت وصالح لمدة محدودة من Cloud Function باسم getStreamUrl.
/// لا يتعامل أبداً مع رابط m3u8 الحقيقي بشكل مباشر أو يخزّنه.
/// ملاحظة: هذه الدالة السحابية لم تُبنَ بعد (الخطوة 6 من خارطة الطريق)،
/// لذا ستفشل الاستدعاءات مؤقتاً برسالة خطأ واضحة حتى إنجاز تلك الخطوة.
class StreamAuthService {
  static Future<StreamSession> requestSession(String channelId) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('getStreamUrl');
      final result = await callable.call({'channelId': channelId});
      final data = Map<String, dynamic>.from(result.data as Map);
      final url = data['url'] as String?;
      final expiresInSeconds = data['expiresIn'] as int?;

      if (url == null || url.isEmpty) {
        return StreamSession.failure('لم يصل رابط بث صالح من الخادم.');
      }
      return StreamSession.success(
        url: url,
        expiresIn: expiresInSeconds != null
            ? Duration(seconds: expiresInSeconds)
            : null,
      );
    } on FirebaseFunctionsException catch (e) {
      return StreamSession.failure(_mapError(e));
    } catch (_) {
      return StreamSession.failure(
          'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى.');
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

class StreamSession {
  final bool ok;
  final String? url;
  final Duration? expiresIn;
  final String? errorMessage;

  const StreamSession._({
    required this.ok,
    this.url,
    this.expiresIn,
    this.errorMessage,
  });

  factory StreamSession.success({required String url, Duration? expiresIn}) =>
      StreamSession._(ok: true, url: url, expiresIn: expiresIn);

  factory StreamSession.failure(String message) =>
      StreamSession._(ok: false, errorMessage: message);
}
