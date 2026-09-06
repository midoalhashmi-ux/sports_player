# Smart Web Playback V9 — changes from sports_player-main(6)

This release keeps the existing project architecture and features intact and only strengthens web playback startup and the native seek experience.

## Changes
- Smart Play detection now has four layers:
  1. Known player controls/classes and play-related attributes/text.
  2. Text-labelled play/watch/live controls.
  3. Geometric fallback around the detected player center for safe icon-only controls.
  4. HTML5 `video.play()` fallback when a real video element exists.
- A player that starts below the visible viewport is scrolled into view inside the hidden WebView before safe play-control detection.
- After an interaction, playback is verified by checking that `currentTime` actually advances; a click alone is not considered success.
- Web startup starts with a 20-second deadline, extends only when there is genuine progress, and is capped at 90 seconds for the entire session.
- Native candidate attempts and failures extend that same session deadline without creating an unbounded retry loop.
- Native playback controls now use the actual known media duration (`_contentIsSeekable`) instead of the database `isLive` flag alone. A recorded video with a finite duration therefore exposes the seek bar and ±10-second controls even if the upstream metadata says `live`.
- When a finite-duration video is detected, the Live badge and "jump to live" control are suppressed so a recorded video is not presented as live in the player controls.
- Native controller position/duration state is reset when switching to a newly discovered source.
- The loading indicator is now a red progress ring plus bold white text with a dark shadow for strong contrast.

## Intentionally unchanged
- AdMob/`AdService` behavior.
- Existing API/source resolvers and source-header handling.
- Existing popup/redirect/notification protection architecture.
- Existing player framework/source discovery logic outside the startup interaction improvements.
- DRM/authentication/CAPTCHA handling; no bypass was added.
