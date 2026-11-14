# Radio

Native macOS menu-bar player for Radio 357 and Nowy Świat: AVPlayer on each station's public stream,
a station switcher, a volume slider, mute and global hotkeys. No window; Zakończ stops it.

## Build

```bash
./build.sh            # build/Radio.app, universal (arm64 + x86_64), macOS 13+
./build.sh --install  # build, replace ~/Applications/Radio.app, relaunch
./build.sh --zip      # build + dist/Radio-<version>.zip for a GitHub release
./build.sh --debug    # build/Radio-debug.app, this Mac's arch only, bundle id pl.local.radio.debug, debug hook compiled in
```

Ad-hoc signed, no Xcode project — `swiftc` over `src/*.swift` + a hand-built bundle (`debughook.swift` compiles
to nothing outside `--debug`). Needs the Command Line Tools
(`xcode-select --install`). The x86_64 slice links with a harmless `libswiftCompatibilityPacks`
warning; it has never been run on an Intel Mac.

## Release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `resources/Info.plist`.
2. `./build.sh --zip`
3. `gh release create v<version> dist/Radio-<version>.zip --notes "…"`

## Install (for someone downloading the zip)

The app isn't notarized by Apple, so macOS blocks the first launch once:

1. Unzip, drag `Radio.app` into Applications, open it — macOS says it can't verify the app; click Done.
2. System Settings → Privacy & Security → scroll down → **Open Anyway**, confirm with your password.

Terminal alternative to step 2: `xattr -dr com.apple.quarantine /Applications/Radio.app`.
Building from source (`git clone` + `./build.sh --install`) skips the block entirely.

## Spotify

When the Spotify app is installed, „Spotify” sits next to the stations (status menu, Dock menu, ⌘3).
It drives the Spotify app over AppleScript: choosing it stops the radio and plays Spotify, choosing a
station pauses Spotify, and the slider, mute and hotkeys act on whichever is playing (mute = Spotify
volume 0, since Spotify has no mute). Playback started in Spotify itself takes over from the radio —
Spotify broadcasts `com.spotify.client.PlaybackStateChanged`, which also carries the track shown in the
menu. So does a Spotify already playing when Radio starts — checked only when Spotify runs and Radio
already has the Automation permission, so a launch never starts Spotify or prompts. While Spotify is the source, „Otwórz stronę stacji” hides — „Otwórz w Spotify” already brings it forward.
Radio never launches Spotify except to play it: pause and volume go through `if … is running`. Quitting
Spotify leaves nothing playing; switching away from a muted Spotify, or quitting Radio on it, restores
Spotify's own volume (and on quit pauses it, so it doesn't turn loud by itself).

The first command triggers macOS's Automation prompt („Radio chce sterować aplikacją Spotify”); a
denial shows one alert linking to Privacy & Security → Automation and unticks Spotify. Spotify's `sound volume` is far
from linear — 20% on the slider is much quieter on Spotify than on the radio.

„Otwórz w Spotify” (⌃⌥L) opens the current song in Spotify, where its ⊕ saves it to Liked Songs or a
playlist: the radio's song as a `spotify:search:` query, Spotify's own track by its `Track ID`. Saving it
directly would need the Web API, whose Development Mode admits only five allowlisted accounts per app.

„Szukaj na YouTube” (off by default: Ustawienia → „Pokazuj „Szukaj na YouTube””) opens a YouTube search for the same song in the
browser. YouTube has no Mac app to drive, so that's as far as it goes.

## Controls

- Menu bar: station logo + volume %; muted: the logo + a crossed-out speaker, Spotify paused: the logo + ⏸ (in place of the %); radio symbol when nothing plays (Spotify quit while it was the source). Scroll on it to
  change volume.
- Global hotkeys: ⌃⌥M mute, ⌃⌥↑ / ⌃⌥↓ volume ±10%, ⌃⌥L open the song in Spotify.
- In the app: ⌘1 / ⌘2 station, ⌘M mute, ⌘↑ / ⌘↓ volume. Dock menu has stations and mute. There is no
  "off" — Zakończ stops playback; in the status menu the speaker icon mutes.
- Last station and volume persist in UserDefaults (`station`, `volume`).
- **Ustawienia** (menu-bar menu and app menu): show in menu bar, show what's playing in the menu bar (on by
  default; the song, else the show, cut at 40 characters because an item wider than the space left of the
  notch vanishes), show in Dock (off = menu-bar-only
  app; the last visible one can't be turned off), keep in Dock (edits `com.apple.dock`
  `persistent-apps` and restarts the Dock), launch at login (`SMAppService`). Keep-in-Dock and
  login refuse to run from an App Translocation copy and ask to move the app to Applications first.

## Streams

Both stations publish these URLs for third-party players, no login: `stream.radio357.pl` and
`stream.nowyswiat.online/mp3`, MP3 128 kbps — the same quality their websites give a listener who isn't
a patron. Each redirects to a Revma URL with a ~5 s token, so only the stable URL is ever stored.
Radio 357 plays every connection a start message with ads (ICY title `AD`). Ustawienia →
„<stacja>: własny adres strumienia…” swaps in a patron's personal link (Radio 357 without the start
message, Nowy Świat at 256 kbps); it stays in UserDefaults (`streamURL.<index>`), never in the repo.
A stalled stream, one that fails to load (no network yet after wake or login, a bad link) and every wake
from sleep reconnect on their own, retrying after 3 s, then 6, 12… up to every 60 s until it plays.
A custom link must start with `https://` or `http://`.

Replacing the old WKWebView of each station's website cut memory from 240–400 MB (growing ~0.5 GB/h)
to ~25 MB, and dropped the second parallel copy of the stream the website player downloaded.

## Now playing

Every row in the status menu is the logo with the show and hosts (album for Spotify; the name when unknown), then „♪ artist – song”, never truncated — lines past 340 pt wrap;
shown for every source, not just the playing one, which also fills the icon's tooltip.
Songs are polled every 15 s, shows every 5 min; the playing station's song comes from the stream's ICY
`StreamTitle` instead (filtered: `AD`, the station's name), which is live where the APIs can lag:

- Radio 357: `stream.radio357.pl/now/playing.json` — `s` = "Artist - Song" (the station's slogan
  between songs), `p.n` / `p.a` = show / host.
- Nowy Świat songs: `nowyswiat.online/api/oZeta/stat` — `data.title` = artist, `data.artist` = song
  (swapped); between songs `title` is "Radio Nowy Świat". It can sit on a stale entry for hours.
- Nowy Świat show: no API; parsed from the homepage's „Teraz na antenie" slide
  (`.rns-slide-schedule-now`).

## Adding a station

Append to `stations` in `src/Stations.swift`: name, logo resource name (180×180 PNG in `resources/`),
site URL („Otwórz stronę stacji”), stream URL, and song / show URLs + parsers.

## Traps (all hit while building it)

- **macOS 26 menus ignore `NSMenuItem.image`** — station logos ride in `attributedTitle` as an
  `NSTextAttachment`.
- **A menu never resizes an item's view** — the volume row is stretched in `menuWillOpen`.
- **`NSMenuItem.onStateImage` is centred on a multi-line row** — the checkmark is a custom image whose
  height matches the title, so it sits on the first line.

## Testing tools (`tools/`)

Compile each with `swiftc tools/<name>.swift -o tools/bin/<name>`.

- `audiolevel <bundle-id> <seconds>` — peak RMS of that app's audio via ScreenCaptureKit; the real
  check that it plays, mutes, and that volume scales.
- `send <command>` — drives the debug build over a distributed notification (`station.debug`):
  `mute`, `up`, `down`, `state`, `station N`, `slider N`, `popup`, `closemenu`,
  `snap <path.png>` (status-item button), `snaprows <path.png>` (the source rows), `snaprow <path.png>`
  (the volume row), `call <selector>`, `fakesong N text`. `state` also logs the YouTube search URL. Log:
  `~/Library/Logs/radio-debug.log`.
- `mouse move|click|rclick x y` — CGEvent mouse.
- `upscale in.png out.png` — 8× onto a dark background, to read a `snap` capture.
- `make-icon out.png` — regenerates the app icon source (then `iconutil` → `resources/AppIcon.icns`).

The debug and release builds both drive the same Spotify and both react to its broadcasts: a Spotify
command from one flips the other to Spotify, and muting either sets Spotify's volume to 0. To play a
station in the debug build next to someone's Spotify, launch it with
`open --env RADIO_NO_SPOTIFY=1 build/Radio-debug.app` (it then ignores Spotify's broadcasts) and set
`defaults write pl.local.radio.debug volume -float 0` for a silent run that still streams.

The menu bar auto-hides on this Mac, so screenshot the button with `send snap`, and the menu with
`send popup` (pops it mid-screen).
