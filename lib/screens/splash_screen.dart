import 'dart:async';

import 'package:flutter/material.dart';

import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;

      // إذا فُتحت شاشة أخرى فوق شاشة البداية في هذه الأثناء (مثلاً شاشة
      // المشاهدة بسبب رابط قادم من تطبيق المحتوى)، فإن هذه الشاشة لم تعد
      // "الحالية" على المكدس. في هذه الحالة يجب ألا ننتقل إطلاقاً، وإلا
      // سنستبدل الشاشة الظاهرة فوقها بشاشة "إضافة روابط" خطأً.
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv, size: 72, color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Sport Player 2026',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
