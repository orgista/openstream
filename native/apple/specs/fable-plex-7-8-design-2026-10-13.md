# Fable design: Plex lessons 7 (logical items vs files) and 8 (playback negotiation) (2026-10-13)

Both are effort L / risk high (design/reference-apps/2026-10-11-plex-lessons-for-openstream.md, ranked items 7 and 8).
Before any code, write the design. Read native/apple/AGENTS.md, that report, the Muse research
(verification-artifacts/muse-2026-10-12/99-openstream-logical-items-vs-files.md, 100-openstream-playback-negotiation.md,
65-openstream-plex-library-matching.md, 125-openstream-mkv-engine-choice.md; sourced but unverified) and the current
code (AppleMediaIndexStore, AppleMediaRecord, ApplePlaybackStore/identity, AppleLocalLibraryStore, media-server stores,
AetherPlaybackEngine and the engine factory).
Deliver `design/plex-7-8-design-2026-10-13.md`: today's model with file:line evidence; the target model; a staged
migration where every stage is shippable, reversible and keeps the owner's progress, watched history, terminals,
outbox, match overrides and Continue Watching (state exactly how each stored key maps); the negotiation rules and
fallbacks with reasons; risks; test plan per stage; what to ask the owner. No code changes, no builds, no commits.
