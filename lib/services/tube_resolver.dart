import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'stream_models.dart';

/// يستخرج رابط تشغيل مباشر من أي رابط يوتيوب — يدعم كل الصيغ الشائعة:
/// - فيديو عادي: youtube.com/watch?v=ID
/// - رابط مختصر: youtu.be/ID
/// - embed: youtube.com/embed/ID
/// - shorts: youtube.com/shorts/ID
/// - بث مباشر بمعرّف مباشر: youtube.com/live/ID
/// - بث مباشر للقناة (بدون معرّف فيديو): youtube.com/@channel/live,
///   youtube.com/channel/UCxxx/live, youtube.com/c/name/live,
///   youtube.com/user/name/live
class YoutubeResolver {
  static final RegExp _directIdPattern = RegExp(
    r'(?:youtu\.be/|youtube(?:-nocookie)?\.com/(?:watch\?v=|embed/|shorts/|live/|v/))([A-Za-z0-9_-]{11})',
  );

  static final RegExp _watchVParamPattern = RegExp(r'[?&]v=([A-Za-z0-9_-]{11})');

  static final RegExp _channelLivePattern = RegExp(
    r'youtube(?:-nocookie)?\.com/(?:@[^/?#]+|channel/[^/?#]+|c/[^/?#]+|user/[^/?#]+)/live',
  );

  static final RegExp _liveVideoIdInPage = RegExp(
    r'"videoId":"([A-Za-z0-9_-]{11})"',
  );

  static Future<StreamSession> resolve(String youtubeUrl) async {
    final trimmedUrl = youtubeUrl.trim();

    // فيديو/شورتس/live بمعرّف مباشر داخل الرابط نفسه
    var videoId = _extractDirectVideoId(trimmedUrl);

    // بث مباشر للقناة بدون معرّف فيديو صريح — نحتاج جلب صفحة القناة
    // لاكتشاف معرّف الفيديو الحي الحالي
    if (videoId == null && _channelLivePattern.hasMatch(trimmedUrl)) {
      videoId = await _resolveChannelLiveVideoId(trimmedUrl);
      if (videoId == null) {
        return StreamSession.failure(
            'لا يوجد بث مباشر نشط الآن على هذه القناة.');
      }
    }

    if (videoId == null) {
      return StreamSession.failure('رابط يوتيوب غير صالح أو غير مدعوم.');
    }

    final yt = YoutubeExplode();
    try {
      final id = VideoId(videoId);
      final video = await yt.videos.get(id);

      if (video.isLive) {
        final liveUrl = await yt.videos.streamsClient.getHttpLiveStreamUrl(id);
        return StreamSession.success(
          kind: StreamKind.hls,
          isLive: true,
          servers: [
            StreamServerOption(
              label: 'يوتيوب مباشر',
              qualities: [StreamQuality(label: 'تلقائي', url: liveUrl)],
            ),
          ],
        );
      }

      final manifest = await yt.videos.streamsClient.getManifest(id);
      final muxed = manifest.muxed.toList()
        ..sort((a, b) => b.videoQuality.index.compareTo(a.videoQuality.index));

      if (muxed.isEmpty) {
        return StreamSession.failure('لا توجد جودات متاحة لهذا الفيديو.');
      }

      return StreamSession.success(
        kind: StreamKind.progressive,
        isLive: false,
        servers: [
          StreamServerOption(
            label: 'يوتيوب',
            qualities: muxed
                .map((s) => StreamQuality(
                      label: s.qualityLabel,
                      url: s.url.toString(),
                    ))
                .toList(),
          ),
        ],
      );
    } catch (_) {
      return StreamSession.failure(
          'تعذر تحميل فيديو يوتيوب. قد يكون خاصاً أو محذوفاً أو غير متاح في منطقتك.');
    } finally {
      yt.close();
    }
  }

  /// يستخرج معرّف الفيديو (11 حرف) من أي صيغة رابط يوتيوب معروفة تحتوي
  /// عليه مباشرة. يرجع null لو الرابط لا يحتوي معرّف فيديو صريح (مثل
  /// روابط بث القناة المباشر).
  static String? _extractDirectVideoId(String url) {
    final directMatch = _directIdPattern.firstMatch(url);
    if (directMatch != null) return directMatch.group(1);

    final vParamMatch = _watchVParamPattern.firstMatch(url);
    if (vParamMatch != null) return vParamMatch.group(1);

    // رابط بحجم 11 حرفاً فقط (معرّف مباشر بلا أي شيء حوله)
    final bareId = url.trim();
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(bareId)) return bareId;

    return null;
  }

  /// يجلب صفحة بث القناة المباشر (مثل youtube.com/@channel/live) ويستخرج
  /// معرّف الفيديو الحي الحالي من داخل الصفحة. يرجع null لو ما فيه بث
  /// نشط حالياً أو تعذر الجلب.
  static Future<String?> _resolveChannelLiveVideoId(String channelUrl) async {
    try {
      final response = await http.get(
        Uri.parse(channelUrl),
        headers: {
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final match = _liveVideoIdInPage.firstMatch(response.body);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }
}
