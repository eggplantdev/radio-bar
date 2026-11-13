# Manual verification

One living checklist for the project — each `##` section is a change; tick boxes as
you verify them in the running app. A section with unticked boxes is not verified yet.

## 2026-11-13 — initial app

- [ ] Fresh launch from Applications: the last station starts playing on its own within ~10 s.
- [ ] Close the window with ⌘W: playback continues; clicking the Dock icon brings the window back;
      ⌘Q stops it.
- [ ] Menu-bar icon → pick the other station: it switches, the checkmark moves, the menu-bar logo changes.
- [ ] Menu-bar slider at ~20%: audibly quieter; ⌃⌥↑ / ⌃⌥↓ change it from any app; scrolling on the
      icon changes it.
- [ ] ⌃⌥M from another app: sound stops and the menu-bar logo turns dimmed and crossed out; again
      restores it.
- [ ] While a song plays, the station's row in the menu shows artist – title; between songs the
      show name (and host on Radio 357), never the station's slogan.
- [ ] Menu → Spotify: the radio stops and Spotify plays; its track appears next to „Spotify";
      picking a station pauses Spotify.
- [ ] Start playback inside Spotify while the radio plays: the radio stops and the app switches to Spotify.
- [ ] Muted while on Spotify: Spotify goes silent; unmute restores its volume.
- [ ] Ustawienia → Pokazuj w Docku off: the Dock icon disappears, the menu-bar icon remains and
      „Pokazuj w pasku menu" is greyed out; turning it back on restores the Dock icon.
- [ ] Ustawienia → Zachowaj w Docku: the Dock restarts with Radio pinned; quit the app — the icon
      stays; untick it — the icon goes.
- [ ] Ustawienia → Uruchamiaj przy logowaniu on, log out and in: the app starts and plays.
- [ ] Zip from `./build.sh --zip`, downloaded on another Mac: „Otwórz mimo to" in Privacy &
      Security opens it; Zachowaj w Docku while still in Downloads asks to move it to Applications.

## 2026-11-13 — find the song in Spotify

- [ ] A station plays a song: menu → „Otwórz w Spotify" (or ⌃⌥L from any app) opens Spotify's search
      for that artist and title, with the song among the top results; the radio keeps playing.
- [ ] Between songs (only the show shows under the station): „Otwórz w Spotify" is greyed out and
      ⌃⌥L beeps.
- [ ] Spotify is the source: ⌃⌥L opens the playing track's album in Spotify with the track highlighted;
      playback isn't interrupted.

## 2026-11-13 — what's playing in the menu bar

- [ ] Fresh install: next to the logo and volume the menu bar shows the playing song, or the show
      between songs; Ustawienia → „Pokazuj, co leci, w pasku menu" is ticked.
- [ ] Untick it: only the logo and volume remain; tick it again: the song comes back.
- [ ] Muted with the option on: the crossed-out logo and the song, no volume.

## 2026-11-13 — native stream player

- [ ] Pick Radio 357, then Nowy Świat: each starts within a few seconds (Radio 357 first plays its short
      start message), the playing station's ♪ line shows the current song, and no window opens.
- [ ] Slider and the speaker icon change and mute the radio; ⌃⌥M and ⌃⌥↑ / ⌃⌥↓ too.
- [ ] Turn Wi-Fi off for ~20 s while a station plays, then on: playback resumes on its own.
- [ ] Sleep the Mac with a station playing, wake it: the station plays again.
- [ ] Ustawienia → „Nowy Świat: własny adres strumienia…" → paste a stream URL → Zapisz: if Nowy Świat is
      playing it restarts from that URL; clearing the field returns to the public stream.
- [ ] „Otwórz stronę stacji" opens the playing station's site in the browser; on Spotify the item reads
      „Otwórz Spotify" and brings Spotify forward.
