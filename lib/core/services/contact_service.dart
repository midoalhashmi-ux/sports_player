import 'package:cloud_firestore/cloud_firestore.dart';

/// يرسل رسائل "تواصل معنا" و"الإبلاغ عن رابط معطوب" مباشرة إلى مجموعة
/// contactMessages في Firestore (وليس بريد إلكتروني) حتى تظهر لاحقاً
/// في لوحة التحكم. الكتابة مسموحة للجميع بدون تسجيل دخول (انظر
/// firestore.rules)، والقراءة محصورة على حساب لوحة التحكم فقط.
class ContactService {
  static Future<void> sendMessage({
    required String type, // 'general' أو 'broken_link'
    required String message,
    String? channelInfo,
  }) async {
    await FirebaseFirestore.instance.collection('contactMessages').add({
      'type': type,
      'message': message.trim(),
      'channelInfo': channelInfo?.trim().isNotEmpty == true ? channelInfo!.trim() : null,
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
