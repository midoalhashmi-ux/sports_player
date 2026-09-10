# watch_screen.dart state machine

Two separate state variables that overlap but aren't the same thing. Bugs
have repeatedly come from confusing the two, or from a code path that
updates one but forgets the other.

## `_state` (`_LoadState`) — what the *UI* shows

```dart
enum _LoadState { loading, error, ready }
```

Drives what's actually rendered: `loading` → `_buildLoading()` (spinner +
progressive waiting message), `error` → `_buildError()`, `ready` → the real
player surface (native `VideoPlayer` widget, or the WebView, depending on
`_isWebSource`).

**The recurring failure mode**: a code path finishes the discovery/playback
pipeline and considers itself "done," but never sets `_state = ready`. The
result is always the same symptom — a permanent loading spinner sitting on
top of something that is actually working underneath (native video playing
silently behind it, or the WebView's own player streaming fine behind it).
When you see "it never finishes loading" or "stuck on searching," check
whether every terminal branch of the relevant function actually flips
`_state` before returning. Grep `_state = _LoadState.ready` and check it's
reachable from wherever the log's last event happened.

## `_webSessionState` (`_WebSessionState`) — where the *web discovery pipeline*
is, only meaningful while `_isWebSource` is relevant

```dart
enum _WebSessionState {
  idle,
  loadingPage,           // WebView navigating to the source page
  webReady,               // page loaded, browser-side playback looks provably real
  interacting,            // auto-click sentinel is trying to trigger a real player tap
  discovering,             // periodic detector timer is scanning for candidate URLs
  validating,              // a candidate is being checked (network probe or skipped — see below)
  nativeTrial,             // a candidate is being handed to ExoPlayer right now
  candidateTrial,
  nativePlaying,           // ExoPlayer succeeded — this is the terminal "native won" state
  nativeFailed,            // most recent native attempt just threw
  drmWebOnly,              // DRM detected, WebView is the only option, permanently
  webFallback,             // native attempts exhausted or deferred, WebView carries playback
  humanVerificationRequired, // real captcha/challenge on the page — never auto-solved, only surfaced
  stopped,
}
```

**`nativePlaying` is the important guard value.** Once native ExoPlayer has
proven it can play the stream, essentially everything else about the
WebView's own lifecycle should be considered irrelevant — its own page can
keep navigating (ad redirects, JS timers) in the background, but none of
that should be allowed to touch `_state`, re-trigger discovery, or start a
second playback attempt. `onPageFinished` is the classic place this was
missed: it fires for *every* page load the WebView does, including ones the
ad network causes on its own, so any state-mutating logic inside it needs an
explicit `if (_webSessionState == _WebSessionState.nativePlaying) return;`
at the very top, or it will happily "helpfully" re-run discovery against a
page the user never asked to see.

**`webFallback`/`webReady` as a terminal state is equally real** — when
native trials are exhausted (`NATIVE_TRIALS_GIVEN_UP` in the log), the
WebView keeps playing on its own for real (this is not a failure state, it's
a legitimate fallback). The bug here has been forgetting to also flip
`_state = ready` when landing in this terminal state — see
`known-bugs.md` case B.

## Native-trial candidate scoring, briefly

Candidates get a `score` from evidence signals (framework detection, HLS
markers, resource-load hits). Two thresholds matter when reading a log:

- `strongHls` / `strongFramework` (score high enough): the code will attempt
  a native trial **regardless of what `_validatePublicMediaSource` says** —
  so if you see `SOURCE_VALIDATED: validated=false` immediately followed by
  `NATIVE_TRIAL_QUEUED` anyway, that's not a bug, that's the strong-evidence
  override working as designed. (It used to also *wait* for that pointless
  validation round-trip before proceeding anyway — fixed, see
  `known-bugs.md` case C — so don't re-diagnose that specific shape again.)
- Below that threshold, a failed validation causes `SOURCE_SKIPPED
  reason=failed_validation` and the loop moves to the next candidate.

`_webNativeAttempts` vs `_webMaxNativeAttempts` (currently 2) caps how many
native trials happen per session before giving up to `webFallback`/
`drmWebOnly`. Each failed attempt logs `NATIVE_TRIAL_FAILED ...
nativeAttempts=N/2`.
