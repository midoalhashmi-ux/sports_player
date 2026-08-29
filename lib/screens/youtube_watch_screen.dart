import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../services/ad_service.dart';

/// شاشة تشغيل يوتيوب عبر المشغل الرسمي (YouTube IFrame Player API عبر
/// WebView رسمي). لا تستخرج أي رابط بث ولا تتصل بأي شيء غير مشغل يوتيوب
/// نفسه — بديل متوافق مع شروط يوتيوب لمسار الاستخراج المحذوف.
///
/// تُستخدم فقط عندما settings/features.youtubeEnabled = true (يُتحقق
/// منه قبل التنقّل لهذه الشاشة، عبر FeatureFlagsService).
class YoutubeWatchScreen extends StatefulWidget {
  final String videoId;
  final String? title;

  const YoutubeWatchScreen({super.key, required this.videoId, this.title});

  @override
  State<YoutubeWatchScreen> createState() => _YoutubeWatchScreenState();
}

class _YoutubeWatchScreenState extends State<YoutubeWatchScreen> {
  late final YoutubePlayerController _controller;
  bool _adDone = false;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        enableJavaScript: true,
      ),
    );
    // نفس منطق شاشة المشاهدة العادية: نعرض الإعلان البيني أولاً (إن
    // وجد)، ولا نحمّل الفيديو إلا بعد إغلاقه، حتى لا يشتغل صوت خلف
    // الإعلان.
    AdService.instance.showInterstitialThenProceed(() {
      if (!mounted) return;
      setState(() => _adDone = true);
      _controller.loadVideoById(videoId: widget.videoId);
    });
  }

  // نفس سلوك الخروج بشاشة المشاهدة العادية: رجوع عادي لو فيه شاشة سابقة،
  // وإلا إغلاق تطبيق المشغل بالكامل.
  void _exit() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: !_adDone
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        tooltip: 'رجوع',
                        onPressed: _exit,
                      ),
                      if (widget.title != null && widget.title!.isNotEmpty)
                        Expanded(
                          child: Text(
                            widget.title!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  YoutubePlayer(controller: _controller, aspectRatio: 16 / 9),
                ],
              ),
      ),
    );
  }
}
