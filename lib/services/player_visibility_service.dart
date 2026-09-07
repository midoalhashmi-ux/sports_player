import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads the optional player-page visibility switch from settings/player.
///
/// The field is intentionally optional and defaults to true so existing
/// installations keep their current WebView behaviour until the dashboard
/// setting is explicitly changed.
class PlayerVisibilityService {
  PlayerVisibilityService._();

  static Future<bool> loadShowSourcePage() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('player')
          .get();
      final value = snapshot.data()?['showSourcePage'];
      return value is bool ? value : true;
    } catch (_) {
      return true;
    }
  }
}