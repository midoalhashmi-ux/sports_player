class PlayerSettings {
  final String deepLinkScheme;
  final String androidPackage;
  final String storeUrl;

  const PlayerSettings({
    required this.deepLinkScheme,
    required this.androidPackage,
    required this.storeUrl,
  });

  factory PlayerSettings.fromMap(Map<String, dynamic>? map) {
    return PlayerSettings(
      deepLinkScheme: map?['deepLinkScheme'] ?? 'sportsplayer',
      androidPackage: map?['androidPackage'] ?? '',
      storeUrl: map?['storeUrl'] ?? '',
    );
  }
}
