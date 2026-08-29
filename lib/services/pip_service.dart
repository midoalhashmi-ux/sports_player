import 'package:flutter/services.dart';

/// جسر بسيط لدعم "صورة داخل صورة" (Picture-in-Picture) عبر قناة ميثود مع
/// الكود الأصلي لأندرويد (MainActivity.kt). غير مدعوم على iOS حالياً —
/// [isSupported] يرجع false هناك تلقائياً (فشل القناة يُعامل كعدم دعم).
///
/// التصميم متعمّد: PiP يُفعَّل فقط بضغطة صريحة من المستخدم على زر مخصص
/// داخل شاشة المشاهدة، وليس تلقائياً عند كل خروج للخلفية — حتى لا نغيّر
/// السلوك الحالي (إيقاف الصوت فوراً عند الخروج للخلفية) لكل من لا يستخدم
/// PiP فعلياً.
class PipService {
  PipService._();
  static final PipService instance = PipService._();

  static const _channel = MethodChannel('sports_player/pip');

  bool? _supportedCache;
  void Function(bool isInPip)? onPipModeChanged;

  bool _handlerAttached = false;
  void _ensureHandlerAttached() {
    if (_handlerAttached) return;
    _handlerAttached = true;
    _channel.setMethodCallHandler(_handleCall);
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method == 'onPipModeChanged') {
      onPipModeChanged?.call(call.arguments as bool);
    }
  }

  /// يتحقق هل الجهاز/النظام يدعم PiP أصلاً (أندرويد 8+ فقط). يُخزَّن
  /// الناتج لأنه لا يتغيّر خلال حياة التطبيق، فلا داعي لاستدعاء القناة
  /// الأصلية أكثر من مرة.
  Future<bool> isSupported() async {
    if (_supportedCache != null) return _supportedCache!;
    _ensureHandlerAttached();
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      _supportedCache = result ?? false;
    } catch (_) {
      // القناة غير موجودة أصلاً (مثلاً iOS) — نعتبره غير مدعوم بدل رمي خطأ
      _supportedCache = false;
    }
    return _supportedCache!;
  }

  /// يطلب الدخول الفعلي لوضع PiP بنسبة عرض/ارتفاع الفيديو الحالي. يرجع
  /// true لو نجح الدخول فعلاً.
  Future<bool> enter({int aspectWidth = 16, int aspectHeight = 9}) async {
    _ensureHandlerAttached();
    try {
      final result = await _channel.invokeMethod<bool>('enter', {
        'aspectWidth': aspectWidth,
        'aspectHeight': aspectHeight,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
