# Smart Web Playback V15

## New verified adapter: Video.js + tokenized HLS CDN

Based on captured playback from 3isk/ukrcdn:
- Video.js 8.16.1 is loaded from vjs.zencdn.net.
- Video.js quality plugins are present.
- `master.m3u8` returns HTTP 200.
- The master playlist points to a tokenized `720p/720p.m3u8`.
- The variant playlist returns tokenized `.ts` segments and ends with `#EXT-X-ENDLIST`.

## Behavior
- Video.js is treated as a browser-authoritative playback surface.
- Tokenized manifests/segments are not hard-coded or persisted.
- The WebView session remains authoritative for cookies, page context, JavaScript and temporary URLs.
- Smart play priming targets safe Video.js controls and the HTML5 media element.
- Generic Video.js detection is based on actual player evidence (`window.videojs`, Video.js scripts/classes plus a media element), not only a specific CDN host.
- Native replay is not attempted merely because a temporary HLS URL was observed.

## Safety
- No DRM bypass.
- No CAPTCHA/auth bypass.
- No ad-domain promotion.
