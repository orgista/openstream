# tvOS title page + library first-launch fixes from the build-20 full verification (lead, 12:30) — work Claude
Guardrails: no git state changes, no uploads, never print credentials/signing identifiers (never cat signing scripts, env.sh, ExportOptions, ~/.asc, owner-build.sh). Owner-data sims via protected.py only; DevPlus/DevTV allowed with state backup/restore as the live-cold job did; OfficePlus never. Heavy jobs via buildlock.sh / buildlock-compile.sh, FOREGROUND, never end your turn with a job running. Keep the mini internal disk >= 15 GB. Read AGENTS.md; code-anti-slop on your diff; openstream-reference-patterns + swiftui-pro skills. Evidence for the bugs: dev-mini /Volumes/DevExt/dev/openstream-build/fullverify-b20/ (REPORT.md, shots/, logs/). Bounded ~2.5 h. Report: Done / Not done / Gates run / Diff / Notes for the reviewer.
1. B4: tvOS movie title page (DevTV, Rampage via Library > Continue Watching): the overview sits at y=1062/1080 and
   nothing is focusable below the button row, so the description and trailers/cast rows can't be reached. Make the
   page scroll with focus (focusable overview/rows below the buttons), like the Apple TV app. swift-focusengine-pro skill.
   UI test on the tvOS sim + DevTV screenshot (restore DevTV state).
2. B5: after a fresh install the first share scan runs under the Local Network prompt, fails, and Library keeps
   "This folder is no longer available." until Refresh. Rescan automatically once permission is granted / the first
   successful network call, and word an unreachable SMB share as unreachable (not gone)
   (AppleLocalLibraryStore.swift:520, AppleLibrary.swift:12). Unit test the retry rule.
3. B9: remove explainer/status text per the owner rule (no explainer text): the Sources lineup hint "Import a lineup file
   to organise channels by number and category.", tvOS guide "Showing 300 of 3,963 channels", Settings "Needs a TMDB API
   key" (show the control state instead). Keep the actions themselves.
4. B10: "Test Connection" → "Test" in Add Live TV (AppleSettingsViews.swift:1199, AppleSourcesSettingsView.swift:1232).
Gates: serial swift test; iOS + tvOS builds + compliance; tvOS sim focus test; iOS 18.6 Sources/Library tests via protected.py.

## Round 2 (lead, 14:15): API review says fix first. Uncommitted here. Bounded ~75 min.
Review: /private/tmp/claude-501/-Volumes-Files-Projects/openstream-lead/api-tvlib.txt (read it).
0. Owner decision 09-14 stands for series: on a series page Down from Play goes to Episodes (no synopsis stop). The
   synopsis focus stop is for movie pages (no Episodes row) only. Test both.
1. .focusEffectDisabled() on the synopsis and credit card (no grey tile/halo) — DevTV screenshot proof.
2. Classify only network-level failures as unreachable (auth/path errors keep their own wording, no retry). Also reload
   when the app becomes active / the network path becomes satisfied if cheap; say what you chose.
3. Retries must not flash a spinner or clear the grid, and must not affect the launch scan stamp — verify + note.
4. Store-level test with a fake failing NAS scan: unreachable status, counter reset after a clean scan, Refresh cancels a
   pending retry, reset clears it.
5. Grep UI tests and scripts/ for lineup.empty, live.cap.notice, "Test Connection" and fix leftovers.
6. iPhone/iPad keep the channel count line (owner 09-17) — state it in the report; no change.
7. Accessibility labels on cast portraits.
Gates: serial swift test; iOS + tvOS builds + compliance; tvOS sim focus tests (movie + series); DevTV re-shot (restore state).
