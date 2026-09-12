import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, per channel, the CDN host of the last stream candidate that
/// actually succeeded a native playback trial. Exact stream URLs are
/// frequently session/token-bound and reused across visits only by luck, but
/// the CDN host a given source site relays through is stable — so on the
/// next visit to the same channel, a freshly discovered candidate on that
/// host is tried first instead of waiting behind unrelated candidates.
class PreferredServerService {
  static const _keyPrefix = 'preferred_server_host_v1_';

  static Future<String?> loadHost(String channelId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_keyPrefix$channelId');
    } catch (_) {
      return null;
    }
  }

  static Future<void> rememberHost(String channelId, String host) async {
    if (host.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix$channelId', host);
    } catch (_) {}
  }
}
