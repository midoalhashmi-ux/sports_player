import 'package:cloud_firestore/cloud_firestore.dart';

/// يقرأ نصوص "الشروط والأحكام" و"سياسة الخصوصية" من settings/legal
/// في Firestore حتى تتعدّل من لوحة التحكم بدون تحديث التطبيق.
class LegalService {
  static Future<String> fetchText(String field) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('legal')
          .get();
      final text = snapshot.data()?[field] as String?;
      if (text != null && text.trim().isNotEmpty) return text;
      return 'لم يتم إضافة هذا النص بعد.';
    } catch (_) {
      return 'تعذر تحميل النص، تحقق من الإنترنت وحاول مرة أخرى.';
    }
  }
}
