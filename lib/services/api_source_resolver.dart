import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Resolves public API payloads into candidate media URLs.
/// It intentionally supports decoding/obfuscation commonly used by public
/// APIs, but does not attempt to bypass DRM, authentication, or access controls.
class ApiSourceCandidate {
  final String url;
  final Map<String, String> headers;
  final int score;
  final String reason;

  const ApiSourceCandidate({
    required this.url,
    this.headers = const {},
    this.score = 0,
    this.reason = '',
  });
}

class ApiSourceResolver {
  static const _urlPattern = r"""https?://[^\s"'<>\\]+|(?:^|[\s"'=:])(/[^\s"'<>]+)""";
  static final RegExp _urlRegex = RegExp(_urlPattern, caseSensitive: false);
  static final RegExp _directPattern = RegExp(
    r'(?:\.m3u8(?:$|[?#])|\.mpd(?:$|[?#])|\.mp4(?:$|[?#])|\.m4v(?:$|[?#])|\.webm(?:$|[?#])|\.mov(?:$|[?#])|/live/|/stream/|/playlist/|/manifest/)',
    caseSensitive: false,
  );

  static Future<List<ApiSourceCandidate>> resolve(
    String url, {
    Map<String, String>? headers,
    int maxDepth = 3,
  }) async {
    final out = <ApiSourceCandidate>[];
    final visited = <String>{};
    await _walk(url, headers ?? const {}, 0, maxDepth, visited, out);
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  static Future<void> _walk(
    String url,
    Map<String, String> headers,
    int depth,
    int maxDepth,
    Set<String> visited,
    List<ApiSourceCandidate> out,
  ) async {
    if (depth > maxDepth || visited.contains(url)) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    visited.add(url);

    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..maxRedirects = 0;
      request.headers.addAll({
        'accept': 'application/json, text/plain, */*',
        'accept-encoding': 'gzip',
        'user-agent': headers['user-agent'] ??
            'okhttp/4.12.0',
        ...headers,
      });
      final streamed = await request.send().timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          final next = uri.resolve(location).toString();
          _addIfUseful(next, headers, 220, 'HTTP redirect', out);
          await _walk(next, headers, depth + 1, maxDepth, visited, out);
        }
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 400) return;

      final contentType = (response.headers['content-type'] ?? '').toLowerCase();
      if (_directPattern.hasMatch(url) ||
          contentType.contains('mpegurl') ||
          contentType.contains('dash+xml') ||
          contentType.startsWith('video/')) {
        _addIfUseful(url, headers, 240, 'direct media response', out);
      }

      final body = response.body;
      final texts = <String>{body};
      texts.addAll(_decodeLayers(body));

      for (final text in texts) {
        _extractTextCandidates(text, uri, headers, depth, maxDepth, visited, out);
      }
    } catch (_) {
      // Best-effort resolver. WebView discovery remains the fallback.
    }
  }

  static void _extractTextCandidates(
    String text,
    Uri base,
    Map<String, String> headers,
    int depth,
    int maxDepth,
    Set<String> visited,
    List<ApiSourceCandidate> out,
  ) {
    final trimmed = text.trim();
    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {}

    if (decoded != null) {
      _walkJson(decoded, base, headers, depth, maxDepth, visited, out);
    }

    for (final match in _urlRegex.allMatches(text)) {
      var raw = match.group(0)?.trim() ?? '';
      if (raw.isEmpty) continue;
      raw = raw.replaceFirst(RegExp(r"""^[\s"'=:]+"""), "");
      raw = raw.replaceAll(RegExp(r"""["'<>),;]+$"""), "");
      final resolved = _resolve(raw, base);
      if (resolved == null) continue;
      final score = _score(resolved);
      if (score >= 80) {
        _addIfUseful(resolved, headers, score, 'URL extracted from API payload', out);
      }
    }
  }

  static void _walkJson(
    dynamic value,
    Uri base,
    Map<String, String> headers,
    int depth,
    int maxDepth,
    Set<String> visited,
    List<ApiSourceCandidate> out,
  ) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        final child = entry.value;
        if (child is String) {
          final resolved = _resolve(child.trim(), base);
          if (resolved != null) {
            var score = _score(resolved);
            if (_isSourceKey(key)) score += 70;
            if (score >= 60) {
              _addIfUseful(resolved, headers, score, 'JSON field: $key', out);
            }
          }
          final nestedTexts = _decodeLayers(child);
          for (final text in nestedTexts) {
            _extractTextCandidates(text, base, headers, depth, maxDepth, visited, out);
          }
        } else {
          _walkJson(child, base, headers, depth, maxDepth, visited, out);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        _walkJson(item, base, headers, depth, maxDepth, visited, out);
      }
    }
  }

  static bool _isSourceKey(String key) {
    return RegExp(r'^(url|uri|link|src|source|stream|streamurl|playurl|play|hls|m3u8|dash|mpd|manifest|playlist|file|video|media|redirect|location|endpoint|data|result|payload|encoded|cipher)$', caseSensitive: false).hasMatch(key);
  }

  static List<String> _decodeLayers(String input) {
    final out = <String>{};
    var frontier = <String>{input};
    final seen = <String>{};
    for (var depth = 0; depth < 4 && frontier.isNotEmpty; depth++) {
      final next = <String>{};
      for (final current in frontier) {
        if (!seen.add(current) || current.isEmpty) continue;
        final candidates = <String>{};
        candidates.add(Uri.decodeFull(current));
        candidates.add(_decodeBase64Text(current));
        candidates.add(_decodeHexText(current));
        candidates.add(_decodeCompressedText(current));
        for (final value in candidates) {
          final normalized = _normalize(value);
          if (normalized == null || normalized.isEmpty || normalized == current) continue;
          if (_isUseful(normalized)) {
            out.add(normalized);
            next.add(normalized);
          }
        }
      }
      frontier = next;
    }
    return out.toList();
  }

  static String? _decodeBase64Text(String input) {
    final compact = input.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 12 || compact.length % 4 == 1) return null;
    if (!RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(compact)) return null;
    final normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
    try {
      return _safeUtf8(base64Decode(padded));
    } catch (_) {
      return null;
    }
  }

  static String? _decodeHexText(String input) {
    final compact = input.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 8 || compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact)) return null;
    try {
      final bytes = <int>[];
      for (var i = 0; i < compact.length; i += 2) {
        bytes.add(int.parse(compact.substring(i, i + 2), radix: 16));
      }
      return _safeUtf8(bytes);
    } catch (_) {
      return null;
    }
  }

  static String? _decodeCompressedText(String input) {
    // Compression decoding is done on raw bytes only when the text is Base64.
    try {
      final compact = input.replaceAll(RegExp(r'\s+'), '');
      if (!RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(compact)) return null;
      final normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
      final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
      final bytes = base64Decode(padded);
      if (bytes.length < 2) return null;
      List<int>? inflated;
      try {
        inflated = gzip.decode(bytes);
      } catch (_) {}
      if (inflated == null) {
        try {
          inflated = ZLibCodec().decode(bytes);
        } catch (_) {}
      }
      return inflated == null ? null : _safeUtf8(inflated);
    } catch (_) {
      return null;
    }
  }

  static String? _safeUtf8(List<int> bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      return _normalize(text);
    } catch (_) {
      return null;
    }
  }

  static String? _normalize(String text) {
    var value = text.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is String) value = decoded.trim();
      } catch (_) {}
    }
    return value;
  }

  static bool _isUseful(String text) {
    final l = text.toLowerCase();
    return _looksLikeUrl(text) ||
        l.contains('.m3u8') || l.contains('.mpd') || l.contains('http') ||
        l.contains('"url"') || l.contains('"stream"') || l.contains('#extm3u');
  }

  static bool _looksLikeUrl(String text) => RegExp(r'^https?://', caseSensitive: false).hasMatch(text.trim());

  static String? _resolve(String value, Uri base) {
    final clean = value.trim();
    if (clean.isEmpty) return null;
    final uri = Uri.tryParse(clean);
    if (uri == null) return null;
    if (uri.isAbsolute) return uri.toString();
    if (clean.startsWith('/')) return base.resolveUri(uri).toString();
    return null;
  }

  static int _score(String url) {
    final l = url.toLowerCase();
    var score = 0;
    if (l.contains('.m3u8')) score += 150;
    else if (l.contains('.mpd')) score += 120;
    else if (RegExp(r'\.(mp4|m4v|webm|mov)(?:$|[?#])').hasMatch(l)) score += 80;
    if (l.contains('/live/')) score += 45;
    if (l.contains('stream')) score += 30;
    if (l.contains('master')) score += 20;
    if (l.contains('playlist') || l.contains('manifest')) score += 15;
    if (l.contains('.ts') || l.contains('segment')) score -= 120;
    if (RegExp(r'(doubleclick|googlesyndication|googleadservices|adservice|vast|advert|ads\b)', caseSensitive: false).hasMatch(l)) score -= 160;
    return score;
  }

  static void _addIfUseful(
    String url,
    Map<String, String> headers,
    int score,
    String reason,
    List<ApiSourceCandidate> out,
  ) {
    if (!_looksLikeUrl(url)) return;
    final normalized = url.trim();
    if (out.any((c) => c.url == normalized)) return;
    out.add(ApiSourceCandidate(url: normalized, headers: Map.unmodifiable(headers), score: score, reason: reason));
  }
}
