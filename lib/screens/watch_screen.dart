import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/channel_source_resolver.dart';

enum _LoadState { loading, error, ready }

class WatchScreen extends StatefulWidget {
  final String channelId;
  const WatchScreen({super.key, required this.channelId});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  VideoPlayerController? _controller;
  _LoadState _state = _LoadState.loading;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  Future<void> _startSession() async {
    setState(() => _state = _LoadState.loading);

    final session = await ChannelSourceResolver.resolve(widget.channelId);
    if (!mounted) return;

    if (!session.ok) {
      setState(() {
        _state = _LoadState.error;
        _errorMessage = session.errorMessage ?? 'تعذر تشغيل البث.';
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(session.url!),
      formatHint: VideoFormat.hls,
    );

    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _state = _LoadState.ready;
      });
      controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'تعذر تشغيل رابط البث. جرّب مرة أخرى.';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: _buildBody()),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text('جارٍ التحقق من صلاحية المشاهدة…',
                style: TextStyle(color: Colors.white70)),
          ],
        );
      case _LoadState.error:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _startSession,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        );
      case _LoadState.ready:
        final controller = _controller!;
        return AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: GestureDetector(
            onTap: () => setState(() {
              controller.value.isPlaying
                  ? controller.pause()
                  : controller.play();
            }),
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),
                if (!controller.value.isPlaying)
                  const Icon(Icons.play_arrow,
                      size: 64, color: Colors.white70),
              ],
            ),
          ),
        );
    }
  }
}
