# Radio

Native macOS wrapper for Radio 357 and Nowy Świat: one WKWebView app with a menu-bar station switcher,
a volume slider, mute and global hotkeys. Closing the window keeps it playing; only Quit stops it.

## Build

```bash
./build.sh            # build/Radio.app, universal (arm64 + x86_64), macOS 13+
./build.sh --install  # build, replace ~/Applications/Radio.app, relaunch
./build.sh --zip      # build + dist/Radio-<version>.zip for a GitHub release
./build.sh --debug    # build/Radio-debug.app, this Mac's arch only, bundle id pl.local.radio.debug, debug hook compiled in
```

Ad-hoc signed, no Xcode project — `swiftc` + a hand-built bundle. Needs the Command Line Tools
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
3. Accept each station's cookie banner once.

Terminal alternative to step 2: `xattr -dr com.apple.quarantine /Applications/Radio.app`.
Building from source (`git clone` + `./build.sh --install`) skips the block entirely.

## Spotify

When the Spotify app is installed, „Spotify” sits next to the stations (status menu, Dock menu, ⌘3).
It drives the Spotify app over AppleScript: choosing it stops the radio and plays Spotify, choosing a
station pauses Spotify, and the slider, mute and hotkeys act on whichever is playing (mute = Spotify
volume 0, since Spotify has no mute). Playback started in Spotify itself takes over from the radio —
Spotify broadcasts `com.spotify.client.PlaybackStateChanged`, which also carries the track shown in the
menu. „Pokaż okno” brings Spotify forward while it's the source.

The first command triggers macOS's Automation prompt („Radio chce sterować aplikacją Spotify”); a
denial shows an alert linking to Privacy & Security → Automation. Spotify's `sound volume` is far
from linear — 20% on the slider is much quieter on Spotify than on the radio.

## Controls

- Menu bar: station logo + volume %, the same logo dimmed and crossed out when muted, radio symbol when off. Scroll on it to
  change volume.
- Global hotkeys: ⌃⌥M mute, ⌃⌥↑ / ⌃⌥↓ volume ±10%.
- In the app: ⌘1 / ⌘2 station, ⌘0 off, ⌘M mute, ⌘↑ / ⌘↓ volume. Dock menu has stations, mute, off.
- Last station and volume persist in UserDefaults (`station`, `volume`).
- **Ustawienia** (menu-bar menu and app menu): show in menu bar, show in Dock (off = menu-bar-only
  app; the last visible one can't be turned off), keep in Dock (edits `com.apple.dock`
  `persistent-apps` and restarts the Dock), launch at login (`SMAppService`). Keep-in-Dock and
  login refuse to run from an App Translocation copy and ask to move the app to Applications first.

## Now playing

The current station's track (or show, between songs) sits next to its name in the status menu and in the
icon's tooltip, polled every 15 s from the endpoints the sites themselves use:
`stream.radio357.pl/now/playing.json` (`s` = "Artist - Song", `p.n` = show) and
`nowyswiat.online/api/oZeta/stat` (`data.title` = artist, `data.artist` = song — swapped; during a show
`title` is "Radio Nowy Świat", which is dropped). Nowy Świat's own player only fills its title while the
page is visible, so reading the DOM doesn't work.

## Adding a station

Append to `stations` in `src/main.swift`: name, logo resource name (180×180 PNG in `resources/`),
site URL, a `startScript` that starts that site's player, and a now-playing URL + parser.

## Traps (all hit while building it)

- **Autostart:** a page-side `setTimeout(() => audio.play())` is refused as not a user gesture;
  `evaluateJavaScript` from Swift counts as one, so retries are driven from Swift.
- **`didFinish` never fires on radio357.pl** (it keeps loading resources) — autostart hangs off `didCommit`.
- **Detached `new Audio()`** (Nowy Świat) isn't in the DOM; the injected script patches
  `HTMLMediaElement.prototype.play` to track every element for volume control.
- **Mute** uses WebKit's private `_setPageMuted:` (JS fallback). Fine for direct distribution; the
  Mac App Store would reject it.
- **macOS 26 menus ignore `NSMenuItem.image`** — station logos ride in `attributedTitle` as an
  `NSTextAttachment`.
- First run shows each site's cookie banner (CookieLawInfo / Cookiebot); answer it once, it persists.

## Testing tools (`tools/`)

Compile each with `swiftc tools/<name>.swift -o tools/bin/<name>`.

- `audiolevel <bundle-id> <seconds>` — peak RMS of that app's audio via ScreenCaptureKit; the real
  check that it plays, mutes, and that volume scales.
- `send <command>` — drives the debug build over a distributed notification (`station.debug`):
  `mute`, `up`, `down`, `off`, `state`, `station N`, `slider N`, `popup`, `closemenu`,
  `snap <path.png>` (status-item button), anything else is evaluated as JS. Log:
  `~/Library/Logs/radio-debug.log`.
- `mouse move|click|rclick x y` — CGEvent mouse.
- `upscale in.png out.png` — 8× onto a dark background, to read a `snap` capture.
- `make-icon out.png` — regenerates the app icon source (then `iconutil` → `resources/AppIcon.icns`).

The debug and release builds both drive the same Spotify and both react to its broadcasts: a Spotify
command from one flips the other to Spotify, and muting either sets Spotify's volume to 0. Quit the
release build before testing anything near Spotify.

The menu bar auto-hides on this Mac, so screenshot the button with `send snap`, and the menu with
`send popup` (pops it mid-screen).
