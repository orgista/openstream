# iCloud sync: sources don't match across devices (owner 2026-10-17: "rill should have them with iCloud sync since I
# have it on my iPhone so that lies another problem")
Evidence (traces on the mini, /Volumes/DevExt/dev/openstream-build/traces/): owner iPhone (owner-iphone-1017.log) sends
"3 sources to iCloud" repeatedly (publishes=true); OfficePlus (officeplus-1017.log, last app session 10-16 05:00Z)
"applied 9 sources from iCloud", then "read: not newer", publishes=false. DevTV is "held from iCloud" by the
atv-slowness debug restore (AppleDebugBackupRestore), so it receives nothing. Earlier owner report (OWNER-TODO
2026-10-08): "iCloud sync still looks broken".
Find and fix, with tests:
1. Which copy wins: newer-wins by what clock? Can a receiver with a local copy consider the iPhone's newer set "not
   newer"? Device clocks, modified-date vs server change tag.
2. Deletions: a source removed on the publisher must disappear on receivers (tombstones), without deleting a
   receiver's local-only sources unexpectedly.
3. Media servers (Rill/Jellyfin, Plex) included, and their passwords via iCloud Keychain (waiting-for-password state).
4. Apple TV receive path (TV never publishes): applies on launch/foreground; status in Settings › Sources › iCloud Sync.
Device check: release DevTV's hold (Settings › Restore from iCloud or a Debug launch flag), confirm DevTV and the
owner's iPhone use the same Apple ID (report if not; never sign anything in/out), open the app on both, compare.
DevPlus only if on the same Apple ID. OfficePlus: read its trace only (no launching/driving; install-only 09-17).
Never print tokens/passwords. Scoped gates (sync unit tests, iOS/tvOS builds, E2E sync tests). No commits.
