import 'package:cloud_firestore/cloud_firestore.dart';

import 'feature_flags_service.dart';
import 'stream_auth_service.dart';
import 'stream_models.dart';
import 'youtube_id_extractor.dart';

/// يقرأ حالة القناة أولاً (channels/{id}):
/// - sourceType == 'youtube': تُشغَّل عبر مشغل يوتيوب الرسمي (لا يُستخرج
///   أي رابط بث)، فقط لو settings/features.youtubeEnabled = true من لوحة
///   التحكم. معرّف/رابط الفيديو يُقرأ من حقل youtubeUrl، وإن لم يوجد من
///   directUrl كبديل. لو الميزة موقوفة أو الحقل فاضي/غير صالح، تُعامل
///   كخطأ إعداد واضح بدل محاولة استخراج أي رابط.
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
        await FeatureFlagsService.instance.ensureLoaded();
        if (!FeatureFlagsService.instance.youtubeEnabled) {
          return StreamSession.failure(
              'تشغيل يوتيوب موقوف مؤقتاً من لوحة التحكم لهذه القناة.');
        }
        final youtubeSource =
            (data['youtubeUrl'] as String?) ?? (data['directUrl'] as String?);
        final videoId = youtubeSource != null
            ? YoutubeIdExtractor.extract(youtubeSource)
            : null;
        if (videoId == null) {
          return StreamSession.failure(
              'رابط يوتيوب لهذه القناة غير مضبوط أو غير صالح من لوحة التحكم.');
        }
        return StreamSession.youtube(videoId);
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
