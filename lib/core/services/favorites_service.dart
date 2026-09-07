import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تخزين محلي (على الجهاز) لمعرّفات القنوات المفضلة.
/// لا يحتاج حساب مستخدم أو اتصال بالخادم — يعمل حتى بدون إنترنت.
class FavoritesService {
  static const _prefsKey = 'favorite_channel_ids';

  /// القيمة الحالية لمعرّفات القنوات المفضلة. أي واجهة تستمع لها
  /// (عبر ValueListenableBuilder) تتحدث تلقائياً عند أي إضافة/إزالة.
  static final ValueNotifier<Set<String>> favorites =
      ValueNotifier<Set<String>>(<String>{});

  static bool _loaded = false;

  /// يُستحسن استدعاؤها مرة عند بدء التطبيق (main.dart) حتى تكون
  /// المفضلة جاهزة قبل رسم أول شاشة. آمنة الاستدعاء أكثر من مرة.
  static Future<void> init() => _ensureLoaded();

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    favorites.value = (prefs.getStringList(_prefsKey) ?? const []).toSet();
    _loaded = true;
  }

  static Future<bool> isFavorite(String channelId) async {
    await _ensureLoaded();
    return favorites.value.contains(channelId);
  }

  static Future<void> toggleFavorite(String channelId) async {
    await _ensureLoaded();
    final updated = Set<String>.from(favorites.value);
    if (!updated.remove(channelId)) {
      updated.add(channelId);
    }
    favorites.value = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, updated.toList());
  }
}
