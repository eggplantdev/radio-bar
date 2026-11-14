# Radio

Odtwarzacz Radia 357 i Radia Nowy Świat na pasku menu macOS, z przełącznikiem na Spotify.
Pokazuje, co leci, ma suwak głośności, wyciszanie i skróty klawiszowe działające z każdej aplikacji.
Lekki: zamiast stron stacji gra sam strumień (~25 MB pamięci).

## Instalacja

Wklej do Terminala (Aplikacje → Narzędzia → Terminal):

```bash
curl -fsSL https://raw.githubusercontent.com/eggplantdev/radio-bar/main/install.sh | bash
```

Skrypt pobiera najnowszą wersję do Aplikacji i ją uruchamia; ikonka pojawia się na pasku menu.
Ta sama linijka później aktualizuje aplikację. Wymaga macOS 13 lub nowszego, na Macu z Apple Silicon
albo Intelem.

Bez Terminala: pobierz `Radio.zip` z [najnowszego wydania](https://github.com/eggplantdev/radio-bar/releases/latest),
rozpakuj i przeciągnij `Radio.app` do Aplikacji. Aplikacja nie jest notaryzowana przez Apple, więc przy
pierwszym otwarciu macOS ją zablokuje: kliknij Gotowe, potem Ustawienia systemowe → Prywatność
i ochrona → przewiń w dół → **Otwórz mimo to**.

Odinstalowanie: Zakończ w menu aplikacji i przenieś `Radio.app` do Kosza.

## Obsługa

- Klik w ikonkę na pasku menu: lista stacji i Spotify z tym, co teraz leci, suwak głośności, Ustawienia.
- Klik w grającą stację pauzuje ją, kolejny wznawia na żywo.
- Przewijanie na ikonce zmienia głośność.
- Skróty z każdej aplikacji: ⌃⌥M wycisz, ⌃⌥↑ / ⌃⌥↓ głośność, ⌃⌥L otwórz grający utwór w Spotify.
- Spotify: wybór „Spotify” steruje aplikacją Spotify — za pierwszym razem macOS zapyta o zgodę.
- Patroni mogą wkleić swój osobisty link do strumienia: Ustawienia → „<stacja>: własny adres strumienia…”.

---

Everything below is for developers.

## Build

```bash
./build.sh            # build/Radio.app, universal (arm64 + x86_64), macOS 13+
./build.sh --install  # build, replace ~/Applications/Radio.app, relaunch
./build.sh --zip      # build + dist/Radio.zip for a GitHub release
./build.sh --debug    # build/Radio-debug.app, this Mac's arch only, bundle id pl.local.radio.debug, debug hook compiled in
```

Ad-hoc signed, no Xcode project — `swiftc` over `src/*.swift` + a hand-built bundle (`debughook.swift` compiles
to nothing outside `--debug`). Needs the Command Line Tools
(`xcode-select --install`). The x86_64 slice links with a harmless `libswiftCompatibilityPacks`
warning.

## Release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `resources/Info.plist`.
2. `./build.sh --zip`
3. `gh release create v<version> dist/Radio.zip --notes "…"` — the asset is always `Radio.zip`, so
   `install.sh` (`releases/latest/download/Radio.zip`) picks up every new release.

`install.sh` downloads with `curl`, which sets no quarantine flag, so the unnotarized app opens without
Gatekeeper's block and without App Translocation.

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
from linear — its loudness goes as roughly (value/100)^3.3 (measured with `audiolevel`) — so the slider
sends Spotify (slider)^(1/3.3): 45% on the slider is Spotify's 79.

„Otwórz w Spotify” (⌃⌥L) opens the current song in Spotify, where its ⊕ saves it to Liked Songs or a
playlist: the radio's song as a `spotify:search:` query, Spotify's own track by its `Track ID`. Saving it
directly would need the Web API, whose Development Mode admits only five allowlisted accounts per app.

„Szukaj na YouTube” (off by default: Ustawienia → „Pokazuj „Szukaj na YouTube””) opens a YouTube search for the same song in the
browser. YouTube has no Mac app to drive, so that's as far as it goes.

## Controls

- Menu bar: station logo + volume %; muted: the logo + a crossed-out speaker, paused: the logo + ⏸ (in place of the %); radio symbol when nothing plays (Spotify quit while it was the source). Scroll on it to
  change volume.
- Clicking the playing source (status menu, Dock menu, ⌘1 / ⌘2 / ⌘3) pauses it, again resumes it — the status
  menu stays open; a paused station reconnects to the live stream rather than resuming where it stopped.
- Global hotkeys: ⌃⌥M mute, ⌃⌥↑ / ⌃⌥↓ volume ±10%, ⌃⌥L open the song in Spotify.
- In the app: ⌘1 / ⌘2 station, ⌘M mute, ⌘↑ / ⌘↓ volume. Dock menu has stations and mute. There is no
  "off" — Zakończ stops playback; in the status menu the speaker icon mutes.
- Last station and volume persist in UserDefaults (`station`, `volume`).
- **Ustawienia** (menu-bar menu and app menu): show in menu bar, show what's playing in the menu bar (on by
  default; the song, else the show, cut at 40 characters on a notched display because an item wider than the
  space left of the notch vanishes, at 100 elsewhere — re-cut when the menu bar moves to another display), show in Dock (off = menu-bar-only
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
- **A menu never resizes an item's view** — the volume row and the row views are stretched in `menuWillOpen`.
- **A plain menu item closes the menu when clicked, and highlights in the accent blue** — every status-menu row
  is a view (`MenuRowView`, in `src/MenuViews.swift`) that draws the grey highlight, check, key equivalent and submenu arrow itself; the
  source rows keep the menu open, the rest close it on mouse-up.

## Testing tools (`tools/`)

Compile each with `swiftc tools/<name>.swift -o tools/bin/<name>`.

- `audiolevel <bundle-id> <seconds>` — peak RMS of that app's audio via ScreenCaptureKit; the real
  check that it plays, mutes, and that volume scales.
- `send <command>` — drives the debug build over a distributed notification (`station.debug`):
  `mute`, `up`, `down`, `state`, `station N`, `slider N`, `popup`, `closemenu`,
  `snap <path.png>` (status-item button), `snapmenu <path.png> [sub]` (the status menu's rows, or
  Ustawienia's, drawn offscreen), `call <selector>`, `fakesong N text`. `state` also logs the YouTube search URL. Log:
  `~/Library/Logs/radio-debug.log`.
- `upscale in.png out.png` — 8× onto a dark background, to read a `snap` capture.
- `make-icon out.png` — regenerates the app icon source (then `iconutil` → `resources/AppIcon.icns`).

The debug and release builds both drive the same Spotify and both react to its broadcasts: a Spotify
command from one flips the other to Spotify, and muting either sets Spotify's volume to 0. To play a
station in the debug build next to someone's Spotify, launch it with
`open --env RADIO_NO_SPOTIFY=1 build/Radio-debug.app` (it then ignores Spotify's broadcasts) and set
`defaults write pl.local.radio.debug volume -float 0` for a silent run that still streams.

With an auto-hiding menu bar, screenshot the button with `send snap` and the menu with `send snapmenu`.
