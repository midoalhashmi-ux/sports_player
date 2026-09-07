import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/secure_stream_service.dart';

class WatchScreen extends StatefulWidget {
  final ChannelModel channel;
  const WatchScreen({super.key, required this.channel});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;
  bool _isBuffering = false;
  bool _bufferIndicatorVisible = false;
  Timer? _bufferIndicatorTimer;
  Duration _lastPosition = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStream();
  }

  Future<void> _loadStream() async {
    _bufferIndicatorTimer?.cancel();
    _chewieController?.dispose();
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _isBuffering = false;
      _bufferIndicatorVisible = false;
      _lastPosition = Duration.zero;
      _error = null;
    });

    final url =
        await SecureStreamService.getTemporaryStreamUrl(widget.channel.id);

    if (!mounted) return;
    if (url == null) {
      setState(() {
        _loading = false;
        _error = 'تعذر جلب رابط البث حالياً. حاول لاحقاً.';
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تهيئة مشغل الفيديو. تحقق من الاتصال وحاول مرة أخرى.';
      });
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }
    _videoController = controller;
    controller.addListener(_videoListener);
    _chewieController = ChewieController(
      videoPlayerController: controller,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: Theme.of(context).colorScheme.primary,
      ),
    );

    setState(() => _loading = false);
  }

  void _videoListener() {
    final controller = _videoController;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (value.hasError) return;
    final positionAdvanced = value.isPlaying && value.position > _lastPosition;
    _lastPosition = value.position;
    final buffering = value.isBuffering && !positionAdvanced;
    if (_isBuffering == buffering) return;
    setState(() {
      _isBuffering = buffering;
      _bufferIndicatorVisible = buffering;
    });
    _bufferIndicatorTimer?.cancel();
    if (buffering) {
      _bufferIndicatorTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _bufferIndicatorVisible = false);
      });
    } else {
      _bufferIndicatorTimer = null;
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _bufferIndicatorTimer?.cancel();
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.title)),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _buildPlayerArea(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.channel.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(widget.channel.subtitle,
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerArea() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 40),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadStream,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_chewieController != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Chewie(controller: _chewieController!),
          if (_isBuffering && _bufferIndicatorVisible)
            const IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
