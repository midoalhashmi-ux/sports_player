import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// سجل تشخيصي مؤقت لجلسة مشاهدة واحدة (شاشة WatchScreen)، يُستخدم فقط
/// لتصدير التفاصيل الدقيقة لتحليل مشاكل "المصدر يعمل في صفحة الويب فقط
/// ولا يلتقطه المشغل الأصلي" ونحوها.
///
/// يُخزَّن بالذاكرة فقط طوال الجلسة الحالية (بدون كتابة مستمرة على القرص)،
/// ويُستبدل تلقائياً عند بدء جلسة جديدة (فتح قناة جديدة). التصدير الفعلي
/// لملف نصي يحدث فقط عند طلب المستخدم من زر التشخيص في القائمة الجانبية.
class SessionLogService {
  SessionLogService._();
  static final SessionLogService instance = SessionLogService._();

  static const int _maxLines = 4000;

  final List<String> _lines = [];
  DateTime? _startedAt;

  bool get hasLog => _lines.isNotEmpty;

  /// يبدأ جلسة تسجيل جديدة ويمسح أي سجل سابق فوراً.
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
  }

  /// يكتب السجل الحالي كملف نصي ويُرجع مساره، أو null إن لم يوجد سجل بعد.
  Future<File?> exportAsTxt() async {
    if (_lines.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/sports_player_debug_log.txt');
    return file.writeAsString(_lines.join('\n'));
  }
}
