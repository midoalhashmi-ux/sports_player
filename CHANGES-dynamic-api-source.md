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
- The watch screen now starts in landscape, exposes an explicit top orientation
  toggle, uses responsive video fitting, and enlarges the main controls.
- WebView-discovered HLS candidates retain the player document context and use
  derived `Origin`/`Referer` headers when replayed by the native player. This
  covers JSON playback endpoints such as `/api/videos/.../playback` whose final
  URL is a temporary `.m3u8` link on another CDN host.
- Manifest discovery now also accepts HLS playlists returned as `text/plain`
  or without a video extension, including `master.txt` and `/m3/` URLs. It
  confirms the response from `#EXTM3U`/HLS tags and passes an explicit HLS
  format hint to the native player.
- The WebView filter includes the ad domains observed in the anime HAR
  (`adsco.re`, `betteradsystem.com`, `scogienaira.cyou`, `li.backsetaspises.com`,
  `yt.vacantazon.com`, `taghas.com`, `inboxdollars.sjv.io`,
  `moolahsyangtze.shop`, `wvdme.com`, and `rtmark.net`) while leaving the
  actual `vmpx.online` HLS host untouched.
- Added a visible screen-fit button for native playback. It toggles between
  keeping the full video visible with possible black bars and filling the
  available screen while preserving the video's aspect ratio.

Full device testing is still required because the final URL is short-lived and
the Android network path may differ from a desktop browser.