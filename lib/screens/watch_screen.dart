import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

import '../services/ad_service.dart';
import '../services/channel_source_resolver.dart';
import '../services/stream_models.dart';
import '../services/youtube_resolver.dart';

enum _LoadState { loading, error, ready }

class WatchScreen extends StatefulWidget {
  final String? channelId;
  final String? externalUrl;
  final bool externalIsYoutube;
  final String? externalUserAgent;

  const WatchScreen({
    super.key,
    this.channelId,
    this.externalUrl,
    this.externalIsYoutube = false,
    this.externalUserAgent,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  final GlobalKey _videoBoundaryKey = GlobalKey();

  _LoadState _state = _LoadState.loading;
  String _errorMessage = '';
  StreamSession? _session;
  StreamServerOption? _activeServer;
  StreamQuality? _activeQuality;
  Map<String, String>? _headers;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100;
  bool _muted = false;
  bool _fullscreen = false;

  bool _locked = false;
  BoxFit _fit = BoxFit.contain;
  String? _seekFeedback;
  Timer? _seekFeedbackTimer;

  // speed / screenshot
  double _playbackSpeed = 1.0;
  bool _savingScreenshot = false;
  bool _showSpeedSheet = false;

  // swipe
  Offset? _swipeStart;
  bool _seekingFromSwipe = false;
  double _lastBrightness = 1.0;
  bool _brightnessMode = false;

  static const _swipeThreshold = 28.0;
  static const _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  // ---------------------------------------------------------------------
  // إصلاح جذري لمشكلة "صوت البث خلف الإعلان": يحدث هذا تحديداً عند اختيار
  // قناة جديدة والمشغل يعمل بالفعل في الخلفية (المستخدم فتح قناة، رجع
  // للتطبيق الرئيسي، ثم اختار قناة أخرى). في هذه الحالة تصل الشاشة الجديدة
  // عبر رابط عميق وتستبدل المكدس، لكن شاشة المشاهدة *القديمة* تبقى حيّة
  // (وصوتها يعمل) طوال مدة أنيميشن الانتقال قبل أن يُستدعى dispose() لها —
  // وخلال هذه اللحظة بالذات يظهر إعلان الشاشة الجديدة فيبدو الصوت القديم
  // "خلف" الإعلان. نحتفظ بمرجع ثابت لآخر شاشة مشاهدة نشطة، ونُسكتها فوراً
  // (بشكل متزامن، قبل أي إعلان أو تحميل) بمجرد أن تبدأ شاشة جديدة.
  static _WatchScreenState? _activeInstance;

  void _forceSilenceInstantly() {
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      controller.setVolume(0);
      controller.pause();
    }
  }

  @override
  void initState() {
    super.initState();
    // أول شيء إطلاقاً قبل أي إعلان أو تحميل: نُسكت أي شاشة مشاهدة سابقة
    // ما زالت حيّة، حتى لا يتداخل صوتها مع الإعلان الجديد.
    _activeInstance?._forceSilenceInstantly();
    _activeInstance = this;
    // نراقب دورة حياة التطبيق لنوقف الصوت/الفيديو فوراً إذا خرج المستخدم
    // من التطبيق (زر الرئيسية، تبديل تطبيق، إغلاقه من الأخير...) بدل ما
    // يستمر البث يشتغل بالخلفية بدون أي واجهة ظاهرة له.
    WidgetsBinding.instance.addObserver(this);
    _scheduleHide();
    // نعرض الإعلان البيني أولاً (إن وجد)، ولا نبدأ تحميل/تشغيل البث إلا
    // بعد إغلاقه — بهذا الشكل لا يشتغل صوت أو صورة البث خلف الإعلان
    // إطلاقاً.
    AdService.instance.showInterstitialThenProceed(() {
      if (mounted) _startSession();
    });
  }

  // ---------------------- player listener ----------------------
  void _videoListener() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'تعذر تشغيل رابط البث. جرّب مرة أخرى أو غيّر السيرفر.';
      });
      return;
    }
    setState(() {
      _isPlaying = value.isPlaying;
      _isBuffering = value.isBuffering;
      _position = value.position;
      _duration = value.duration;
    });
  }

  // ---------------------- session ----------------------
  Future<void> _startSession() async {
    setState(() => _state = _LoadState.loading);

    _headers = (widget.externalUserAgent != null &&
            widget.externalUserAgent!.isNotEmpty)
        ? {'user-agent': widget.externalUserAgent!}
        : null;

    final StreamSession session;
    if (widget.externalUrl != null && widget.externalUrl!.isNotEmpty) {
      session = widget.externalIsYoutube
          ? await YoutubeResolver.resolve(widget.externalUrl!)
          : StreamSession.success(
              kind: StreamKind.hls,
              isLive: false,
              servers: [
                StreamServerOption(
                  label: 'الرابط المُدخل',
                  qualities: [
                    StreamQuality(label: 'تلقائي', url: widget.externalUrl!)
                  ],
                ),
              ],
            );
    } else if (widget.channelId != null) {
      session = await ChannelSourceResolver.resolve(widget.channelId!);
    } else {
      session = StreamSession.failure('لا يوجد مصدر بث لتشغيله.');
    }

    if (!mounted) return;

    if (!session.ok || session.servers.isEmpty) {
      setState(() {
        _state = _LoadState.error;
        _errorMessage = session.errorMessage ?? 'تعذر تشغيل البث.';
      });
      return;
    }

    _session = session;
    await _playServerQuality(
      session.servers.first,
      session.servers.first.qualities.first,
    );
  }

  // ---------------------- play ----------------------
  Future<void> _playServerQuality(
      StreamServerOption server, StreamQuality quality) async {
    setState(() {
      _state = _LoadState.loading;
      _activeServer = server;
      _activeQuality = quality;
    });
    try {
      final oldController = _controller;
      oldController?.removeListener(_videoListener);
      await oldController?.dispose();

      final newController = VideoPlayerController.networkUrl(
        Uri.parse(quality.url),
        httpHeaders: _headers ?? const {},
      );
      _controller = newController;
      newController.addListener(_videoListener);
      await newController.initialize();
      await newController.setPlaybackSpeed(_playbackSpeed);
      await newController.setVolume(_muted ? 0 : _volume / 100);
      await newController.play();
      await WakelockPlus.enable();
      if (!mounted) return;
      setState(() => _state = _LoadState.ready);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'تعذر تشغيل هذا المصدر. جرّب سيرفر أو جودة أخرى.';
      });
    }
  }

  // ---------------------- controls ----------------------
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_locked) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (_locked) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    _isPlaying ? controller.pause() : controller.play();
    _scheduleHide();
  }

  void _seekBy(Duration delta) {
    final controller = _controller;
    if (controller == null) return;
    final target = _position + delta;
    controller.seekTo(target < Duration.zero ? Duration.zero : target);
    _scheduleHide();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : _volume / 100);
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      _muted = value == 0;
    });
    _controller?.setVolume(_muted ? 0 : value / 100);
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  // نخرج من شاشة المشاهدة: لو فيه شاشة سابقة على المكدس نرجع لها عادي،
  // ولو ما فيه (لأن التطبيق فُتح عبر رابط من تطبيق المحتوى وشاشة المشاهدة
  // هي الشاشة الوحيدة) نغلق تطبيق المشغل بالكامل ونرجع المستخدم مباشرة
  // لتطبيق المحتوى، بدل ما يعلّق على شاشة داخلية فارغة بالمشغل.
  void _exit() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      SystemNavigator.pop();
    }
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    if (!_locked) {
      setState(() => _controlsVisible = true);
      _scheduleHide();
    }
  }

  void _toggleFit() {
    setState(
        () => _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain);
  }

  void _jumpToLive() {
    final controller = _controller;
    if (controller == null) return;
    if (_duration > Duration.zero) {
      controller.seekTo(_duration);
    }
    if (!_isPlaying) controller.play();
    _scheduleHide();
  }

  Future<void> _changeSpeed(double speed) async {
    await _controller?.setPlaybackSpeed(speed);
    setState(() {
      _playbackSpeed = speed;
      _showSpeedSheet = false;
    });
    _scheduleHide();
  }

  void _openSpeedSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('سرعة التشغيل',
                    style: TextStyle(color: Colors.white70)),
              ),
              ..._speedOptions.map((speed) {
                final selected = speed == _playbackSpeed;
                return ListTile(
                  title: Text(
                    '${speed}x',
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check, color: Colors.greenAccent)
                      : null,
                  onTap: () => _changeSpeed(speed),
                );
              }),
            ],
          ),
        );
      },
    ).then((_) {
      if (mounted) setState(() => _showSpeedSheet = false);
    });
  }

  // ---------------------- screenshot ----------------------
  Future<void> _takeScreenshot() async {
    if (_savingScreenshot || _state != _LoadState.ready) return;
    setState(() => _savingScreenshot = true);
    try {
      final boundaryContext = _videoBoundaryKey.currentContext;
      if (boundaryContext == null) throw Exception('فشل التقاط الصورة.');
      final boundary =
          boundaryContext.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('فشل التقاط الصورة.');
      final bytes = byteData.buffer.asUint8List();
      if (Platform.isAndroid || Platform.isIOS) {
        final result = await ImageGallerySaverPlus.saveImage(bytes,
            quality: 100, name: 'sports_player_${DateTime.now().millisecondsSinceEpoch}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    result['isSuccess'] == true ? 'تم حفظ الصورة.' : 'تعذر حفظ الصورة.')),
          );
        }
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final saved = File('${dir.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png');
        await saved.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم حفظ الصورة في:\n${saved.path}')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر التقاط صورة.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingScreenshot = false);
    }
  }

  // ---------------------- gestures ----------------------
  void _handleDoubleTapDown(TapDownDetails details) {
    if (_locked || _state != _LoadState.ready) return;
    final isLive = _session?.isLive ?? false;
    if (isLive) return;
    final width = MediaQuery.of(context).size.width;
    final isRight = details.globalPosition.dx > width / 2;
    _seekBy(Duration(seconds: isRight ? 10 : -10));
    _seekFeedbackTimer?.cancel();
    setState(() => _seekFeedback = isRight ? 'right' : 'left');
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_locked || _state != _LoadState.ready) return;
    final isLive = _session?.isLive ?? false;
    if (isLive) return;
    _swipeStart = details.globalPosition;
    _seekingFromSwipe = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_swipeStart == null || _seekingFromSwipe) return;
    final delta = details.globalPosition.dx - _swipeStart!.dx;
    if (delta.abs() > _swipeThreshold) {
      _seekingFromSwipe = true;
      final seconds = (delta / _swipeThreshold).round() * 5;
      _seekBy(Duration(seconds: seconds));
      _seekFeedbackTimer?.cancel();
      setState(() => _seekFeedback = delta > 0 ? 'right' : 'left');
      _seekFeedbackTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _seekFeedback = null);
      });
      _swipeStart = details.globalPosition;
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _swipeStart = null;
    _seekingFromSwipe = false;
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_locked || _state != _LoadState.ready) return;
    _swipeStart = details.globalPosition;
    _brightnessMode = details.globalPosition.dx >
        MediaQuery.of(context).size.width / 2;
    _lastBrightness =
        _brightnessMode ? (_muted ? 0 : _volume) : _lastBrightness;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_swipeStart == null || _brightnessMode) return;
    final height = MediaQuery.of(context).size.height;
    final delta = (_swipeStart!.dy - details.globalPosition.dy) / height;
    final newVolume = (_lastBrightness + delta * 100).clamp(0.0, 100.0);
    _setVolume(newVolume);
    _scheduleHide();
  }

  // ---------------------- sheets ----------------------
  void _openQualitySheet() {
    final session = _session;
    if (session == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (session.hasMultipleServers) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child:
                      Text('السيرفر', style: TextStyle(color: Colors.white70)),
                ),
                ...session.servers.map((server) => ListTile(
                      title: Text(server.label,
                          style: const TextStyle(color: Colors.white)),
                      trailing: server.label == _activeServer?.label
                          ? const Icon(Icons.check, color: Colors.greenAccent)
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _playServerQuality(server, server.qualities.first);
                      },
                    )),
              ],
              if (_activeServer != null &&
                  _activeServer!.qualities.length > 1) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child:
                      Text('الجودة', style: TextStyle(color: Colors.white70)),
                ),
                ..._activeServer!.qualities.map((quality) => ListTile(
                      title: Text(quality.label,
                          style: const TextStyle(color: Colors.white)),
                      trailing: quality.label == _activeQuality?.label
                          ? const Icon(Icons.check, color: Colors.greenAccent)
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _playServerQuality(_activeServer!, quality);
                      },
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---------------------- lifecycle ----------------------
  // يُستدعى كل ما يغيّر التطبيق حالته: يذهب للخلفية، يرجع للمقدمة، أو
  // يُغلق نهائياً. هذا هو الإصلاح الفعلي لمشكلة "البث يستمر بالخلفية":
  // بدون هذه الدالة، مغادرة التطبيق (زر الرئيسية أو تبديل تطبيق) لا
  // توقف الـ VideoPlayerController إطلاقاً، فيستمر الصوت يعمل بلا واجهة.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // التطبيق لم يعد ظاهراً للمستخدم (تصغير، تبديل تطبيق، أو إغلاق) —
        // نوقف التشغيل فوراً بدل ما يستمر الصوت/الفيديو بالخلفية.
        if (controller.value.isPlaying) controller.pause();
        break;
      case AppLifecycleState.resumed:
        // لا نُعيد التشغيل تلقائياً عند الرجوع — نترك للمستخدم أن يضغط
        // تشغيل بنفسه، تجنباً لتشغيل مفاجئ بالصوت بمجرد فتح التطبيق.
        break;
    }
  }

  @override
  void dispose() {
    if (identical(_activeInstance, this)) _activeInstance = null;
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _controller?.removeListener(_videoListener);
    WakelockPlus.disable();
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ---------------------- build ----------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: _toggleControls,
          onDoubleTapDown: _handleDoubleTapDown,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_state == _LoadState.ready) Center(child: _buildVideo()),
              if (_state == _LoadState.loading) _buildLoading(),
              if (_state == _LoadState.error) _buildError(),
              if (_state == _LoadState.ready && _isBuffering)
                const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              if (_seekFeedback != null)
                Align(
                  alignment: _seekFeedback == 'right'
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _seekFeedback == 'right'
                            ? Icons.forward_10
                            : Icons.replay_10,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              if (_state == _LoadState.ready && !_locked)
                AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: _buildControls(),
                  ),
                ),
              if (_state == _LoadState.ready)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _exit,
                  ),
                ),
              if (_state == _LoadState.ready)
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    icon: Icon(_locked ? Icons.lock : Icons.lock_open,
                        color: Colors.white),
                    onPressed: _toggleLock,
                  ),
                ),
              // speed badge
              if (_state == _LoadState.ready && _playbackSpeed != 1.0)
                Positioned(
                  top: 12,
                  left: 56,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideo() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final size = controller.value.size;
    final double width = size.width == 0 ? 16.0 : size.width;
    final double height = size.height == 0 ? 9.0 : size.height;
    return RepaintBoundary(
      key: _videoBoundaryKey,
      child: FittedBox(
        fit: _fit,
        child: SizedBox(
          width: width,
          height: height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 12),
          Text('جارٍ التحقق من صلاحية المشاهدة…',
              style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: _startSession,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
                if (_session != null && _session!.hasMultipleServers) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openQualitySheet,
                    icon: const Icon(Icons.dns),
                    label: const Text('تغيير السيرفر'),
                  ),
                ],
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _exit,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('رجوع'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    final isLive = _session?.isLive ?? false;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.black87],
          stops: [0, 0.5, 1],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 8, 48, 0),
            child: Row(
              children: [
                if (isLive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('مباشر',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                const Spacer(),
                if (isLive)
                  IconButton(
                    icon: const Icon(Icons.live_tv, color: Colors.white),
                    tooltip: 'القفز للبث المباشر',
                    onPressed: _jumpToLive,
                  ),
                IconButton(
                  icon: const Icon(Icons.aspect_ratio, color: Colors.white),
                  tooltip: 'وضع العرض',
                  onPressed: _toggleFit,
                ),
                IconButton(
                  icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white),
                  onPressed: _toggleMute,
                ),
                SizedBox(
                  width: 90,
                  child: Slider(
                    value: _muted ? 0 : _volume,
                    min: 0,
                    max: 100,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChanged: _setVolume,
                  ),
                ),
                if (_session != null &&
                    (_session!.hasMultipleServers ||
                        _session!.hasMultipleQualities))
                  IconButton(
                    icon: const Icon(Icons.hd, color: Colors.white),
                    onPressed: _openQualitySheet,
                  ),
                IconButton(
                  icon: const Icon(Icons.speed, color: Colors.white),
                  tooltip: 'سرعة التشغيل',
                  onPressed: _openSpeedSheet,
                ),
                IconButton(
                  icon: _savingScreenshot
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.camera_alt, color: Colors.white),
                  tooltip: 'التقاط صورة',
                  onPressed: _savingScreenshot ? null : _takeScreenshot,
                ),
              ],
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isLive)
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.replay_10, color: Colors.white),
                    onPressed: () => _seekBy(const Duration(seconds: -10)),
                  ),
                const SizedBox(width: 12),
                IconButton(
                  iconSize: 56,
                  icon: Icon(
                      _isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white),
                  onPressed: _togglePlay,
                ),
                const SizedBox(width: 12),
                if (!isLive)
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.forward_10, color: Colors.white),
                    onPressed: () => _seekBy(const Duration(seconds: 10)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                if (!isLive) ...[
                  Text(_formatDuration(_position),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _position.inMilliseconds
                          .clamp(
                              0,
                              _duration.inMilliseconds == 0
                                  ? 1
                                  : _duration.inMilliseconds)
                          .toDouble(),
                      min: 0,
                      max: _duration.inMilliseconds == 0
                          ? 1
                          : _duration.inMilliseconds.toDouble(),
                      activeColor: Colors.redAccent,
                      inactiveColor: Colors.white24,
                      onChanged: (value) => _controller
                          ?.seekTo(Duration(milliseconds: value.toInt())),
                    ),
                  ),
                  Text(_formatDuration(_duration),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ] else
                  const Spacer(),
                IconButton(
                  icon: Icon(
                      _fullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: Colors.white),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}
