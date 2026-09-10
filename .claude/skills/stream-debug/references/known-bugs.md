# Worked examples: real bugs found via this method

Four cases from real user-supplied logs, in the order they were found. Each
follows the same shape: symptom → log excerpt → hypothesis → code location →
fix. Use these to calibrate what "a minimal, well-evidenced fix" looks like
in this codebase — none of them needed more than ~10 changed lines.

## Case A — dual audio / "plays, then goes back to searching, then plays again"

**Symptom reported**: on an anime source, playback would start, then the UI
would flip back to a searching state, then start again — and background
audio was audible the whole time.

**Log shape**: `PLAY_SERVER_QUALITY_SUCCESS ... final state: NATIVE` at
`+14.2s`, then the log kept going — `MEDIA_RESOURCE`/`HLS_CANDIDATE_FROM_JS`
lines continued for segments already being played, then at `+17.9s` a
`NAV_ALLOWED` to an unrelated ad-redirect domain, then at `+19.1s`
`PAGE_FINISHED` for that ad page, then `KICK_AUTO_DETECT` /
`AUTO_DETECT_START` fired again, then a **second** `NATIVE_TRIAL_QUEUED` /
`PLAY_SERVER_QUALITY_SUCCESS` for the same original URL at `+23.9s`.

**Hypothesis**: the hidden WebView was still alive and wandering through an
ad-redirect chain on its own after native playback had already succeeded,
and something in that navigation was re-triggering the whole discovery
pipeline.

**Code location**: `onPageFinished` callback inside the `WebViewController`
setup (search for `_slog('PAGE_FINISHED'`). It unconditionally did
`setState(() => _state = _LoadState.loading)` and `_setWebSessionState
(_WebSessionState.webReady)` then kicked auto-detect again — with zero check
for whether native playback had already won.

**Fix**: one guard clause at the top of `onPageFinished`:
```dart
if (_webSessionState == _WebSessionState.nativePlaying) return;
```

## Case B — "worked" but the user says it didn't (movie source)

**Symptom reported**: a movie source "didn't work."

**Log shape**: both native trial attempts failed
(`NATIVE_TRIAL_FAILED ... ExoPlaybackException: Source error`,
`nativeAttempts=1/2` then `2/2`), `MANIFEST_RELAY_FAILED` too, then
`NATIVE_TRIALS_GIVEN_UP ... final state: WEBVIEW ONLY` at `+33.7s` — **and
then the log kept going for another 30+ seconds** with `MEDIA_RESOURCE`
lines showing `segmentEvidence=true` repeatedly: the WebView's own player
was actually successfully streaming the whole time.

**Hypothesis**: the video was genuinely playing (inside the WebView, since
native never worked for this source), but the UI didn't reflect it —
something downstream of "give up on native" never flipped the screen out of
its loading state.

**Code location**: the `else` branch after `NATIVE_TRIALS_GIVEN_UP` sets
`_setWebSessionState(webReady or drmWebOnly)` but — at the time — never
touched `_state`, which had been set to `_LoadState.loading` a few lines
above when the *first* native attempt failed and was never revisited.

**Fix**: `if (mounted) setState(() => _state = _LoadState.ready);` in that
`else` branch. Also relevant: this exact bug was made *worse*, not just
inert, by an earlier session fix that gated WebView touch interaction on
`_state == ready` (to stop accidental ad-taps during silent discovery) — so
until this fix, the user couldn't even manually tap through, because
`_state` never reached `ready`. When two fixes interact like this, say so
explicitly to the user rather than presenting them as unrelated.

## Case C — wasted seconds before a short-lived token expires

**Symptom reported**: same movie-source log as case B, used for a second
pass of investigation once the "why does it fail at all" question came up.

**Log shape**: `SOURCE_VALIDATING` immediately followed by `SOURCE_VALIDATED
validated=false`, immediately followed by `NATIVE_TRIAL_QUEUED` **anyway**
(strong-evidence override, see `state-machine.md`) — meaning the validation
network round-trip's result was discarded. The candidate URL had been first
observed via `HLS_CANDIDATE_FROM_JS` roughly 12 seconds before the
validation attempt even started.

**Hypothesis**: not provable from a static log alone (no way to confirm a
CDN token's actual TTL from outside), but well-supported: a signed URL with
a short expiry would explain both "WebView keeps working because it
refreshes its own session-bound URLs continuously" and "native fails the
same URL every time." Said this plainly to the user as a strong-but-unproven
theory, not a fact — don't oversell confidence static log analysis can't
provide.

**Code location**: the candidate loop in `_autoDetectWebSource` — it always
`await`ed `_validatePublicMediaSource(...)` before proceeding, even in the
branch where `strongHls || strongFramework` meant the result would be
ignored regardless (the skip condition a few lines down already excludes
strong-evidence candidates from being skipped on failed validation).

**Fix**: skip the network call entirely when `strongHls || strongFramework`,
treat `validated = true` directly. Zero behavior change for the branch that
uses the result — pure latency reduction for the one that doesn't. This is
the shape of fix to prefer when the root cause can't be fully confirmed:
something safe and provably neutral-or-better, not a speculative rewrite.

## Case D — a malformed candidate URL burning the second (and last) native attempt

**Symptom reported**: found while reading the same log as case B/C, not
separately reported.

**Log shape**: after the manifest relay failed, the retry discovery picked a
new candidate: `SOURCE_VALIDATING: url=https://vidtube.cam//` — a bare
domain with an empty/root path, obviously not a real manifest or segment
URL. It burned the second and final native-trial attempt for nothing
(`NATIVE_TRIAL_FAILED ... nativeAttempts=2/2`), directly causing
`NATIVE_TRIALS_GIVEN_UP` to trigger sooner than it might have otherwise.

**Code location**: `_isNonMediaAsset`, the last filter before a URL is
allowed into the trial candidate pool. It only rejected by file extension
(images/fonts/etc.), nothing checked for "no real path at all."

**Fix**: added a check to `_isNonMediaAsset` —
`uri.path.isEmpty || uri.path == '/'` → reject. Cheap, generalizes past this
one CDN's false positive.
