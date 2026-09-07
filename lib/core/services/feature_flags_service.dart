import 'package:cloud_firestore/cloud_firestore.dart';

class FeatureFlags {
  final bool matchAlerts;
  final bool liveScoreTab;
  final bool backgroundAudio;
  final bool liveChat;

  const FeatureFlags({
    this.matchAlerts = false,
    this.liveScoreTab = false,
    this.backgroundAudio = false,
    this.liveChat = false,
  });

  factory FeatureFlags.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const FeatureFlags();
    return FeatureFlags(
      matchAlerts: map['matchAlerts'] ?? false,
      liveScoreTab: map['liveScoreTab'] ?? false,
      backgroundAudio: map['backgroundAudio'] ?? false,
      liveChat: map['liveChat'] ?? false,
    );
  }
}

class FeatureFlagsService {
  static Stream<FeatureFlags> watchFlags() {
    return FirebaseFirestore.instance
        .collection('settings')
        .doc('features')
        .snapshots()
        .map((doc) => FeatureFlags.fromMap(doc.data()));
  }
}
