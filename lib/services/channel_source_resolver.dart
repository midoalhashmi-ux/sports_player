import 'package:cloud_firestore/cloud_firestore.dart';

import 'api_source_resolver.dart';
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

      // الحالة مركزية من لوحة التحكم: القناة المعطّلة لا يجوز أن تمر
      // لأي مسار (Web/HLS/محمي/Cloud Function).
      if (data != null && data['status'] == 'disabled') {
        return StreamSession.failure('هذه القناة متوقفة مؤقتاً.');
      }

      // القناة قد تحمل Referer/User-Agent اختياريين محفوظين من لوحة التحكم
      // (channels.sourceHeaders). فارغان تماماً = استخدم افتراضيات
      // WebView/الشبكة، ولا يُعتبر غيابهما سبباً لفشل الحل.
      final rawHeaders = data?['sourceHeaders'];
      final sourceHeaders = <String, String>{};
      if (rawHeaders is Map) {
        final referer = rawHeaders['referer']?.toString().trim();
        final userAgent = (rawHeaders['user-agent'] ?? rawHeaders['userAgent'])
            ?.toString()
            .trim();
        if (referer != null && referer.isNotEmpty) sourceHeaders['referer'] = referer;
        if (userAgent != null && userAgent.isNotEmpty) sourceHeaders['user-agent'] = userAgent;
      }

      // API ديناميكي: نخزّن عنوان API المستقر فقط، ثم نطلب منه رابط البث
      // المؤقت أثناء التشغيل. apiHeaders مخصصة لطلب API، بينما sourceHeaders
      // تبقى هيدرز التشغيل/Referer الخاصة برابط HLS النهائي. للتوافق مع
      // السجلات القديمة، إذا غابت apiHeaders نستخدم sourceHeaders للطلب أيضاً.
      if (data != null && data['streamType'] == 'api') {
        final apiUrl = (data['sourceUrl'] ?? data['apiUrl'] ?? '').toString().trim();
        if (apiUrl.isEmpty) {
          return StreamSession.failure('لم يتم ضبط رابط API لهذه القناة بعد.');
        }
        final apiHeaders = <String, String>{};
        final rawApiHeaders = data['apiHeaders'];
        if (rawApiHeaders is Map) {
          for (final entry in rawApiHeaders.entries) {
            final key = entry.key.toString().trim().toLowerCase();
            final value = entry.value?.toString().trim() ?? '';
            if ((key == 'referer' || key == 'user-agent') && value.isNotEmpty) {
              apiHeaders[key] = value;
            }
          }
        }
        final requestHeaders = apiHeaders.isNotEmpty ? apiHeaders : sourceHeaders;
        final candidates = await ApiSourceResolver.resolve(
          apiUrl,
          headers: requestHeaders,
          onDiagnostic: (message) => ApiSourceResolver.safeDiagnostic(
            'channel=${_safeId(channelId)} $message',
          ),
        );
        final playable = candidates.where(
          (item) => _isPlayableUrl(item.url) || item.reason == 'direct media response',
        );
        final candidate = playable.isEmpty ? null : playable.first;
        if (candidate == null) {
          return StreamSession.failure(
            'تعذر استخراج رابط بث صالح من API. تحقق من نوع الرد أو إعدادات Headers.',
          );
        }
        final lower = candidate.url.toLowerCase();
        final kind = lower.contains('.mpd')
            ? StreamKind.dash
            : lower.contains('.m3u8') || lower.contains('.m3u')
                ? StreamKind.hls
                : StreamKind.progressive;
        return StreamSession.success(
          kind: kind,
          isLive: data['status'] == 'live',
          servers: [
            StreamServerOption(
              label: 'API ديناميكي',
              qualities: [StreamQuality(label: 'تلقائي', url: candidate.url)],
            ),
          ],
          headers: sourceHeaders,
        );
      }

      // يمكن للوحة التحكم تحديد أن المصدر صفحة ويب رسمية بدلاً من رابط
      // فيديو مباشر. في هذه الحالة نعرض الصفحة داخل WebView ولا نحاول
      // تمريرها إلى ExoPlayer كمصدر فيديو.
      if (data != null && data['streamType'] == 'web') {
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
          headers: sourceHeaders,
        );
      }

      final isProtected = data == null || data['protected'] != false;

      if (!isProtected) {
        final rawServers = data['servers'] as List?;
        if (rawServers != null && rawServers.isNotEmpty) {
          final servers = rawServers
              .whereType<Map>()
              .map((s) => StreamServerOption.fromMap(s))
              .where((s) => s.qualities.isNotEmpty)
              .toList();
          if (servers.isNotEmpty) {
            return StreamSession.success(
              kind: StreamKind.hls,
              isLive: data['status'] == 'live',
              servers: servers,
              headers: sourceHeaders,
            );
          }
        }

        final directUrl = data['directUrl'] as String?;
        if (directUrl == null || directUrl.isEmpty) {
          return StreamSession.failure('لم يتم ضبط رابط البث لهذه القناة بعد.');
        }
        return StreamSession.success(
          kind: StreamKind.hls,
          isLive: data['status'] == 'live',
          servers: [
            StreamServerOption(
              label: 'مباشر',
              qualities: [StreamQuality(label: 'تلقائي', url: directUrl)],
            ),
          ],
          headers: sourceHeaders,
        );
      }
    } catch (_) {
      // إذا تعذر التحقق من حالة الحماية، نكمل بالمسار الآمن الافتراضي
      // عبر Cloud Function بدلاً من الفشل الكامل.
    }
    return StreamAuthService.requestSession(channelId);
  }

  static bool _isPlayableUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.m3u') ||
        lower.contains('.mpd') ||
        RegExp(r'\.(mp4|m4v|webm|mov)(?:$|[?#])').hasMatch(lower) ||
        lower.contains('/live/') ||
        lower.contains('/stream/') ||
        lower.contains('/playlist/') ||
        lower.contains('/manifest/');
  }

  static String _safeId(String value) {
    final clean = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return clean.length > 32 ? clean.substring(0, 32) : clean;
  }
}
