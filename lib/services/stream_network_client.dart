import 'package:http/http.dart' as http;

/// A single reused HTTP connection for the repeated candidate-validation
/// probes fired during source discovery (`_validatePublicMediaSource`).
///
/// The package-level `http.get`/`http.head` convenience functions each open
/// and tear down their own connection (including a fresh TLS handshake) per
/// call. Discovery can probe several candidates in one scan, so reusing one
/// `http.Client` for the whole session avoids repeating that handshake for
/// every probe. Timeouts stay per-call and match what each call site used
/// before this existed — this only changes connection reuse, not behavior.
class StreamNetworkClient {
  final http.Client _client = http.Client();

  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    required Duration timeout,
  }) {
    return _client.get(url, headers: headers).timeout(timeout);
  }

  Future<http.Response> head(
    Uri url, {
    Map<String, String>? headers,
    required Duration timeout,
  }) {
    return _client.head(url, headers: headers).timeout(timeout);
  }

  void close() => _client.close();
}
