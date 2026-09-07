# UX and playback follow-up

- The companion app's legacy native watch screen now tracks real playback
  progress while buffering. A stale Android `isBuffering` value after seeking
  cannot leave a permanent center spinner; the indicator is capped at three
  seconds and disappears as soon as the position advances.
- Reloading that screen disposes the previous player before creating a new
  session, preventing duplicate playback resources.
- Firestore Timestamp values are accepted for channel start times in addition
  to ISO date strings.
- Channel loading errors now have a clear offline message and retry action.

The main channel flow still opens the dedicated player by channel ID. Stream
URLs and tokens are not moved into the content app.

## Build note

`video_player` and `chewie` were already referenced by the legacy watch screen
but were missing from `pubspec.yaml`; both dependencies are now declared so the
file remains buildable if that screen is used.