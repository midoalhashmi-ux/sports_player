import 'package:firebase_core/firebase_core.dart';

/// إعدادات Firebase الفعلية لمشروع sports-stream-app
/// تم توليدها يدوياً من google-services.json (تطبيق Android فقط)
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDDo8Hs253YOOfmYg863UUTnlfE-KNyG5s',
    appId: '1:207449859236:android:ebe996c8c5836959ceb231',
    messagingSenderId: '207449859236',
    projectId: 'sports-stream-app-36a7a',
    storageBucket: 'sports-stream-app-36a7a.firebasestorage.app',
  );
}
