# Dynamic API source

- Added the dashboard source type `API ديناميكي / Encoded API`.
- Firestore stores the stable API URL in `channels.sourceUrl` and never writes
  the temporary HLS URL returned by that API.
- Optional `apiHeaders` are used for the API request. Existing
  `sourceHeaders` remain the playback headers for the final HLS/MPD/MP4 URL.
- The player follows HTTP redirects and tries standard URL encoding, JSON,
  Base64/Base64URL, Hex, Gzip, and Zlib layers. It does not guess an unknown
  cipher key and does not bypass DRM, CAPTCHA, or authentication.
- Resolver diagnostics redact query strings and therefore do not print
  temporary `t`/`e` tokens or full signed URLs.

Full device testing is still required because the final URL is short-lived and
the Android network path may differ from a desktop browser.