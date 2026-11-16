# AGENTS.md

Build, debug tools and the traps hit so far: `@README.md`.

## Shipping a change

- Finish every change with `./build.sh --install`: the owner uses the installed app all day, so that is how a change gets checked.
- Then commit it and push `main` (`git push origin main`, as a single command). This repo is on the push hook's whitelist, so the global "never push main" rule does not apply here.
- There's no manual-checks registry. Don't create one, even when the commit skill asks for it.

## Verifying

- Never click, send keys to or `send` commands at the installed `Radio.app`: its menu would pop open while the owner is working. Verify in the debug build (`./build.sh --debug`, then `tools/bin/send state | snapmenu`).
- Before launching the debug build, run `defaults write pl.local.radio.debug station -int 0`, then `open --env RADIO_NO_SPOTIFY=1`. Saved on Spotify, it would pause the owner's Spotify and set its volume to 0.
- Both builds run an executable called `Radio`. To stop the debug one, use `pkill -f "Radio-debug.app/Contents/MacOS/Radio"`, never `pkill -x Radio`.
