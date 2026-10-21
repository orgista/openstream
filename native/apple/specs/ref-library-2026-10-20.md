# Reference library + skill from open-source apps that do it well (owner 2026-10-20)

Owner: "we need better skills or knowledge — we can get that from apps that have something that works." Build a
pinned open-source reference library on Dev-Mini and a skill every worker loads before UI/playback/caching work.
No closed-source or DRM-protected material; licenses recorded; we copy patterns and numbers, never code.

1. Clone (shallow, pinned to a tag or commit you record) into /Volumes/DevExt/dev/rea/targets/oss/<name>/ on
   Dev-Mini: Apple "Destination Video" sample (developer.apple.com sample code; its GitHub mirror if the zip
   needs a login), jellyfin/Swiftfin, videolan/vlc-ios, xbmc/xbmc (Kodi: PVR/Live TV + disc menus only),
   kean/Nuke, onevcat/Kingfisher. Record license + commit in /Volumes/DevExt/dev/rea/targets/oss/INDEX.md.
2. For each, extract the patterns that answer OpenStream's open owner complaints, with file paths and numbers:
   - Hero / billboard on iPhone and the matching title page (art choice, crop/focal rule, height, scrim, title
     treatment, how the landing hero and the detail hero share one component) — Destination Video, Swiftfin.
   - Top bars over art (no bar at rest, buttons over art, title fading in on scroll) — Destination Video, Swiftfin.
   - Live TV: channel list, category/favorites bar (pinned how), player stage, guide grid density, tap behaviour —
     Swiftfin Live TV, Kodi PVR.
   - Image loading and caching: memory + disk cache sizes, prefetch on scroll, decode off main, request priority,
     placeholder → art transitions — Nuke, Kingfisher (and how Swiftfin uses one of them).
   - Playback stability / resume / discs over network shares — VLC iOS, Kodi.
3. Write the skill at ~/.claude/skills/openstream-reference-patterns/SKILL.md on THIS Mac (it is the skills home;
   symlinks to the work-Claude / Codex / agy skill homes per the worker-specs memory: ~/.claude-work/skills,
   ~/.codex/skills, ~/.codex-headless/skills, ~/.gemini/config/skills) + references/<topic>.md files: each topic =
   the pattern in 5–15 lines, the numbers, and "see <repo>/<path>:<line>" pointers on the mini. ≤ 150 lines in
   SKILL.md; the description says when to load it (any OpenStream hero/title page/top bar/Live/caching/playback work).
4. Add one line to native/apple/AGENTS.md §8 skills table pointing at the skill (this worktree; the lead commits).
Rules: Dev-Mini for clones/reading (network downloads of these public repos approved); no builds needed; no
commits; nothing uploaded. Report: the INDEX table, the skill's topic list, the three most useful findings for the
running jobs (hero-unify, live-oss, video-1016).
