import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// سجل تشخيصي لجلسة مشاهدة واحدة (شاشة WatchScreen)، يُستخدم فقط لتصدير
/// التفاصيل الدقيقة لتحليل مشاكل "المصدر يعمل في صفحة الويب فقط ولا
/// يلتقطه المشغل الأصلي" ونحوها.
///
/// يُبنى بالذاكرة أثناء الجلسة، ويُستبدل تلقائياً عند بدء جلسة جديدة (فتح
/// قناة جديدة). كل سطر تسجيل يُكتب فوراً على القرص لحظة إضافته (وليس فقط
/// عند dispose) — هذا مهم لأن هذا التطبيق غالباً يُفتح عبر رابط عميق من
/// تطبيق المحتوى مباشرة إلى شاشة المشاهدة، متجاوزاً الشاشة الرئيسية
/// كلياً، وقد تنتهي العملية بإغلاق مفاجئ (رجوع يُنهي النشاط، أو تبديل
/// شاشة مشاهدة بأخرى بسرعة عند بداية التشغيل) لا يُتاح فيه لـ dispose()
/// وقت كافٍ ليكتمل. الكتابة اللحظية تضمن بقاء آخر حالة معروفة محفوظة على
/// القرص مهما كان سبب/توقيت انتهاء الجلسة.
class SessionLogService {
  SessionLogService._();
  static final SessionLogService instance = SessionLogService._();

  static const int _maxLines = 4000;
  static const String _fileName = 'sports_player_debug_log.txt';

  final List<String> _lines = [];
  DateTime? _startedAt;

  bool get hasLog => _lines.isNotEmpty;

  /// يبدأ جلسة تسجيل جديدة ويمسح أي سجل سابق بالذاكرة فوراً.
  void startSession(String label) {
    _lines.clear();
    _startedAt = DateTime.now();
    _append('SESSION_START', label);
  }

  void log(String phase, [String details = '']) {
    if (_startedAt == null) return; // لا تسجيل قبل بدء جلسة
    _append(phase, details);
  }

  void endSession(String result) {
    if (_startedAt == null) return;
    _append('SESSION_END', result);
  }

  void _append(String phase, String details) {
    if (_lines.length >= _maxLines) return;
    final started = _startedAt;
    final elapsed = started == null
        ? '0.000'
        : (DateTime.now().difference(started).inMilliseconds / 1000)
            .toStringAsFixed(3);
    _lines.add('[+${elapsed}s] $phase: $details');
    // كتابة لحظية بأفضل مجهود — راجع تعليق الكلاس أعلاه لسبب أهميتها.
    unawaited(_persistToDisk());
  }

  Future<File> _logFile() async {
    // Application Documents أكثر ثباتاً من المجلد المؤقت، الذي قد يُفرَّغ
    // من نظام التشغيل بين تشغيلتين منفصلتين للتطبيق بدون إشعار.
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> _persistToDisk() async {
    try {
      final file = await _logFile();
      await file.writeAsString(_lines.join('\n'));
    } catch (_) {
      // أفضل مجهود فقط — فشل الحفظ لا يجب أن يؤثر على تشغيل الفيديو.
    }
  }

  /// يكتب السجل الحالي كملف نصي ويُرجع مساره. لو الجلسة الحالية بالذاكرة
  /// فاضية (تشغيلة جديدة للتطبيق بعد إغلاقه كلياً)، يرجع آخر سجل محفوظ
  /// على القرص من جلسة سابقة إن وُجد، بدل الإبلاغ بعدم وجود سجل رغم أن
  /// المستخدم شاهد قناة فعلاً قبل قليل.
  Future<File?> exportAsTxt() async {
    final file = await _logFile();
    if (_lines.isNotEmpty) {
      await _persistToDisk();
      return file;
    }
    return (await file.exists()) ? file : null;
  }
}
