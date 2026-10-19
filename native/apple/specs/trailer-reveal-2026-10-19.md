# Trailer reveal: play within ~2 s, hide only YouTube's centre play glyph (rows 77 + 3/21, owner 2026-10-19)

Owner: "trailers do not play cleanly again" (1018d) and earlier "trailer reveal late (about 6 s after it is picked)".
Decision (lead, owner's repeated complaint): option (a) from the ck-visual probe — reveal the trailer as soon as it
is PLAYING (build 15 did 0.5 s after PLAYING) and hide only YouTube's centre play/pause glyph
(`.player-controls-middle`, like `.ytp-bezel` already is); attribution/title strip untouched. Delete e63f693's 4.5 s
media-time hold (`AppleTrailerRevealPolicy.swift:33`). Branch `trailer-reveal` from main b8ed703.

Facts from the ck-visual probe (dev-mini:/Volumes/DevExt/dev/openstream-build/ck-visual/K/probe): with the fast rule
the page reveals in 1.78 s (Matilda 18.6), 2.06 s (hero 18.6), 3.19 s (iOS 27); YouTube's centre control showed for
2–3 s; no top title strip showed in those frames. A Mac Safari UA did not get the desktop embed.

Fix: the reveal policy returns to "PLAYING + ≤ 0.5 s" on iPhone (hero and title page), CSS hides
`.player-controls-middle` (and keeps `.ytp-bezel` hidden); the existing test that guards "nothing of YouTube's
player is hidden" is updated to "only the centre play glyph is hidden", quoting the owner. Keep the hang fix
(6225c85) and the server-trailer path untouched. tvOS/visionOS unchanged (they use server trailers / no YouTube).
Proof: iOS 18.6 owner-profile sim (protected.py): pick → reveal ≤ 2.5 s on a title page and on the Discover hero,
measured from the trace (`trailer web load` → `trailer cover fading out`), 10 fps capture showing no frame with
YouTube's top strip and the centre glyph never visible once the cover is gone; `swift test` compile lane; iOS build;
code-anti-slop; zero-byte. Builds/sims only on Dev-Mini via scripts/mini.sh
(`OPENSTREAM_MINI_DEST='~/Developer/openstream-build/lanes/trailer-reveal'`); FIFO locks; no commit.
Report: timings before/after (3 titles), change (file:line), capture paths, gates, `git status --short`.
