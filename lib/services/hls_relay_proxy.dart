import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Local HTTP relay for one HLS manifest and its segments/keys.
///
/// `video_player`/ExoPlayer accepts one static header map at controller
/// creation and reuses it for every request it makes for the lifetime of
/// that controller. Some sources need headers that are only valid briefly
/// (a session cookie the site's own JS keeps refreshing) — those requests
/// start failing partway through playback even though the manifest itself
/// loaded fine. This proxy sits between ExoPlayer and the real CDN: it
/// serves a rewritten manifest whose segment/key URIs point back at itself,
/// and re-fetches each one from the real URL with **freshly obtained**
/// headers at the moment ExoPlayer actually asks for it, instead of headers
/// captured once at the start.
///
/// Lifecycle: one instance = one [http.Client], created in [start] and
/// closed exactly once in [stop]. Never share a client across instances or
/// close one while a request on it may still be in flight — a shared
/// client closed mid-request was traced as the cause of repeated
/// "Client is already closed" segment failures in an earlier diagnostic
/// session, and this design exists specifically to avoid that.
class HlsRelayProxy {
  HttpServer? _server;
  http.Client? _client;
  Uri? _manifestUrl;
  Future<Map<String, String>> Function()? _headersProvider;
  final Map<String, String> _segmentMap = <String, String>{};

  bool get isRunning => _server != null;

  /// Starts the local server and returns the local playlist URL to hand to
  /// the native player controller in place of the real manifest URL.
  /// [headersProvider] is invoked fresh for the manifest fetch and for
  /// every single segment/key request — never cached across requests.
  Future<Uri> start(
    Uri manifestUrl,
    Future<Map<String, String>> Function() headersProvider,
  ) async {
    if (_server != null) {
      throw StateError('HlsRelayProxy already started — call stop() first.');
    }
    _manifestUrl = manifestUrl;
    _headersProvider = headersProvider;
    _client = http.Client();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(_serve(server));
    return Uri.parse('http://127.0.0.1:${server.port}/playlist.m3u8');
  }

  /// Stops the server and closes the one client this instance owns. Safe to
  /// call even if [start] was never called or was already stopped.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    try {
      await server?.close(force: true);
    } catch (_) {}
    _client?.close();
    _client = null;
    _manifestUrl = null;
    _headersProvider = null;
    _segmentMap.clear();
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.uri.path == '/playlist.m3u8') {
        await _serveManifest(request);
      } else if (request.uri.path == '/segment') {
        await _serveSegment(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveManifest(HttpRequest request) async {
    final client = _client;
    final headersProvider = _headersProvider;
    final manifestUrl = _manifestUrl;
    if (client == null || headersProvider == null || manifestUrl == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    final headers = await headersProvider();
    final http.Response response;
    try {
      response = await client
          .get(manifestUrl, headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      request.response.statusCode = response.statusCode;
      await request.response.close();
      return;
    }
    final rewritten = _rewriteManifest(response.body, manifestUrl);
    request.response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    request.response.write(rewritten);
    await request.response.close();
  }

  /// Rewrites every non-comment line (a segment or sub-manifest reference)
  /// and every `#EXT-X-KEY` `URI="..."` (the AES-128 decryption key — left
  /// unrelayed, native fetches it directly and fails the same way the
  /// manifest did) to point back at this proxy's `/segment` endpoint,
  /// resolved against the real manifest's URL first so relative references
  /// still work.
  String _rewriteManifest(String body, Uri baseUrl) {
    final out = StringBuffer();
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        out.writeln(line);
        continue;
      }
      if (line.startsWith('#')) {
        final keyMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (keyMatch != null && line.startsWith('#EXT-X-KEY')) {
          final real = baseUrl.resolve(keyMatch.group(1)!).toString();
          final token = _registerSegment(real);
          out.writeln(
              line.replaceRange(keyMatch.start, keyMatch.end, 'URI="/segment?u=$token"'));
          continue;
        }
        out.writeln(line);
        continue;
      }
      final real = baseUrl.resolve(line).toString();
      final token = _registerSegment(real);
      out.writeln('/segment?u=$token');
    }
    return out.toString();
  }

  String _registerSegment(String realUrl) {
    final token = base64Url.encode(utf8.encode(realUrl));
    _segmentMap[token] = realUrl;
    return token;
  }

  Future<void> _serveSegment(HttpRequest request) async {
    final client = _client;
    final headersProvider = _headersProvider;
    if (client == null || headersProvider == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    final token = request.uri.queryParameters['u'];
    final realUrl = token != null ? _segmentMap[token] : null;
    if (realUrl == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final headers = await headersProvider();
    // Forward the player's Range request (seeking depends on this) rather
    // than always fetching the whole segment.
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) headers['range'] = range;

    // A real master playlist references *sub*-manifests (per-quality
    // variant playlists), each itself listing the actual segment/key URIs.
    // Those sub-manifests get registered and relayed through this same
    // /segment endpoint like anything else found in a manifest — but if
    // relayed as raw bytes, the player would receive a variant playlist
    // whose own segment URIs still point straight at the real CDN,
    // bypassing this proxy for every actual segment fetch and reproducing
    // the exact stale-header failure it exists to avoid. A byte-range
    // request only ever targets real media data (players fetch playlists
    // in full), so this sniffs and rewrites only on non-range requests —
    // real segment fetches stay a plain, cheap stream passthrough.
    if (range == null) {
      final rewritten = await _tryRelayAsNestedManifest(realUrl, headers);
      if (rewritten != null) {
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
        request.response.write(rewritten);
        await request.response.close();
        return;
      }
    }

    final http.StreamedResponse upstream;
    try {
      final upstreamRequest = http.Request('GET', Uri.parse(realUrl))
        ..headers.addAll(headers);
      upstream = await client.send(upstreamRequest).timeout(const Duration(seconds: 15));
    } catch (_) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }
    request.response.statusCode = upstream.statusCode;
    final contentType = upstream.headers['content-type'];
    if (contentType != null) {
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    final contentRange = upstream.headers['content-range'];
    if (contentRange != null) {
      request.response.headers.set('content-range', contentRange);
    }
    final acceptRanges = upstream.headers['accept-ranges'];
    if (acceptRanges != null) {
      request.response.headers.set('accept-ranges', acceptRanges);
    }
    try {
      await request.response.addStream(upstream.stream);
    } catch (_) {
      // The player disconnected/aborted mid-segment (a seek elsewhere, or
      // it moved on) — nothing to recover, just stop relaying this one.
    } finally {
      await request.response.close();
    }
  }

  /// Fetches [realUrl] in full (not streamed) and, only if it is actually
  /// an HLS manifest (`#EXTM3U`), returns it rewritten with every
  /// reference relayed through this proxy too. Returns null for anything
  /// else (a real media segment, a key, a fetch error) so the caller falls
  /// back to its normal streamed passthrough.
  Future<String?> _tryRelayAsNestedManifest(
      String realUrl, Map<String, String> headers) async {
    final client = _client;
    if (client == null) return null;
    final http.Response response;
    try {
      response = await client.get(Uri.parse(realUrl), headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final body = response.body;
    if (!body.trimLeft().startsWith('#EXTM3U')) return null;
    return _rewriteManifest(body, Uri.parse(realUrl));
  }
}
