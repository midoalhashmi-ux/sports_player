/// يستخرج معرّف فيديو يوتيوب (11 حرف) من رابط، بدون أي اتصال خارجي أو
/// استخراج لرابط بث فعلي — المعرّف فقط يُمرَّر لمشغل يوتيوب الرسمي
/// (YoutubeWatchScreen) الذي يتولى التشغيل عبر IFrame Player API.
///
/// يدعم:
/// - youtube.com/watch?v=ID
/// - youtu.be/ID
/// - youtube.com/embed/ID
/// - youtube.com/shorts/ID
/// - youtube.com/live/ID
/// - معرّف مباشر (11 حرف) بدون رابط
///
/// لا يدعم عمداً روابط بث القناة بدون معرّف (مثل /@channel/live) لأن
/// اكتشافها يتطلب جلب صفحة القناة (طلب شبكة إضافي خارج API الرسمي) —
/// لو احتجتها لاحقاً، القناة تُحدَّد بمعرّف الفيديو الحالي يدوياً من
/// لوحة التحكم بدل الاكتشاف التلقائي.
class YoutubeIdExtractor {
  static final RegExp _directIdPattern = RegExp(
    r'(?:youtu\.be/|youtube(?:-nocookie)?\.com/(?:watch\?v=|embed/|shorts/|live/|v/))([A-Za-z0-9_-]{11})',
  );

  static final RegExp _watchVParamPattern =
      RegExp(r'[?&]v=([A-Za-z0-9_-]{11})');

  static final RegExp _bareIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// يرجع معرّف الفيديو، أو null لو الرابط غير مدعوم/غير صالح.
  static String? extract(String urlOrId) {
    final trimmed = urlOrId.trim();
    if (trimmed.isEmpty) return null;

    if (_bareIdPattern.hasMatch(trimmed)) return trimmed;

    final direct = _directIdPattern.firstMatch(trimmed);
    if (direct != null) return direct.group(1);

    final watchV = _watchVParamPattern.firstMatch(trimmed);
    if (watchV != null) return watchV.group(1);

    return null;
  }
}
