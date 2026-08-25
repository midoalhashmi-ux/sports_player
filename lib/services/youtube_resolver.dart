import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'stream_models.dart';

/// يستخرج رابط تشغيل مباشر من رابط يوتيوب — يدعم:
/// - فيديو يوتيوب عادي (يرجع كل الجودات المتاحة)
/// - بث يوتيوب مباشر (يرجع رابط HLS مباشر)
class YoutubeResolver {
  static Future<StreamSession> resolve(String youtubeUrl) async {
    final yt = YoutubeExplode();
    try {
      final videoId = VideoId(youtubeUrl);
      final video = await yt.videos.get(videoId);

      if (video.isLive) {
        final liveUrl =
            await yt.videos.streamsClient.getHttpLiveStreamUrl(videoId);
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

      final manifest = await yt.videos.streamsClient.getManifest(videoId);
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
}
