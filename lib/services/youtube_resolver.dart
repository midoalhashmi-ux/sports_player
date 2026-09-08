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

      // نطلب أكثر من "عميل" يوتيوب معاً (وليس العميل الافتراضي فقط) — بعض
      // الفيديوهات ترفض تسليم الروابط لعميل معيّن أو تتطلب فك تشفير توقيع
      // (signature) يفشل أحياناً مع العميل الافتراضي وحده. هذا يطابق توصية
      // مكتبة youtube_explode_dart نفسها لزيادة نسبة نجاح الاستخراج.
      final manifest = await yt.videos.streamsClient.getManifest(
        id,
        ytClients: const [
          YoutubeApiClient.safari,
          YoutubeApiClient.androidVr,
          YoutubeApiClient.ios,
        ],
      );
      final muxed = manifest.muxed.toList()
        ..sort((a, b) => b.videoQuality.index.compareTo(a.videoQuality.index));

      if (muxed.isEmpty) {
        // لا توجد صيغة واحدة تجمع الصورة والصوت معاً — هذا شائع في
        // الفيديوهات الحديثة (يوتيوب توقف عملياً عن توفير muxed بجودة
        // أعلى من 360p لكثير من الفيديوهات). نحاول كحل أخير أي بث HLS
        // متاح لهذا الفيديو، لأن مشغلنا (video_player) يدعم HLS مباشرة
        // بنفس طريقة الرابط المفرد تماماً مثل muxed.
        try {
          final hlsUrl = await yt.videos.streamsClient.getHttpLiveStreamUrl(id);
          return StreamSession.success(
            kind: StreamKind.hls,
            isLive: false,
            servers: [
              StreamServerOption(
                label: 'يوتيوب',
                qualities: [StreamQuality(label: 'تلقائي', url: hlsUrl)],
              ),
            ],
          );
        } catch (_) {
          return StreamSession.failure(
              'هذا الفيديو لا يوفر صيغة تشغيل مباشرة مدعومة (يوتيوب لا يوفر رابطاً مدمجاً للصوت والصورة لبعض الفيديوهات الحديثة).');
        }
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
    } catch (error, stackTrace) {
      // نسجّل الخطأ الحقيقي في سجلات التطبيق (تظهر في adb logcat / سجلات
      // الأعطال) بدل ابتلاعه بصمت — بدون هذا يستحيل تشخيص أي فيديو تحديداً
      // يفشل ولماذا.
      // ignore: avoid_print
      print('[YoutubeResolver] فشل استخراج الفيديو $videoId: $error\n$stackTrace');
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
