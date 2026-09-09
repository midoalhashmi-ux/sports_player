import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// سجل تشخيصي لجلسة مشاهدة واحدة (شاشة WatchScreen)، يُستخدم فقط لتصدير
/// التفاصيل الدقيقة لتحليل مشاكل "المصدر يعمل في صفحة الويب فقط ولا
/// يلتقطه المشغل الأصلي" ونحوها.
///
/// يُبنى بالذاكرة أثناء الجلسة، ويُستبدل تلقائياً عند بدء جلسة جديدة (فتح
/// قناة جديدة). عند نهاية الجلسة (dispose على شاشة المشاهدة) يُحفظ السجل
/// كاملاً على القرص فوراً — هذا مهم لأن هذا التطبيق غالباً يُفتح عبر رابط
/// عميق من تطبيق المحتوى مباشرة إلى شاشة المشاهدة، متجاوزاً الشاشة
/// الرئيسية كلياً، وزر الخروج من هناك يُغلق تطبيق المشغل بالكامل. بدون
/// حفظ فوري على القرص، يضيع السجل بمجرد إغلاق التطبيق قبل ما يوصل
/// المستخدم لزر "تصدير السجل" بالشاشة الرئيسية في تشغيلة لاحقة منفصلة.
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

  /// ينهي الجلسة الحالية ويحفظ السجل كاملاً على القرص فوراً، بدل انتظار
  /// ضغط زر التصدير — راجع تعليق الكلاس أعلاه لسبب أهمية هذا.
  void endSession(String result) {
    if (_startedAt == null) return;
    _append('SESSION_END', result);
    unawaited(_persistToDisk());
  }

  void _append(String phase, String details) {
    if (_lines.length >= _maxLines) return;
    final started = _startedAt;
    final elapsed = started == null
        ? '0.000'
        : (DateTime.now().difference(started).inMilliseconds / 1000)
            .toStringAsFixed(3);
    _lines.add('[+${elapsed}s] $phase: $details');
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
