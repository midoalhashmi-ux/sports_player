# Legendary Source Engine Update

This build strengthens `WatchScreen` source resolution while preserving the existing WebView/Native architecture.

## Added

- Explicit HTTP redirect handling (3xx `Location`) instead of relying on implicit redirect behavior.
- Bounded recursive API source resolver (`lib/services/api_source_resolver.dart`).
- Recursive JSON traversal for common stream/source fields.
- URL extraction from arbitrary public API payload text.
- Base64 + Base64URL decoding with padding repair.
- GZIP/ZLIB decoding after Base64.
- Hex decoding.
- Percent-decoding and JSON-string unwrapping.
- Optional XOR decoding only when an explicit `x-xor-key` or `xor-key` header is provided.
- Direct media response recognition.
- Candidate scoring and deduplication.
- Native stream headers retained through resolution.
- WebView/Native header merging using the current web context when available.
- Best-effort HLS validation before Native trials.
- Existing WebView detector remains the final discovery layer (video/source/iframe/performance/fetch/XHR).

## Important limitation

The `def.ycnapi.com/api/channel/4` response shown during investigation decodes from Base64 to binary data rather than readable JSON/URL text. No unknown encryption key or proprietary cipher is guessed or cracked. If that binary payload is protected by a private algorithm, the app must obtain the decoding logic from the legitimate client/source implementation.

The resolver therefore maximizes coverage of common public encodings and redirects, then relies on the existing WebView discovery path when a public media URL is observable there.

## Safety

No DRM bypass, key extraction, authentication bypass, subscription bypass, CAPTCHA bypass, or access-control circumvention is implemented.


## V7 Universal Player Intelligence
- Direct MP4/WebM/M4V/MOV validation falls back from HEAD to a small Range GET for CDNs that reject HEAD.
- WebView discovery inspects HTML5 media, JW Player, Video.js, Plyr, common public player globals, data-* attributes, and inline configuration.
- Smart interaction recognizes common player play controls, including JW/Video.js/Plyr controls, with bounded attempts.
- Existing API decoding, redirect, SPA, DRM detection, native proof, WebView fallback, and protection logic are preserved.
