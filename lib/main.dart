import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/watch_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

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
  Uri? _initialUri;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // نبدأ تهيئة Firebase وفي نفس الوقت نتحقق هل التطبيق فُتح عبر رابط
      // قادم من تطبيق المحتوى — قبل بناء أي واجهة. بهذا الشكل نقرر من أول
      // لحظة: هل نعرض شاشة المشاهدة مباشرة كشاشة وحيدة (بدون شاشة بداية
      // أو رئيسية خلفها إطلاقاً)، أو نمر بمسار شاشة البداية العادي.
      final firebaseFuture =
          Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      final linkFuture = AppLinks().getInitialLink();

      await firebaseFuture;
      final initialUri = await linkFuture;

      if (mounted) {
        setState(() {
          _ready = true;
          _initialUri = initialUri;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorApp(error: _error!);
    if (!_ready) return const _LoadingApp();
    return PlayerApp(initialUri: _initialUri);
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
  final Uri? initialUri;
  const PlayerApp({super.key, this.initialUri});
  @override
  State<PlayerApp> createState() => _PlayerAppState();
}

class _PlayerAppState extends State<PlayerApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    // نستمع فقط للروابط التي تصل أثناء عمل التطبيق (رابط الإقلاع الأول
    // تمت معالجته مسبقاً في _BootAppState قبل بناء الواجهة).
    _linkSub = _appLinks.uriLinkStream.listen(_handleRuntimeUri, onError: (_) {});
  }

  // يبني شاشة المشاهدة من رابط، أو null إن لم يكن الرابط يحمل بيانات بث.
  Widget? _watchScreenForUri(Uri uri) {
    final channelId = uri.queryParameters['channelId'];
    final url = uri.queryParameters['url'];
    final type = uri.queryParameters['type'];

    if ((channelId == null || channelId.isEmpty) &&
        (url == null || url.isEmpty)) {
      return null;
    }

    return WatchScreen(
      key: ValueKey(channelId ?? url),
      channelId:
          (channelId != null && channelId.isNotEmpty) ? channelId : null,
      externalUrl:
          (url != null && url.isNotEmpty) ? Uri.decodeFull(url) : null,
      externalIsYoutube: type == 'youtube',
    );
  }

  void _handleRuntimeUri(Uri uri) {
    final screen = _watchScreenForUri(uri);
    if (screen == null) return;

    // نفرّغ المكدس بالكامل ونجعل شاشة المشاهدة هي الشاشة الوحيدة — تماماً
    // مثل حالة فتح التطبيق مباشرة عبر رابط. بهذا الشكل يبقى زر الخروج
    // متسقاً دائماً: يغلق تطبيق المشغل بالكامل ويرجع المستخدم لتطبيق
    // المحتوى، بدل ما "يعلّق" على شاشة داخلية للمشغل لم يكن يفترض بها
    // الظهور أصلاً.
    // نستخدم انتقالاً فورياً بلا أنيميشن (بدل MaterialPageRoute الافتراضي)
    // حتى لا تبقى شاشة المشاهدة القديمة ظاهرة/مسموعة خلال مدة الأنيميشن
    // فوق الشاشة الجديدة عند تبديل القناة والمشغل يعمل بالفعل في الخلفية.
    navigatorKey.currentState?.pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialUri = widget.initialUri;
    final initialWatchScreen =
        initialUri != null ? _watchScreenForUri(initialUri) : null;

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'BinSheikh Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      locale: const Locale('ar'),
      // لا توجد شاشة بداية (Splash) في تطبيق المشغل إطلاقاً — شاشة
      // البداية موجودة فقط في التطبيق العادي (BinSheikh). إذا فُتح
      // المشغل عبر رابط من تطبيق المحتوى، شاشة المشاهدة هي الشاشة
      // الوحيدة مباشرة، وإلا يذهب مباشرة لشاشة التصفح الداخلية للمشغل.
      home: initialWatchScreen ?? const HomeScreen(),
    );
  }
}
