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
