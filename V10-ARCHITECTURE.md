# Universal Web Player Engine — V10 Architecture

```text
Source URL
   |
   +--> Native resolver (existing)
   |
   +--> WebView
          |
          +--> DOM / framework discovery
          +--> dynamic iframe watcher
          +--> smart interaction
          +--> media-resource evidence
          |
          +--> iframe promotion when a real player frame appears
          |
          +--> playback proof
                 |
                 +--> Web playback confirmed
                 |
                 +--> safe native candidate found -> Native trial
```

### Design principle

The engine detects **playback behavior**, not a provider name or a single media extension.

### Native policy

Native playback is opportunistic. If a valid MP4/HLS/DASH candidate is strongly evidenced and validates, it may be tried. If the candidate fails, the WebView remains the authoritative fallback.

### Web policy

The WebView is the source of truth for custom players, blob/MSE playback, API-driven players, and sources that cannot be safely converted to a native URL.

### Iframe policy

An iframe is treated as a player document candidate only when it has strong generic evidence. When promoted, the original page URL is retained for fallback and is supplied as Referer when appropriate.
