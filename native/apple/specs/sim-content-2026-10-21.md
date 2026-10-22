# Owner content on the review simulators (2026-10-21)

Owner: "I have ipad up on sim but no content can we make sure these have the content please?" Today only the iOS 18.6
owner sim (iPhone 15 Pro Max iOS18, 7530ECB2-CE38-4BC6-B7E6-D4B3BEDDF48D) holds the owner's imported setup.
Goal: the owner's setup (sources, Live lineup, library/watch state, settings, Keychain items the app needs) on:
- iPad Pro 13" 8939801C-5C7F-45AD-81F9-B24465E5E5C1 (iOS 27.0) — the owner has it BOOTED in Simulator right now: keep it
  booted if you can (install/copy into the booted device); if a shutdown is unavoidable, boot it again after and
  leave the app open on Discover.
- iPhone Duo 57B18C7A-A409-4F2E-8E26-F9CEB1A0ACE8 (iOS 27.2; needs
  DEVELOPER_DIR=/Volumes/DevExt/Applications/Xcode-27.2.app/Contents/Developer for simctl on it).
- iPhone 18 Pro Max 2E61439B-4B06-48BA-96F1-8CB92A54699D (iOS 27.0).

How: reuse the snapshot mechanism in `/Volumes/DevExt/dev/openstream-build/batch-1018a/protected.py` (it captures the
owner app, app group, host state and Keychain from a sim) — take a fresh snapshot of 7530ECB2 (read-only for it), and
restore it into each target after installing the current app build (main 4963d99 Debug simulator build with add-ons,
built into your own DerivedData `~/Developer/sim-dd-simcontent`). Alternatively the app's own backup import
(`~/Developer/openstream-build/devplus/OpenStream-owner-backup.json` + its password file — never print, never copy off
the mini). Pick whichever reproduces the setup reliably; Keychain items must come along or sources won't sign in.
Verify on each target: Discover shows the owner's rows with art, Library has titles, Live lists the owner's channels and
plays one, Settings shows the sources. Screenshot each (keep in /Volumes/DevExt/dev/openstream-build/sim-content/).

After this, these three sims hold owner data: update native/apple/AGENTS.md's persistent-sims list to say so and that
any test run on them must go through protected.py (like 7530ECB2). Run tests only through protected.py.
Rules: sim lock via `~/Developer/bin/buildlock.sh` (FIFO; another worker shares the mini — queue, never kill); never
create/erase/delete simulators; keep the internal disk > 15 GB; never print secrets/passwords/tokens/URLs with
credentials; nothing leaves the mini. Report: what method, what each target shows (screenshot paths), any gaps.
