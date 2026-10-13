# Plex lesson 12: durable EPG mapping evidence (2026-10-13)

Source: design/reference-apps/2026-10-11-plex-lessons-for-openstream.md, ranked item 12 (read its area 11 too), and
Muse research verification-artifacts/muse-2026-10-12/102-openstream-epg-channel-mapping.md and
77-openstream-iptv-m3u-xmltv-parsing.md (sourced but unverified; check claims against our code).
Do: preserve manual and provider channel identity, match confidence, time correction and cache coverage, so duplicate
names, a provider ID change, DST/offset correction and a failed refresh keep the correct guide. DVR/recording is out.
Rules: owner data safety (no loss of manual mappings, favorites, recents; read-compatible migration); pure unit tests
for every acceptance case above (fixtures, no network); serial Swift suite; E2E-tvOS 20/0 and E2E-iOS 40/1 (AirPlay
known) via Tests/Fixtures/run-e2e.py with -derivedDataPath $HOME/Developer/sim-dd-internal; gate first (other projects
use Dev-Mini); never touch OfficePlus; no commits; clean up after yourself.
