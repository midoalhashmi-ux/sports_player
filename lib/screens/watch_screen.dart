import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/channel_source_resolver.dart';
import '../services/stream_models.dart';
import '../services/youtube_resolver.dart';

enum _LoadState { loading, error, ready }

class WatchScreen extends StatefulWidget {
  /// معرّف قناة مُدارة من لوحة التحكم (المسار الآمن المعتاد).
  final String? channelId;

  /// رابط خارجي أرسله المستخدم مباشرة (مثلاً من شاشة "Add URL").
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

class _WatchScreenState extends State<WatchScreen> {
  late final Player _player;
  late final VideoController _videoController;

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

  // عناصر تحكم إضافية (القسم 2)
  bool _locked = false;
  BoxFit _fit = BoxFit.contain;
  String? _seekFeedback; // 'left' أو 'right' لحظة النقر المزدوج
  Timer? _seekFeedbackTimer;

  StreamSubscription? _playingSub;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _errorSub;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _bindPlayerStreams();
    _startSession();
    _scheduleHide();
  }

  void _bindPlayerStreams() {
    _playingSub = _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });
    _positionSub = _player.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = _player.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _errorSub = _player.stream.error.listen((error) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'تعذر تشغيل رابط البث. جرّب مرة أخرى أو غيّر السيرفر.';
      });
    });
  }

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

  Future<void> _playServerQuality(
      StreamServerOption server, StreamQuality quality) async {
    setState(() {
      _state = _LoadState.loading;
      _activeServer = server;
      _activeQuality = quality;
    });
    try {
      await _player.open(Media(quality.url, httpHeaders: _headers));
      await _player.play();
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
    _isPlaying ? _player.pause() : _player.play();
    _scheduleHide();
  }

  void _seekBy(Duration delta) {
    final target = _position + delta;
    _player.seek(target < Duration.zero ? Duration.zero : target);
    _scheduleHide();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _player.setVolume(_muted ? 0 : _volume);
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      _muted = value == 0;
    });
    _player.setVolume(value);
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
    if (_duration > Duration.zero) {
      _player.seek(_duration);
    }
    if (!_isPlaying) _player.play();
    _scheduleHide();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    if (_locked || _state != _LoadState.ready) return;
    final isLive = _session?.isLive ?? false;
    if (isLive) return; // النقر المزدوج للتقديم/الترجيع متاح فقط للفيديو العادي
    final width = MediaQuery.of(context).size.width;
    final isRight = details.globalPosition.dx > width / 2;
    _seekBy(Duration(seconds: isRight ? 10 : -10));
    _seekFeedbackTimer?.cancel();
    setState(() => _seekFeedback = isRight ? 'right' : 'left');
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

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
                  child: Text('السيرفر', style: TextStyle(color: Colors.white70)),
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
                  child: Text('الجودة', style: TextStyle(color: Colors.white70)),
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

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    WakelockPlus.disable();
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: _toggleControls,
          onDoubleTapDown: _handleDoubleTapDown,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_state == _LoadState.ready)
                Center(
                    child: Video(
                        controller: _videoController,
                        fit: _fit,
                        controls: NoVideoControls)),
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
              if (_state == _LoadState.ready && !_locked)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
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
            ],
          ),
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
                  onPressed: () => Navigator.of(context).maybePop(),
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
                      onChanged: (value) =>
                          _player.seek(Duration(milliseconds: value.toInt())),
                    ),
                  ),
                  Text(_formatDuration(_duration),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ] else
                  const Spacer(),
                IconButton(
                  icon: Icon(
                      _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
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
