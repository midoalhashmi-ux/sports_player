import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/player_settings.dart';

class PlayerService {
  static Stream<PlayerSettings> watchSettings() {
    return FirebaseFirestore.instance
        .collection('settings')
        .doc('player')
        .snapshots()
        .map((doc) => PlayerSettings.fromMap(doc.data()));
  }

  /// يرسل معرف القناة فقط إلى المشغل؛ لا يرسل رابط البث أو التوكن.
  static Future<bool> openChannel({
    required String channelId,
    required PlayerSettings settings,
  }) {
    final uri = Uri(
      scheme: settings.deepLinkScheme,
      host: 'play',
      queryParameters: {'channelId': channelId},
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> openStore(PlayerSettings settings) async {
    final url = settings.storeUrl;
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
