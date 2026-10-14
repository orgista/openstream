# iPhone hero follow-ups (Fable review of ef4a4d3) + Library hero delay (2026-10-14)

Read native/apple/AGENTS.md and `verification-artifacts/fable-review-hero-2026-10-14.md` first.
1. MEDIUM: trailer cover render off the main actor and only when a trailer will play (finding 1: CGContext +
   fillRect for keyArt/backdrop in a detached task; ImageRenderer only for posterCard, after the 2 s start delay once
   a trailer key exists).
2. LOW: `appleHeroIsCovered` set where a sheet/fullScreenCover can sit over a visible hero, removed from Search
   (finding 2).
3. LOW: the top-bias test at SE width (finding 3).
4. LOW: iOS 18 nav bar over the hero top (finding 4): check on the iOS 18.6 sim `7530ECB2…`; apply the iOS<26
   `toolbarBackgroundVisibility(.hidden …)` only if it is the cause.
5. Library hero art ~12 s (≈4.9 s library index publish + ≈5.3 s art): find the cause from the traces added in
   ef4a4d3 and fix it if contained; target art ≤ 1.5 s after the library publishes, black placeholder never > 2 s.
Codex owns AppleLibraryMetadataResolver, AppleLibraryTitleParser, AppleLocalLibraryStore, AppleMetadataClient,
AppleLibraryFixMatch* and two Fix Match lines in AppleDiscoverView: do not touch them; validate on a copy with those
at HEAD if they do not compile. Gates: serial Swift suite, iOS + tvOS builds with recompile greps, E2E-iOS 40/1 and
E2E-tvOS 20/0 via scripts/mini.sh/buildlock; simulator builds with -derivedDataPath $HOME/Developer/sim-dd-internal;
screenshots AFTER3-* in verification-artifacts/iphone-hero-2026-10-14/. No commits. Report per AGENTS.md §7.
