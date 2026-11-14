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

Ad-hoc signed, no Xcode project: `swiftc` over `src/*.swift` + a hand-built bundle. Needs the Command Line
Tools (`xcode-select --install`). The x86_64 slice links with a harmless `libswiftCompatibilityPacks` warning.

## Release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `resources/Info.plist`.
2. `./build.sh --zip`
3. `gh release create v<version> dist/Radio.zip --notes "…"` — keep the asset name `Radio.zip`, since
   `install.sh` downloads `releases/latest/download/Radio.zip`.

## Spotify

Driven over AppleScript. Pause and volume go through `if … is running`, so Radio never launches Spotify
except to play it. Playback started in Spotify itself takes over via the
`com.spotify.client.PlaybackStateChanged` broadcast, which also carries the track.

Spotify's `sound volume` is not linear: loudness goes as roughly (value/100)^3.3 (measured with
`audiolevel`), so the slider sends Spotify slider^(1/3.3) — 45% is Spotify's 79.

Saving a song to Liked Songs would need the Web API, whose Development Mode admits only five allowlisted
accounts per app — so „Otwórz w Spotify” only opens it there.

## Streams

`stream.radio357.pl` and `stream.nowyswiat.online/mp3`, public, MP3 128 kbps. Each redirects to a Revma
URL with a ~5 s token, so only the stable URL is stored. A patron's personal link lives in UserDefaults
(`streamURL.<index>`), never in the repo. A stalled or failed stream and every wake from sleep
reconnect after 3 s, 6, 12… up to every 60 s. Other UserDefaults keys: `station`, `volume`.

## Now playing

The playing station's song comes from the stream's ICY `StreamTitle` (filtered: `AD`, the station's
name), since the APIs lag. The others are polled — songs every 15 s, shows every 5 min:

- Radio 357: `stream.radio357.pl/now/playing.json` — `s` = "Artist - Song" (the station's slogan
  between songs), `p.n` / `p.a` = show / host.
- Nowy Świat songs: `nowyswiat.online/api/oZeta/stat` — `data.title` = artist, `data.artist` = song
  (swapped); between songs `title` is "Radio Nowy Świat". It can sit on a stale entry for hours.
- Nowy Świat show: no API; parsed from the homepage's „Teraz na antenie” slide
  (`.rns-slide-schedule-now`).

## Adding a station

Append to `stations` in `src/Stations.swift`: name, logo resource name (180×180 PNG in `resources/`),
site URL, stream URL, and song / show URLs + parsers.

## Traps (all hit while building it)

- **macOS ignores cursor changes from a background app, and a menu opened from the menu bar leaves Radio
  in the background** — the hand over the volume slider works only because `RowSlider` sets the private
  `SetsCursorInBackground` connection property (`src/MenuViews.swift`).
- **The open menu hangs from the menu-bar item's left edge** — a new song changing the item's width would
  shift it sideways, so the item's text and icon hold still while the menu is open.
- **A menu-bar item wider than the space left of the notch vanishes** — the song in the menu bar is cut at
  40 characters on a notched display, 100 elsewhere.
- **macOS 26 menus ignore `NSMenuItem.image`** — station logos ride in `attributedTitle` as an
  `NSTextAttachment`.
- **A menu never resizes an item's view** — row views are stretched in `menuWillOpen`.
- **A plain menu item closes the menu when clicked and highlights in the accent blue** — every
  status-menu row is a `MenuRowView` that draws its own grey highlight, check, key equivalent and arrow.

## Testing tools (`tools/`)

Compile each with `swiftc tools/<name>.swift -o tools/bin/<name>`.

- `audiolevel <bundle-id> <seconds>` — peak RMS of that app's audio via ScreenCaptureKit: the real
  check that it plays, mutes, and that volume scales.
- `send <command>` — drives the debug build: `mute`, `up`, `down`, `state`, `station N`, `slider N`,
  `popup`, `closemenu`, `snap <path.png>` (the menu-bar item), `snapmenu <path.png> [sub]` (the menu's
  rows drawn offscreen, no mouse), `call <selector>`, `fakesong N text`. Log: `~/Library/Logs/radio-debug.log`.
- `upscale in.png out.png` — 8× onto a dark background, to read a `snap` capture.
- `make-icon out.png` — regenerates the app icon source (then `iconutil` → `resources/AppIcon.icns`).

The debug and release builds drive the same Spotify. To test a station next to someone's Spotify, launch
`open --env RADIO_NO_SPOTIFY=1 build/Radio-debug.app` (ignores Spotify) after
`defaults write pl.local.radio.debug volume -float 0` for a silent run that still streams.
