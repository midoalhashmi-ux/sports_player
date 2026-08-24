import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/watch_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class PlayerApp extends StatefulWidget {
  const PlayerApp({super.key});
  @override
  State<PlayerApp> createState() => _PlayerAppState();
}

class _PlayerAppState extends State<PlayerApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  String? _pendingChannelId;

  @override
  void initState() {
    super.initState();
    _listenForLinks();
  }

  Future<void> _listenForLinks() async {
    final initialUri = await _appLinks.getInitialAppLink();
    if (initialUri != null) _handleUri(initialUri);
    _linkSub = _appLinks.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  void _handleUri(Uri uri) {
    final channelId = uri.queryParameters['channelId'];
    if (channelId == null || channelId.isEmpty) return;
    setState(() => _pendingChannelId = channelId);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مشغل البث',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      locale: const Locale('ar'),
      home: _pendingChannelId == null
          ? const _WaitingForChannelScreen()
          : WatchScreen(
              key: ValueKey(_pendingChannelId),
              channelId: _pendingChannelId!,
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
