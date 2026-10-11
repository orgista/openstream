# REA polish pass: Apple TV heroes, Netflix icons + suggestions (owner 2026-10-11)

Owner: "Apple TV is the main GUI I am trying to emulate with heroes, and Netflix for icons [and] suggestion algorithm.
Our design is in a good place but both those apps can help us bring it to perfection."

So this is a **polish** pass, not a redesign: find the small differences between our screens and the references and
rank the fixes. Read native/apple/AGENTS.md (all of it; §3, §4.2 and §7 matter most) and load the
`reverse-engineer-anything` skill. Read the earlier reports first and do not redo them:
design/reference-apps/2026-10-11-skip-intro-next-episode.md (Apple TV evidence) and 2026-10-11-netflix-gui.md.
Owner decisions that stand: titles under posters, Continue Watching progress on artwork, accent #FF3366, textless
backdrops OK, only the approved billboard fade (no extra scrims), trailers tabled, no explainer text in the UI.

Two workers: **worker A** = Apple TV, **worker B** = Netflix. Each writes one report. Time-box about 2 hours each.

## Worker A: Apple TV app heroes and main GUI
Target: /System/Applications/TV.app on Dev-Mini (Mac TV app, same design language as tvOS; say where tvOS may differ).
Look in nibs/storyboards (`decode-interface-builder`), the asset catalogs, plists, JS/JSON templates in Resources and
frameworks it links (e.g. TVAppServices / AMP / JetEngine / ShelfKit-style frameworks under /System/Library), symbols,
strings; Ghidra only for a specific question.
Answer, with evidence: the hero/billboard (height share of screen, artwork crop/aspect, title logo vs text, logo size
and position, metadata line, buttons and their order, page dots / paging, auto-advance interval, how a hero transitions,
what focus does to it, how scrolling down collapses/fades it); the shelves under it (lockup types and aspects, sizes,
spacing, title placement, row headers, "See All", Up Next row, badges/flags); focus effects (scale, shadow, parallax,
durations, curves); colours, materials/blur, typography styles; empty/loading behaviour.
Then compare with ours (read-only): AppleTVBillboardView.swift, AppleTVBillboardMetrics.swift, AppleHeroRotation.swift,
AppleTVBillboardTitleTreatment.swift, AppleTitleLogoPolicy.swift, AppleMediaShelf.swift, AppleCatalogCardMetrics.swift,
AppleCatalogShelfPolicy.swift, AppleTVChrome.swift and the hero/shelf parts of AppleDiscoverView.swift (all under
Sources/OpenStreamApple). For each difference give ours (path:line) vs theirs (evidence).
Report: design/reference-apps/2026-10-11-appletv-hero-gui.md

## Worker B: Netflix icons and suggestion algorithm
Targets: /Volumes/DevExt/dev/rea/targets/apk/netflix-mobile/ (com.netflix.mediaclient + splits) and
apk/com.netflix.ninja.apk (TV; UI mostly in libnetflix.so, say so if unreachable).
"Icons" = (1) card artwork: which image types the client asks for (boxart, landscape, title logo, "story art",
personalised artwork ids), sizes, how the client picks one per row/context, badges on cards (New Episode, Recently
Added, Top 10, Leaving Soon) and their placement; and (2) UI iconography: play, add/check (My List), thumbs ratings,
download, info, more — shapes, sizes, states.
"Suggestion algorithm" = everything the client shows or sends about recommendations: row/list types (Because You
Watched, Top 10, Trending, Continue Watching, My List, New & Popular, genre rows), how rows and items are ordered and
de-duplicated across rows, what signals the client reports (impressions, plays, thumbs, add to list, time watched,
browse/scroll), match-%/"why this" text, profile scoping. The ranking itself is server-side: say what is client
evidence and what is not found, never guess.
Then compare with ours (read-only): AppleRecommendationRanker.swift, AppleSimilarTitleRanker.swift,
AppleHeroRotation.swift, AppleCatalogArtworkPolicy.swift, AppleArtworkResolver.swift, AppleMediaShelf.swift,
AppleCatalogShelfPolicy.swift and the rows in AppleDiscoverView.swift. We have local data only (watch history,
progress, sources, TMDB metadata incl. recommendations/similar/genres, add-on catalogs): design an on-device
suggestion approach that uses signals we have, as a ranked change list against our current rankers.
Report: design/reference-apps/2026-10-11-netflix-artwork-suggestions.md

## Every report
- Summary first, then findings with evidence locations, then "Not found", then **"Polish list"**: 8–15 ranked changes,
  each with ours (path:line) → target behaviour, impact, effort S/M/L, risk, and which platforms (tvOS/iPhone/iPad/Mac).
  Then "How this was done" (tools that worked, dead ends).
- Learn behaviour; never copy their code, strings, art, icons or assets into OpenStream. No DRM/sign-in bypass. Never
  run or install the APKs. Never upload anything. No builds, sims or emulators. No code changes.
- Write only your one report file. Do not commit or `git add`. Scratch in /tmp on the mini.
- Ghidra is heavy: check `ssh dev-mini 'cat ~/Developer/.build.lock/owner'` first; if a build holds the lock, work on
  strings/resources meanwhile. Close native sessions when done.
- If a REA tool fails for setup reasons, report the exact error and continue; do not install software.
- Final message: AGENTS.md §7 report format.
