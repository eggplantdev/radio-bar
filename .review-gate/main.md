# Review-gate ledger — radio-bar (whole app) · 2026-11-13

Scope: every tracked file from the root commit 444753e through e86d8d2, plus the uncommitted
„Szukaj na YouTube” change (README.md, context/foundation/manual-checks.md, src/debughook.swift, src/main.swift).
Checks: /code-review, comment-noise-audit (flag-only), module-cohesion-audit.
Dropped: 10x-impl-review (no plan.md), tailwind-v4-audit (no CSS), feature-first-structure and
structure-scatter-audit (two source files, nothing to scatter), verify pass (native app, no browser).

## Findings
<!-- No automated test harness in this repo: every correctness finding's guard is a manual check in context/foundation/manual-checks.md. -->
- [x] 🔴 CRITICAL · fixed · code-review · `src/main.swift` startStream/retry · a stream that fails while loading (no network after wake/login, bad custom URL) sets item.status = .failed, posts none of the observed notifications, and is never retried — KVO on the item's status now retries it
      test: no automated test (no harness) · manual — „review-gate fixes” § Wi-Fi off, pick a station, Wi-Fi on
- [x] fixed · design · stream lifecycle · 🔵 delayed reconnect not tied to the failed item + 🔵 ICY metadata from the replaced item applied to the new station — one `retry(item)` path: retries only while the item is still current, backs off 3 s → 60 s, resets on readyToPlay; metadata ignored unless its output belongs to the current item
- [x] 🟡 WARNING · fixed · code-review · `src/main.swift` spotifyIfRunning · after the user quits Spotify, the next volume/mute/station change relaunched it; pause and volume now go through `if … is running`, and Spotify's termination unticks it
      test: no automated test (no harness) · manual — „review-gate fixes” § quit Spotify, scroll/⌃⌥M
- [x] 🟡 WARNING · fixed · code-review · `src/main.swift` stopSpotify/applicationWillTerminate · muting on Spotify then switching to a station or quitting Radio left Spotify's own volume at 0 — both restore it (quit also pauses)
      test: no automated test (no harness) · manual — „review-gate fixes” § mute → station, mute → quit
- [x] 🟡 WARNING · fixed · code-review · `src/main.swift` queryCharacters · `.alphanumerics` left Polish letters unescaped (nil URL on macOS 13) — ASCII-only set shared by the Spotify and YouTube search
      test: no automated test (no harness) · verified in the debug build: „Między ciszą” → `Mi%C4%99dzy%20cisz%C4%85`
- [x] 🟡 WARNING · fixed · code-review · `src/main.swift` permissionDenied · after an Automation denial every Spotify command opened its own alert behind the front app — one alert per run, app activated first, Spotify unticked
      test: no automated test (no harness) · manual — `tccutil reset AppleEvents pl.local.radio`, pick Spotify, deny, scroll
- [x] 🟡 WARNING · skipped · code-review · `src/main.swift` playSpotify · pick Spotify while it isn't running, then a station within a second → both silent — the fix is a timing window/generation counter, a second mechanism for a change-of-mind within the seconds Spotify takes to launch
- [ ] 🔵 OBSERVATION · awaiting answer · code-review · `src/main.swift` applicationDidFinishLaunching · Spotify already playing when Radio launches on a station → both play at once; fix needs a choice: pause Spotify, or adopt it as the source
- [x] 🔵 OBSERVATION · fixed · code-review · `src/main.swift` scrollWheel · slow trackpad scroll never changed the volume — `scrollRemainder` accumulates until a whole percent
      test: no automated test (no harness) · manual — „review-gate fixes” § slow two-finger scroll
- [x] 🔵 OBSERVATION · fixed · code-review · `src/main.swift` dockTiles · „Zachowaj w Docku” wrote [Radio] over the whole Dock when persistent-apps couldn't be read — nil → beep, Dock untouched
      test: no automated test (no harness) · no manual check — the read failing can't be staged on a working Mac
- [x] 🔵 OBSERVATION · fixed · code-review · `src/main.swift` editStreamURL · the custom stream URL saved any parsable scheme and dropped a schemeless link silently — only http/https with a host, else the dialog returns with a message
      test: no automated test (no harness) · manual — „review-gate fixes” § `radio357.pl/abc`
- [x] 🔵 OBSERVATION · fixed · code-review · `src/main.swift` Edit menu · no Wytnij / Cofnij / Ponów — added
      test: no automated test (no harness) · manual — „review-gate fixes” § ⌘X / ⌘Z
- [x] 🔵 OBSERVATION · dropped · code-review · `src/main.swift` spotifyQueue · NSAppleScript on a serial background queue — no observed failure in weeks of use; moving to NSAppleEventDescriptor is a rewrite of the bridge for a contract breach nobody has hit
- [x] 🔵 OBSERVATION · dismissed · code-review · `src/debughook.swift` · any local process can drive the debug build — it is a dev instrument, never installed or set as a login item
- [x] fixed · comment-noise · `src/main.swift`, `tools/audiolevel.swift`, `tools/make-icon.swift` · 8 comments narrating the code or repeating README — deleted
- [x] fixed · comment-noise · `src/main.swift`, `tools/make-icon.swift` · 5 comments restating the code — trimmed to the first clause
- [x] fixed · comment-noise · `src/main.swift` menuWillOpen · the volume-row reset got its one-line why
- [ ] awaiting answer · module-cohesion · `src/main.swift` · ~850 lines, 5 reasons to change; proposed split: Stations / Spotify / Settings / Menus / main via `extension AppDelegate`; members lose `private`; build.sh → `src/*.swift` with debughook wrapped in `#if DEBUGHOOK`
- [ ] awaiting answer · simplify (altitude) · `src/main.swift` · `current` + `spotifyActive` → one `enum Source` — removes the two-flag states the Spotify fixes keep guarding; touches most of the file, so your call
- [x] fixed · simplify · `src/main.swift` refreshIndicators · every scroll/slider event rebuilt all row titles — rebuilt only when shows/songs/album/track change (`rowsKey`)
- [x] fixed · simplify · `src/main.swift` syncSpotifyVolume · one AppleScript per scroll event — one in flight plus a pending flag
- [x] fixed · simplify · `src/main.swift` logos/spotifyImage · logos and the Spotify icon re-rendered each refresh — lazy, built once
- [x] fixed · simplify · `src/main.swift` dock badge · written on every refresh — only when it changes
- [x] fixed · simplify · `src/main.swift` session · URLSession.shared wrote API responses to the disk cache — ephemeral session
- [x] fixed · simplify · `src/main.swift` load · the Nowy Świat song API served a CDN entry hours old — `t=<unix>` busts it
- [x] fixed · simplify · `src/main.swift` poll timer · stopped while the menu was open — added in `.common` mode
- [x] fixed · simplify · `src/main.swift` · dead code: turnOff, hotKeyRefs, nowPlayingTicks; debughook `off` / `rmenu`
- [x] fixed · simplify · `src/main.swift` sourceItems/symbolItem/item · three copies of the station/Spotify item loop and item builders — one helper each
- [x] fixed · simplify · `src/main.swift` hotKeys · string → switch dispatch — table of selectors through `NSApp.sendAction`
- [x] fixed · simplify · `src/main.swift` adoptSpotify · playSpotify and the broadcast handler duplicated the takeover — one method
- [x] fixed · simplify · `src/main.swift` Station.showURL · Radio 357's show URL duplicated its song URL — optional, nil = from the song response
- [x] fixed · simplify · `src/main.swift` volume defaults · ad-hoc `object(forKey:) ?? 1` reads — `register(defaults:)` once
- [x] dropped · simplify · `src/main.swift` HTML entities · decode via CFXML — the hand table covers what the NŚ homepage emits
- [x] dropped · simplify · `src/main.swift` alerts · one alert helper — three alerts with different shapes, the helper would carry flags for each
- [x] dropped · simplify · `src/main.swift` fittingSize · extension for the volume-row measure — two call sites
- [x] dropped · simplify · `src/debughook.swift` · up/down/mute duplicate the app's actions; snapshot helpers — dev instrument, not worth the churn
- [x] dropped · simplify · `tools/audiolevel.swift` · vDSP for the RMS — a test tool over a few seconds of audio
- [x] dropped · simplify · `src/main.swift` UserDefaults keys enum — a handful of keys, each used in one or two places
- [x] dropped · simplify · `src/main.swift` dashed helper · used twice
- [x] dropped · simplify · `src/main.swift` index-keyed defaults (`streamURL.<index>`) — renaming the keys loses saved custom links
- [x] dropped · simplify · `src/main.swift` mute-button image cache — negligible; the attempt was reverted
- [x] dismissed · simplify · checkmark caching / polling gating — moot after the `rowsKey` skip; polling costs ~2 MB/h (measured, accepted)
- [x] skipped · simplify (altitude) · check state via validateMenuItem — validateMenuItem doesn't run on an already-open menu, so live updates while it's open would stop; an `isPlaying(entry)` helper used instead
- [x] dismissed · simplify (altitude) · volume row via autoresizingMask — tested earlier, NSMenu never resizes an item's view
- [x] skipped · simplify (altitude) · rebuild rows only on menu open — the tooltip and the menu-bar title read the same rows; `rowsKey` skip gives the saving without the behaviour change
- [x] fixed · fix-review · `src/main.swift` retry · backoff doubled once per notification (3 → 12 after one failure) — doubles only inside the retry that runs
- [x] 🟡 fixed · fix-review · `src/main.swift` stopSpotify/applicationWillTerminate · an unmute held back by the in-flight coalescer was lost on a station switch or quit, leaving Spotify at 0 — switching away always restores the volume; quit also when a sync is in flight
- [x] 🟡 fixed · fix-review · `src/main.swift` permissionDenied · after a denial, the takeover path unticked a Spotify that was playing — only a failed „Spotify” pick from the menu unticks it
- [x] fixed · fix-review · `src/main.swift` load · the cache-buster replaced any existing query — appended instead
- [x] dropped · fix-review · `src/main.swift` applicationWillTerminate · quit waits behind a script stuck on the consent prompt or a hung Spotify (up to the 2 min AppleEvent timeout) — needs both at once at quit time
- [x] dismissed · fix-review · Spotify quit while Radio is muted keeps volume 0 — restoring it means launching Spotify; accepted

## Simplify pass
Ran /simplify (4 agents: reuse, simplification, efficiency, altitude) — 13 applied, 1 proposed, 13 dropped/dismissed/skipped; each finding folded into ## Findings (tagged simplify).

## Fix review
One fresh agent on the fix diff: every fix removes its cause, no regressions in the check marks, Dock menu, hotkeys, menu-bar title, takeover or volume coalescing. Its leftovers are folded into ## Findings (tagged fix-review); a second pass over those six lines was not needed — each is a one-line change verified in the debug build.

## Tests & suite
No test suite in this repo; verification is the debug build + context/foundation/manual-checks.md.
Debug build compiles (only the pre-existing `stringValue` deprecation warning); failed-load retry and Polish encoding verified in the debug build.
