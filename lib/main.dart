import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/services/favorites_service.dart';
import 'core/services/app_settings_service.dart';
import 'core/services/app_update_service.dart';
import 'features/home/home_shell.dart';
import 'features/settings/app_update_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'theme/dynamic_theme_service.dart';

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

  // شاشة البداية (Splash) موجودة في هذا التطبيق فقط (BinSheikh) — تطبيق
  // المشغل لا يعرض أي شاشة بداية إطلاقاً. نضمن ظهورها لمدة كافية للعلامة
  // التجارية حتى لو انتهت تهيئة Firebase بشكل أسرع من ذلك.
  static const _minSplashDuration = Duration(milliseconds: 1400);
  bool _minSplashElapsed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    Future.delayed(_minSplashDuration, () {
      if (mounted) setState(() => _minSplashElapsed = true);
    });
  }

  Future<void> _initialize() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await FavoritesService.init();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorApp(error: _error!);
    if (!_ready || !_minSplashElapsed) return const _SplashApp();
    return const SportsApp();
  }
}

class _SplashApp extends StatelessWidget {
  const _SplashApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF0B1120),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.live_tv, size: 72, color: Color(0xFF38BDF8)),
                SizedBox(height: 16),
                Text(
                  'BinSheikh',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 24),
                CircularProgressIndicator(color: Color(0xFF38BDF8)),
              ],
            ),
          ),
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
          backgroundColor: const Color(0xFF0B1120),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('تعذر بدء خدمة المحتوى.\n\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
      );
}

class SportsApp extends StatelessWidget {
  const SportsApp({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<DynamicThemeSettings>(
        stream: DynamicThemeService.watchTheme(),
        builder: (context, snapshot) => MaterialApp(
          title: 'BinSheikh',
          debugShowCheckedModeBanner: false,
          theme: snapshot.data?.toThemeData() ?? AppTheme.fallback,
          locale: const Locale('ar'),
          // بدون هذين السطرين، MaterialApp لا يجد أي مندوب ترجمة (Delegate)
          // مطابق للعربية فيرجع فعلياً للإنجليزية كلغة تحديد اتجاه فعلي، وهذا
          // هو سبب ظهور الشاشة كاملة باتجاه LTR (من اليسار لليمين) رغم أن
          // النصوص عربية — ومنه ظهور شعار/اسم الدوري يسار الشاشة بدل يمينها.
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ar')],
          home: const _UpdateGate(),
        ),
      );
}

class _UpdateGate extends StatefulWidget {
  const _UpdateGate();

  @override
  State<_UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<_UpdateGate> {
  AppUpdateInfo? _info;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final info = await AppUpdateService.fetchUpdateInfo();
    if (!mounted) return;
    setState(() {
      _info = info;
      _busy = false;
    });

    if (info.forceUpdate && info.minVersion != null && info.minVersion!.isNotEmpty) {
      final current = const String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');
      final currentParts = current.split('.').map(int.tryParse).toList();
      final minParts = info.minVersion!.split('.').map(int.tryParse).toList();

      final needsUpdate = currentParts.length == minParts.length &&
          minParts[0] != null &&
          currentParts[0] != null &&
          minParts[1] != null &&
          currentParts[1] != null &&
          minParts[2] != null &&
          currentParts[2] != null &&
          (currentParts[0]! > minParts[0]! ||
              (currentParts[0] == minParts[0] &&
                  currentParts[1]! > minParts[1]!) ||
              (currentParts[0] == minParts[0] &&
                  currentParts[1] == minParts[1] &&
                  currentParts[2]! > minParts[2]!)) == false;

      if (needsUpdate) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AppUpdateDialog(
              info: info,
              onDismiss: info.forceUpdate ? null : () => Navigator.of(context).pop(),
              onUpdate: () async {
                Navigator.of(context).pop();
                final settings = await AppSettingsService.fetchSettings();
                if (!mounted) return;
                if (settings.appStoreUrl.trim().isNotEmpty) {
                  await launchUrl(Uri.parse(settings.appStoreUrl.trim()), mode: LaunchMode.externalApplication);
                }
              },
            ),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0B1120),
          body: const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
        ),
      );
    }
    return const HomeShell();
  }
}
