import 'package:cloud_firestore/cloud_firestore.dart';

import 'stream_auth_service.dart';
import 'stream_models.dart';

/// يقرأ حالة القناة أولاً (channels/{id}):
/// - protected == false: يستخدم servers/directUrl المخزّنة مباشرة في المستند.
/// - غير ذلك (الوضع الافتراضي): يمر عبر StreamAuthService لجلسة موقّتة ومحمية.
class ChannelSourceResolver {
  static Future<StreamSession> resolve(String channelId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('channels')
          .doc(channelId)
          .get();
      final data = snapshot.data();

      // يمكن للوحة التحكم تحديد أن المصدر صفحة ويب رسمية بدلاً من رابط
      // فيديو مباشر. في هذه الحالة نعرض الصفحة داخل WebView ولا نحاول
      // تمريرها إلى ExoPlayer كمصدر فيديو.
      if (data != null && data['streamType'] == 'web') {
        if (data['status'] == 'disabled') {
          return StreamSession.failure('هذه القناة متوقفة مؤقتاً.');
        }
        final webUrl = (data['sourceUrl'] ?? data['streamUrl'] ?? data['directUrl'] ?? '').toString().trim();
        if (webUrl.isEmpty) {
          return StreamSession.failure('لم يتم ضبط رابط صفحة البث لهذه القناة بعد.');
        }
        return StreamSession.success(
          kind: StreamKind.web,
          isLive: data['status'] == 'live',
          servers: [
            StreamServerOption(
              label: 'المصدر الرسمي',
              qualities: [StreamQuality(label: 'صفحة البث', url: webUrl)],
            ),
          ],
        );
      }

      final isProtected = data == null || data['protected'] != false;

      if (!isProtected) {
        // القناة غير المحمية معطّلة من لوحة التحكم — كان هذا الفحص غائباً
        // فيستمر تشغيلها من servers/directUrl رغم التعطيل. الآن تُرفض فوراً
        // قبل أي قراءة لمصدر البث.
        if (data?['status'] == 'disabled') {
          return StreamSession.failure('هذه القناة متوقفة مؤقتاً.');
        }

        final rawServers = data?['servers'] as List?;
        if (rawServers != null && rawServers.isNotEmpty) {
          final servers = rawServers
              .whereType<Map>()
              .map((s) => StreamServerOption.fromMap(s))
              .where((s) => s.qualities.isNotEmpty)
              .toList();
          if (servers.isNotEmpty) {
            return StreamSession.success(
              kind: StreamKind.hls,
              isLive: data?['status'] == 'live',
              servers: servers,
            );
          }
        }

        final directUrl = data?['directUrl'] as String?;
        if (directUrl == null || directUrl.isEmpty) {
          return StreamSession.failure('لم يتم ضبط رابط البث لهذه القناة بعد.');
        }
        return StreamSession.success(
          kind: StreamKind.hls,
          isLive: data?['status'] == 'live',
          servers: [
            StreamServerOption(
              label: 'مباشر',
              qualities: [StreamQuality(label: 'تلقائي', url: directUrl)],
            ),
          ],
        );
      }
    } catch (_) {
      // إذا تعذر التحقق من حالة الحماية، نكمل بالمسار الآمن الافتراضي
      // عبر Cloud Function بدلاً من الفشل الكامل.
    }
    return StreamAuthService.requestSession(channelId);
  }
}
