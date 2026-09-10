---
name: stream-debug
description: Diagnose and fix video playback failures in the sports_player Flutter app (part of the BinSheikh/sports_player-repo/AHMED-dashboard ecosystem) by reading an exported sports_player_debug_log.txt and tracing it against lib/screens/watch_screen.dart. Use this whenever the user shares a debug log from this app, says a source/channel/movie/anime "doesn't work" or "keeps searching" or has weird audio/loading behavior, mentions log tags like NATIVE_TRIAL_FAILED, SOURCE_VALIDATED, MANIFEST_RELAY_FAILED, NATIVE_TRIALS_GIVEN_UP, WEB_RESOURCE_ERROR, or ExoPlaybackException/Source error, or asks to work on watch_screen.dart, the WebView-to-native playback pipeline, or anything spanning sports_player-repo + BinSheikh + AHMED-dashboard together. Load this before touching watch_screen.dart even without a log, since the state-machine reference prevents re-deriving it from scratch.
---

# sports_player streaming diagnostics

This project has one recurring hard problem: getting protected/tokenized video
sources (Arabic streaming sites for anime, Turkish drama, movies) to actually
play. The app tries native ExoPlayer first and falls back to the WebView's own
player when that fails. Nearly every real bug so far has been in that
handoff — not in "the CDN is broken."

**The method that has worked every single time so far**: don't theorize from
the code alone. Get an exported log, walk it chronologically, find the exact
line where the log's timeline contradicts what the code *should* do, then
read that code path. Guessing at fixes without a log wastes effort — several
early theories in this project's history (header spoofing, TLS fingerprinting)
turned out to be wrong or unconfirmable; the fixes that actually shipped all
came from a specific log line contradicting a specific `setState` call.

## Project map

Three separate git repos, one Firebase project (`sports-stream-app-36a7a`),
one Cloudflare Worker (`binsheikh-api.binsheikh.workers.dev`):

| Repo | Local path | What it is |
|---|---|---|
| sports_player | `sports_player-repo/` | The player app (this repo). Gets a channel/episode ID via deep link, discovers the real stream, plays it. `lib/screens/watch_screen.dart` is the entire engine — one huge StatefulWidget. |
| BinSheikh | `../BinSheikh/` | The content-browsing app. Never touches stream URLs directly — deep-links into sports_player with just a channel ID. |
| AHMED-dashboard | `../AHMED-dashboard/` | Plain HTML/JS admin panel. `app.js` (general admin), `site-importer.js` (scrapes content sites into Firestore), `ratings.js` (TMDB/Jikan rating lookups). Talks to the Cloudflare Worker with an `x-admin-key` header (`ADMIN_SYNC_SECRET`). |

The Worker (`BinSheikh/cloudflare-worker/src/index.js`) does three unrelated
jobs behind one router: signs/proxies real HLS URLs so they never reach the
client in the clear, scrapes source sites for the importer, and syncs
match data from API-Football. Editing it requires `npx wrangler deploy`
separately — a GitHub push alone does **not** update the live Worker.

## Environment gotchas (Windows/PowerShell, this machine)

- `node`, `git`, `npx` are **not** on PATH by default in a fresh PowerShell
  session here. Every command needs this prefix:
  ```powershell
  $env:PATH = "C:\Users\DELL\AppData\Local\hermes\git\cmd;C:\Users\DELL\AppData\Local\hermes\node;$env:PATH"
  ```
- `git commit -m "..."` reliably **breaks** on Arabic text combined with
  special characters (arrows, smart quotes) — PowerShell mis-splits the
  argument and git reports bogus pathspec errors. Always write the message to
  a file in the scratchpad dir and use `git commit -F <file>` instead.
- `dart analyze` output garbles Arabic comments unless you set
  `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` first in the same
  command.
- Verifying JS syntax without a real Node project: `node --check <file>`
  fails on ESM `import` syntax unless piped through
  `node --input-type=module --check`, and piping through `Get-Content -Raw`
  can itself mangle Arabic — prefer `node --check <file>` directly on the
  file when possible, and only fall back to the piped form if you need to
  force ESM parsing.
- Always run `dart analyze` on the touched file(s) after any edit to
  `watch_screen.dart` before calling it done — it's ~4000 lines and a stray
  brace from manual editing is easy to miss. A handful of pre-existing
  warnings/errors are normal (dead youtube_explode_dart import, unused
  fields) — compare against a fresh `dart analyze` baseline, don't assume
  every warning is yours.

## The debugging method

1. **Get the log.** Ask for the exported `sports_player_debug_log.txt` if the
   user hasn't attached one — "it doesn't work" with no log is close to
   undiagnosable in this codebase given how much state it tracks.
2. **Read it start to finish with timestamps.** Every line is
   `[+N.NNNs] TAG: details`. Note the *gaps* between timestamps as much as the
   tags themselves — a 10+ second gap between candidate discovery and the
   actual trial attempt is itself a clue (see known-bugs.md, case C).
3. **Build a one-paragraph narrative of what actually happened**, in plain
   language, before touching any code: what was tried, what failed, what the
   final state was. If the narrative doesn't match what the user reported
   ("didn't work" but the log shows segments streaming fine), that mismatch
   *is* the bug — see `references/known-bugs.md` case B.
4. **Grep the exact log tag string in `watch_screen.dart`** to jump straight
   to the emitting code (`_slog('TAG_NAME', ...)`). Read outward from there —
   the state that gets set right before/after, and what governs it.
5. **State the hypothesis in one sentence**, then verify it by reading the
   surrounding code — don't patch until you can point at the specific
   `setState`/condition that produces the log's exact sequence. `references/
   state-machine.md` has the state enums and what each one is supposed to
   gate, so you're not rediscovering the architecture each time.
6. **Fix minimally.** Every fix that has shipped in this project was a few
   lines — a missing guard clause, a `_state` never reset, a redundant network
   call. If a fix looks like it needs a rewrite of the detection pipeline,
   the hypothesis is probably still wrong — go back to step 3.
7. **Verify with `dart analyze`**, then explain the fix to the user in terms
   of the specific log lines it addresses, not in the abstract. Concrete beats
   generic here — the user has been burned before by explanations that don't
   map to what they actually saw.
8. If a fix doesn't hold, that's expected — this pipeline has a lot of
   surface area. Ask for a fresh log from the *same* failure and re-run the
   method rather than stacking more speculative changes on the last guess.

See `references/known-bugs.md` for four real worked examples (log excerpt →
hypothesis → code location → fix) that are the clearest illustration of this
method in practice. See `references/state-machine.md` before reasoning about
`_webSessionState`/`_state` transitions from scratch.
