import 'package:firebase_core/firebase_core.dart';

/// إعدادات Firebase الفعلية لتطبيق المشغل — تطبيق Android مسجّل باسم حزمة
/// مستقل (com.midoalhashmi.zoltrastream) داخل نفس مشروع Firebase المستخدم
/// في تطبيق المحتوى (sports-stream-app-36a7a). القيم مأخوذة من
/// google-services.json الذي تم تحميله بعد تسجيل التطبيق في Firebase Console
/// بتاريخ 2026-08-25.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDDo8Hs253YOOfmYg863UUTnlfE-KNyG5s',
    appId: '1:207449859236:android:bf1f58d71ec65af4ceb231',
    messagingSenderId: '207449859236',
    projectId: 'sports-stream-app-36a7a',
    storageBucket: 'sports-stream-app-36a7a.firebasestorage.app',
  );
}

