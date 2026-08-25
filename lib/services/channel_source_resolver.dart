import 'package:cloud_firestore/cloud_firestore.dart';

import 'stream_auth_service.dart';

/// يقرأ حالة القناة أولاً (channels/{id}):
/// - إذا protected == false: يستخدم رابط directUrl مباشرة (بدون Cloud Function،
///   بدون تأخير التوكن) — مناسب للقنوات المستقرة اللي ما تحتاج حماية إضافية.
/// - غير ذلك (الوضع الافتراضي): يمر عبر StreamAuthService (Cloud Function
///   getStreamUrl) للحصول على رابط موقّت ومحمي.
class ChannelSourceResolver {
  static Future<StreamSession> resolve(String channelId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('channels')
          .doc(channelId)
          .get();
      final data = snapshot.data();
      final isProtected = data == null || data['protected'] != false;

      if (!isProtected) {
        final directUrl = data?['directUrl'] as String?;
        if (directUrl == null || directUrl.isEmpty) {
          return StreamSession.failure('لم يتم ضبط رابط البث لهذه القناة بعد.');
        }
        return StreamSession.success(url: directUrl);
      }
    } catch (_) {
      // إذا تعذر التحقق من حالة الحماية، نكمل بالمسار الآمن الافتراضي
      // عبر Cloud Function بدلاً من الفشل الكامل.
    }
    return StreamAuthService.requestSession(channelId);
  }
}
