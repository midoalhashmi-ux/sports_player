import 'dart:convert';

/// Pure, side-effect-free classification/scoring logic for URLs discovered
/// during WebView source detection. Extracted out of `watch_screen.dart`
/// (a single ~4900-line StatefulWidget) so this specific logic — the part
/// that decides which candidate is worth a native playback trial — can be
/// unit tested and reviewed on its own, independent of the WebView/timer/
/// ExoPlayer orchestration around it. None of these depend on instance
/// state; each takes only the inputs it needs and returns a plain value.
///
/// This does not change any behavior: every method here is a verbatim copy
/// of the logic that used to live directly in _WatchScreenState.
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
  /// differ only by fragment are the same candidate) so the same stream
  /// isn't registered/scored twice under two different keys.
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
    return uri.removeFragment().toString();
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
    if (looksLikeHls(url)) score += 100;
    else if (lower.contains('.mpd')) score += 85;
    else if (lower.contains('.mp4') || lower.contains('.m4v') || lower.contains('.webm') || lower.contains('.mov')) score += 55;
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
  /// asset extensions, or a bare domain/root path with no real path at all
  /// (seen in practice as a false-positive candidate that burned a native
  /// trial attempt for nothing).
  static bool isNonMediaAsset(String url) {
    if (RegExp(
      r'\.(jpe?g|png|gif|webp|bmp|svg|ico|css|woff2?|ttf|eot|otf|json|swf|wasm)(?:$|[?#])',
      caseSensitive: false,
    ).hasMatch(url)) {
      return true;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.path.isEmpty || uri.path == '/')) return true;
    return false;
  }
}
