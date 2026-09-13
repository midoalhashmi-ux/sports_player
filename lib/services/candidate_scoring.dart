import 'dart:convert';

/// Pure, side-effect-free classification/scoring logic for URLs discovered
/// during WebView source detection. Extracted out of `watch_screen.dart`
/// (a single ~5000-line StatefulWidget) so this specific logic — the part
/// that decides which candidate is worth a native playback trial — can be
/// unit tested and reviewed on its own, independent of the WebView/timer/
/// ExoPlayer orchestration around it. None of these depend on instance
/// state; each takes only the inputs it needs and returns a plain value.
///
/// This does not change any behavior: every method here is a verbatim copy
/// of the logic that used to live directly in _WatchScreenState, including
/// every fix already applied there (removeFragment() over replace(),
/// trailing-slash-after-.m3u8 stripping, the "//" empty-path edge case).
class CandidateScoring {
  CandidateScoring._();

  /// True when [text] contains a clear sign of embedded media (an HLS/DASH
  /// marker or a `<video>` tag) — used while walking decoded JSON/JS
  /// payloads looking for a real stream reference.
  static bool containsMediaMarker(String text) {
    final lower = text.toLowerCase();
    return lower.contains('#extm3u') || lower.contains('.m3u8') || lower.contains('.m3u') ||
        lower.contains('.mpd') || lower.contains('<video');
  }

  /// True when [url]'s extension alone is enough to know a player could
  /// play it directly, without any further probing.
  static bool isDirectPlayable(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('.m3u') || lower.contains('.mpd') ||
        lower.contains('.mp4') || lower.contains('.webm') ||
        lower.contains('.m4v') || lower.contains('.mov');
  }

  static dynamic tryParseJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static bool looksLikeJson(String text) {
    final trimmed = text.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  /// Strips the URL fragment (never sent to a server, and two URLs that
  /// differ only by fragment are the same candidate) and a stray trailing
  /// slash right after `.m3u8`/`.m3u` (some sites register their manifest
  /// URL with one; confirmed by a real diagnostic log to draw a 400 Bad
  /// Request from at least one real CDN) so the same stream isn't
  /// registered/scored twice under two different keys.
  ///
  /// Uses `Uri.removeFragment()` rather than `Uri.replace(fragment: '')` —
  /// the latter sets an explicit-but-empty fragment (`hasFragment` becomes
  /// true), which leaves a trailing bare `#` on every normalized URL, even
  /// ones that never had a fragment to begin with. `removeFragment()` is
  /// the API built specifically to avoid that; it returns the same URI
  /// unchanged when there was no fragment.
  static String normalizeCandidate(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return url.trim();
    var normalized = uri.removeFragment().toString();
    if (RegExp(r'\.m3u8?/$', caseSensitive: false).hasMatch(normalized)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool looksLikeHls(String url) => RegExp(
        r'(?:\.m3u8?(?:$|[?#])|/(?:hls|m3)/|(?:master|playlist|manifest)(?:[./?#&]|$))',
        caseSensitive: false,
      ).hasMatch(url);

  static bool looksLikeProgressiveVideo(String url) =>
      RegExp(r'\.(mp4|m4v|webm|mov)(?:$|[?#])', caseSensitive: false).hasMatch(url);

  /// Heuristic score used to rank/filter candidate URLs before a native
  /// playback trial is spent on one of them — higher is more likely to be
  /// a real, playable stream rather than a segment, ad, or unrelated asset.
  static int scoreDetectedSource(String url) {
    final lower = url.toLowerCase();
    var score = 0;
    if (looksLikeHls(url)) {
      score += 100;
    } else if (lower.contains('.mpd')) {
      score += 85;
    } else if (lower.contains('.mp4') || lower.contains('.m4v') || lower.contains('.webm') || lower.contains('.mov')) {
      score += 55;
    }
    if (lower.contains('live')) score += 35;
    if (lower.contains('stream')) score += 25;
    if (lower.contains('channel')) score += 20;
    if (lower.contains('master')) score += 15;
    if (lower.contains('playlist')) score += 10;
    if (lower.contains('segment') || lower.contains('.ts')) score -= 100;
    if (lower.contains('ads') || lower.contains('advert') || lower.contains('vast') || lower.contains('doubleclick')) score -= 100;
    return score;
  }

  /// True for URLs that can never be a real stream candidate: known static
  /// asset extensions, or a path made up of nothing but slashes (a bare
  /// domain, "/", "//", ...) — seen in practice as false-positive
  /// candidates that burned a native trial attempt for nothing.
  ///
  /// `.key` مؤكَّد بسجل تشخيص فعلي: مفتاح تشفير AES-128 لشرائح HLS يعيش
  /// عادةً بنفس مسار `/hls/...` للقائمة والشرائح نفسها — `looksLikeHls()`
  /// (يطابق `/hls/` كمقطع مسار) كان يمنحه نقاط تقييم عالية (100+) رغم
  /// إنه ملف مفتاح تشفير خام، لا فيديو قابل للتشغيل إطلاقاً. النتيجة
  /// الفعلية: بعد فشل كل مرشّحي الفيديو الحقيقيين وإعادة فحص المصادر،
  /// المفتاح كان يتصدّر كمرشّح "دليل قوي" ويُرسَل لمحاولة تشغيل أصلي
  /// (`PLAY_SERVER_QUALITY_START .../encryption.key`) — يفشل حتماً
  /// (`ExoPlaybackException: Source error`)، ثم تُستنفَد كل محاولات
  /// إعادة الاتصال التلقائي الثماني (`NATIVE_AUTO_RECONNECT`) بإعادة
  /// محاولة نفس رابط المفتاح تكراراً — يبدو للمستخدم كمصدر "توقف فجأة".
  ///
  /// `.ts` مؤكَّد بسجل تشخيص فعلي منفصل بنفس النمط بالضبط: شريحة HLS خام
  /// وحيدة (`seg-1-v1-a1.ts`) — `scoreDetectedSource` أصلاً يخصم 100 نقطة
  /// لأي رابط شريحة، لكن هذا الخصم كان يُلغى ببونص "مسجَّل كـhls بالسجل"
  /// (+85) أو "من إطار عمل معروف" (+85) لو ظهر نفس رابط الشريحة بمصدر آخر
  /// (مثل قائمة تشغيل JWPlayer الداخلية) — فيتجاوز حد 80 ويُختار كمرشّح
  /// "قوي" رغم كونه شريحة واحدة لا قائمة تشغيل كاملة. نفس تسلسل الفشل:
  /// `PLAY_SERVER_QUALITY_START .../seg-1-v1-a1.ts` يفشل حتماً، ثم إعادة
  /// اتصال تلقائي تكراري بنفس الرابط الفاشل.
  static bool isNonMediaAsset(String url) {
    if (RegExp(
      r'\.(jpe?g|png|gif|webp|bmp|svg|ico|css|woff2?|ttf|eot|otf|json|swf|wasm|key|ts)(?:$|[?#])',
      caseSensitive: false,
    ).hasMatch(url)) {
      return true;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && uri.path.replaceAll('/', '').isEmpty) return true;
    return false;
  }
}
