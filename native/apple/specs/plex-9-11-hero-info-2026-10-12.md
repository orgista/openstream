# Plex lessons 9 and 11, plus one hero fix (2026-10-12)

Sources: design/reference-apps/2026-10-11-plex-lessons-for-openstream.md ranked change list items 9 and 11.
Claude picked these under the keep-building rule. Read native/apple/AGENTS.md and the report.

9. Richer provider hubs through existing row policies: use the Jellyfin/Plex/Emby home hubs we can already reach
   (e.g. recently added, on deck/next up, genre hubs) as rows, with eligibility, paging and refresh of only the
   affected row; existing custom row order, empty/duplicate-heading handling and title routes unchanged; an
   unavailable or empty hub falls back silently. Fake-server tests, no network.
11. Approved chapter markers get typed provenance (source, media version, validated timing): invalid, duplicate or
   outdated markers never seek past the media; content without chapters never gets a fabricated intro. Intro
   fingerprinting stays tabled. Tests.
Hero fix. tvOS hero (AppleHomeTVHeroActions, AppleHomeTVHeroCarousel.swift ~130-165): when the primary pill is
   "Details" (no playable source), it and the round info button do the same thing with the same icon. Drop the round
   info button in that case (keep My List); unchanged when the primary is Play. Same check for the iPhone/iPad/Mac
   hero action rows. Tests on the pure policy if one decides the buttons.

Rules: as specs/todo-finish-2026-10-09.md "Rules", except **do not commit** (the lead commits). Dev-Mini via
scripts/mini.sh + buildlock.sh; full Swift suite green >= 3139 plus new tests (serial if captions tests time out);
iOS + tvOS builds. Never print server URLs, tokens or user names. No uploads, no git stash/checkout/reset, don't
touch native/google-tv or AppleSMBRangeServer.swift. One OWNER-TODO.md Done line per item. End with done / not done.
