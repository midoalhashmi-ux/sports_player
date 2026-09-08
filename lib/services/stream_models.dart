/// نوع مصدر البث — يحدد كيف يتعامل المشغل مع الرابط.
enum StreamKind { hls, dash, progressive, web, other }

/// جودة واحدة داخل سيرفر معيّن (مثلاً 1080p / 720p / تلقائي).
class StreamQuality {
  final String label;
  final String url;
  const StreamQuality({required this.label, required this.url});

  factory StreamQuality.fromMap(Map<dynamic, dynamic> map) {
    return StreamQuality(
      label: (map['label'] ?? 'جودة').toString(),
      url: (map['url'] ?? '').toString(),
    );
  }
}

/// سيرفر واحد (مصدر) وله جودة أو أكثر. القناة قد تملك أكثر من سيرفر كخطة بديلة.
class StreamServerOption {
  final String label;
  final List<StreamQuality> qualities;
  const StreamServerOption({required this.label, required this.qualities});

  factory StreamServerOption.fromMap(Map<dynamic, dynamic> map) {
    final rawQualities = (map['qualities'] as List?) ?? const [];
    return StreamServerOption(
      label: (map['label'] ?? 'سيرفر').toString(),
      qualities: rawQualities
          .whereType<Map>()
          .map((q) => StreamQuality.fromMap(q))
          .where((q) => q.url.isNotEmpty)
          .toList(),
    );
  }
}

/// نتيجة تجهيز جلسة البث — تُستخدم من أي مصدر مدعوم.
class StreamSession {
  final bool ok;
  final StreamKind kind;
  final bool isLive;
  final List<StreamServerOption> servers;
  final String? errorMessage;
  // Optional Referer/User-Agent (or other) headers configured for this
  // source from the dashboard (channels.sourceHeaders). Empty by default —
  // callers must treat an absent/empty map as "use defaults", never as a
  // reason to fail.
  final Map<String, String> headers;

  const StreamSession._({
    required this.ok,
    required this.kind,
    required this.isLive,
    required this.servers,
    this.errorMessage,
    this.headers = const {},
  });

  factory StreamSession.success({
    required StreamKind kind,
    required bool isLive,
    required List<StreamServerOption> servers,
    Map<String, String> headers = const {},
  }) {
    return StreamSession._(
      ok: true,
      kind: kind,
      isLive: isLive,
      servers: servers,
      headers: headers,
    );
  }

  factory StreamSession.failure(String message) => StreamSession._(
        ok: false,
        kind: StreamKind.other,
        isLive: false,
        servers: const [],
        errorMessage: message,
      );

  bool get hasMultipleServers => servers.length > 1;
  bool get hasMultipleQualities =>
      servers.isNotEmpty && servers.first.qualities.length > 1;
}
