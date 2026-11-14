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
- [ ] ⌃⌥M from another app: sound stops and the menu bar shows the logo and a crossed-out speaker instead of the %; again
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
- [ ] Muted with the option on: the logo, a crossed-out speaker and the song, no volume.

## 2026-11-13 — native stream player

- [ ] Pick Radio 357, then Nowy Świat: each starts within a few seconds (Radio 357 first plays its short
      start message), the playing station's ♪ line shows the current song, and no window opens.
- [ ] Slider and the speaker icon change and mute the radio; ⌃⌥M and ⌃⌥↑ / ⌃⌥↓ too.
- [ ] Turn Wi-Fi off for ~20 s while a station plays, then on: playback resumes on its own.
- [ ] Sleep the Mac with a station playing, wake it: the station plays again.
- [ ] Ustawienia → „Nowy Świat: własny adres strumienia…" → paste a stream URL → Zapisz: if Nowy Świat is
      playing it restarts from that URL; clearing the field returns to the public stream.
- [ ] „Otwórz stronę stacji" opens the playing station's site in the browser; on Spotify the item is gone
      and only „Otwórz w Spotify" remains.

## 2026-11-13 — search the song on YouTube

- [ ] Fresh install: no „Szukaj na YouTube" in the menu; Ustawienia → „Pokazuj „Szukaj na YouTube”" adds it
      under „Otwórz w Spotify", unticking removes it.
- [ ] A station plays a song: menu → „Szukaj na YouTube" opens YouTube's search for that artist and title
      in the browser; the radio keeps playing.
- [ ] Between songs: „Szukaj na YouTube" is greyed out.
- [ ] Spotify is the source: „Szukaj na YouTube" searches for Spotify's current track.

## 2026-11-13 — review-gate fixes

- [ ] Wi-Fi off, pick a station, wait ~10 s, Wi-Fi on: the station starts playing on its own within a minute.
- [ ] Spotify is the source; quit Spotify: Spotify loses its tick; then scroll on the menu-bar icon or press ⌃⌥M —
      Spotify does not launch.
- [ ] Spotify is the source; mute, then pick Radio 357; open Spotify and press play: it is audible.
- [ ] Spotify is the source and muted; quit Radio: Spotify pauses, and pressing play in Spotify is audible.
- [ ] Slow two-finger scroll on the menu-bar icon: the volume moves by single percents.
- [ ] Ustawienia → „Radio 357: własny adres strumienia…" → type `radio357.pl/abc` → Zapisz: the dialog stays
      with a message about https://; the old value is kept.
- [ ] In the same dialog ⌘X cuts and ⌘Z undoes.
- [ ] A Nowy Świat song shown under its row matches what the station is playing, not an hours-old entry.

## 2026-11-13 — Spotify playing at launch, split into files

- [ ] Spotify plays, Radio was last on a station: quit Radio, open it again — Spotify keeps playing, Radio shows
      Spotify ticked with its track, no station starts.
- [ ] Spotify paused: open Radio — the last station plays.
- [ ] Spotify is the source; press pause in Spotify: the menu bar shows the Spotify logo and ⏸ instead of the %;
      play again: the % comes back.
- [ ] A station plays; click its row in the menu: it goes silent, the menu bar shows ⏸ and the menu stays open;
      click again: it plays live. Click another station: it switches, the menu stays open, the tick moves.
      Hovering any row — stations, „Otwórz stronę stacji”, Ustawienia and its submenu, Zakończ, the volume row — lays the same faint grey rounded highlight under it, like the Wi-Fi menu; never blue. Hovering Ustawienia opens its submenu with the ticks in place. The same on Spotify: Spotify pauses and resumes.
- [ ] On the ultra-wide display a long song shows up to 100 characters in the menu bar; move the menu bar to the
      laptop display (click there): it is cut at 40 and stays visible left of the notch.
- [ ] The gap between the logo and the % matches the gaps around „·”.
- [ ] Menu → hover the volume bar: a white knob grows in over a moment (the bar keeps its colour) and the pointer becomes a hand;
      click or drag anywhere in the row's height sets the volume; moving away hides the knob.
- [ ] Every earlier check in this file still passes (code moved into several files, behaviour unchanged):
      station switch, Spotify takeover, mute, Ustawienia, Dock menu.
