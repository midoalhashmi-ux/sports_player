import 'package:cloud_firestore/cloud_firestore.dart';

import 'stream_auth_service.dart';
import 'stream_models.dart';
import 'youtube_resolver.dart';

/// يقرأ حالة القناة أولاً (channels/{id}):
/// - sourceType == 'youtube': يستخرج الرابط عبر YoutubeResolver مباشرة (بدون خادم).
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

      if (data != null && data['sourceType'] == 'youtube') {
        final youtubeUrl = data['directUrl'] as String?;
        if (youtubeUrl == null || youtubeUrl.isEmpty) {
          return StreamSession.failure('لم يتم ضبط رابط يوتيوب لهذه القناة.');
        }
        return YoutubeResolver.resolve(youtubeUrl);
      }

      final isProtected = data == null || data['protected'] != false;

      if (!isProtected) {
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
