import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'firebase_options.dart';
import 'screens/watch_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const _BootApp());
}

class _BootApp extends StatefulWidget {
  const _BootApp();
  @override
  State<_BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<_BootApp> {
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorApp(error: _error!);
    if (!_ready) return const _LoadingApp();
    return const PlayerApp();
  }
}

class _LoadingApp extends StatelessWidget {
  const _LoadingApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
}

class _ErrorApp extends StatelessWidget {
  final String error;
  const _ErrorApp({required this.error});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('تعذر بدء تطبيق المشغل.\n\n$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
      );
}

class _PendingPlay {
  final String? channelId;
  final String? url;
  final bool isYoutube;
  const _PendingPlay({this.channelId, this.url, this.isYoutube = false});
}

class PlayerApp extends StatefulWidget {
  const PlayerApp({super.key});
  @override
  State<PlayerApp> createState() => _PlayerAppState();
}

class _PlayerAppState extends State<PlayerApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  _PendingPlay? _pending;

  @override
  void initState() {
    super.initState();
    _listenForLinks();
  }

  Future<void> _listenForLinks() async {
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) _handleUri(initialUri);
    _linkSub = _appLinks.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  void _handleUri(Uri uri) {
    final channelId = uri.queryParameters['channelId'];
    final url = uri.queryParameters['url'];
    final type = uri.queryParameters['type'];

    if ((channelId == null || channelId.isEmpty) &&
        (url == null || url.isEmpty)) {
      return;
    }

    setState(() => _pending = _PendingPlay(
          channelId:
              (channelId != null && channelId.isNotEmpty) ? channelId : null,
          url: (url != null && url.isNotEmpty) ? Uri.decodeFull(url) : null,
          isYoutube: type == 'youtube',
        ));
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return MaterialApp(
      title: 'مشغل البث',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      locale: const Locale('ar'),
      home: pending == null
          ? const _WaitingForChannelScreen()
          : WatchScreen(
              key: ValueKey(pending.channelId ?? pending.url),
              channelId: pending.channelId,
              externalUrl: pending.url,
              externalIsYoutube: pending.isYoutube,
            ),
    );
  }
}

class _WaitingForChannelScreen extends StatelessWidget {
  const _WaitingForChannelScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.live_tv, size: 56, color: Colors.white54),
                SizedBox(height: 12),
                Text(
                  'افتح قناة من تطبيق المحتوى ليبدأ التشغيل هنا تلقائياً.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      );
}
