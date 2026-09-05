# Auto Source Detector

This build adds automatic public media-source detection for `streamType=web` pages.

How it works:
- Opens the configured web page in the protected WebView.
- Waits for client-side JavaScript to initialize.
- Scans public `<video>` / `<source>` elements and browser performance resource entries.
- Detects public HLS (`.m3u8`) and common progressive video URLs.
- Scores candidates and switches to the native video player when a strong HLS/video source is found.
- Leaves DASH (`.mpd`) inside WebView because the current `video_player` dependency does not provide DASH playback.
- Does not bypass DRM, authentication, subscriptions, or access controls.

Recommended Rotana URL format:
`https://rotana.net/ar/live#/live/rotana-comedy`

The detector is intentionally best-effort: websites can change their player architecture, use cross-origin media, DRM, blob URLs, or encrypted delivery that cannot be converted to a native public URL.
