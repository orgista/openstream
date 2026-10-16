Review complete. Read-only, nothing edited, built or run.

**What holds up (checked against the spec and design §3.2/§5/§6/§8)**

- **Migration is non-deleting and idempotent.** `migrateVersionProgress` only adds `versionProgress.v1` scopes and the canonical item entry; old per-file keys are never rewritten (`ApplePlaybackStore.swift:477-508`). The upgrade/downgrade test proves the old keys are byte-identical afterwards. Ties resolve by `freshest` (equal clock, higher position wins), deterministic.
- **Stacks** are one version with cumulative position: the writer adds `versionOffset`, resume maps back through `location(at:)` to the right part file, part handoff rides `AppleNextEpisodeContext(isPartBoundary:)` with no card, no prompt and no autoplay gate. Overlay test covers it.
- **Jellyfin/Emby**: the chosen `MediaSource.id` is the version id, the ticket's `mediaSourceID`, and every outbox entry's `MediaSourceId` (test asserts Playing/Progress/Stopped bodies). Original first: no `MaxStreamingBitrate`, direct play ranked first, conversion only after a failure with a bounded fallback chain.
- **Snapshot/cloud**: the two new blobs are not in `AppleConfigurationSnapshot`, so the v1 format and cloud bytes are unchanged apart from one extra canonical progress entry per migrated title. Watched ticks and removals resolve through the Stage A class as the design asks.
- **UI**: "Play version…" appears only in the Play button's context menu (iOS/macOS/visionOS and the tvOS pill) and only with more than one version. Play is unchanged. The alert is "Resume from H:MM:SS?" with Resume / Start from Beginning / Cancel. No explainer text, no platform-specific API outside existing guards.

**Defects**

1. **High. Answering the resume prompt plays the requested file, not the negotiated version, and silently makes it sticky.** `AppleDiscoverView.swift:6856` stores the loop's `file` (first local candidate) as `versionResumeFile`; the prompt was raised for whichever version `presentation(for:)` picked (sticky or highest quality, `AppleLocalLibraryStore.swift:794-799`). Resume / Start from Beginning at `:9780/:9784` set `selectedLocalFile`, so the retry runs with `explicitVersion: true` (`:6835`) and `preferVersion` fires at `AppleLocalLibraryStore.swift:839`. With sticky = 4K and localFiles.first = 1080p, Play prompts for the 4K position, then plays 1080p and overwrites the sticky choice with 1080p. Owner answer 4 says sticky only on an explicit "Play version…" pick. Fix: carry the selected file/version in `AppleVersionResumeConfirmation` (`AppleMediaVersion.swift:109`) and retry with a confirmed flag, not with `explicitVersion`.

2. **Medium. Unmatched copies are merged by filename group.** `AppleLocalLibraryStore.swift:733` gives two unmatched same-title same-year files in one source a shared `li:local:` item id and records a permanent alias class joining both file keys (`mediaVersions(for:)` with `recordAliases: true`). Design §2 says an unmatched file keeps its own record id as its item; §5 says only manual or 0.95 matches create aliases, and `AppleIdentityAliasStore.record` never removes a member. Keep the `parsed.part != nil` case (a stack must share a timeline); drop the `candidates.count > 1` case or gate it on a strong match.

3. **Medium, unverified. NAS multi-part stacks now depend on an HTTP probe.** `AppleLocalLibraryStore.swift:808-826` probes every stack member through the SMB range server with `AetherEngine.probe(url:)` and throws `unavailable` if any duration is missing. Previously cd1/cd2 on a share played part by part. If the probe does not work over the range server, every NAS stack becomes unplayable. Needs a device check with a cd1/cd2 film on the share before commit.

4. **Low. Local engine fallback is skipped when another version exists.** `AppleDiscoverView.swift:6564-6578` jumps to the next version on the same engine before `ApplePlaybackEngineFallback.afterEveryStreamFailed` gets to retry on the OpenStream engine. Design §4.2 rule 7 keeps the engine fallback unchanged.

5. **Low. Server fallback always "has" a conversion.** `AppleDiscoverView.swift:6551` passes `conversionAvailable: true`; with no `TranscodingUrl` the route stays original and the same stream is replayed once before moving to the next version.

6. **Low. Sticky choice is deleted on a temporary absence.** `ApplePlaybackStore.swift:541-545` removes the preference whenever the version is not in `available`; for local files that set is "files in the current scan", so an unmounted share deletes the choice.

7. **Low. Two writers on one cache file.** `AppleMediaServerLibraryStore.swift:1096` creates a fresh `AppleMediaVersionCache()` per title page visit and writes the shared `MediaVersions-v1.json`, while `AppleLocalLibraryStore` keeps its own in-memory copy (`:39`). Cache only, no user state, but the two overwrite each other and the Jellyfin `PlaybackInfo` POST now runs on every title page open.

8. **Nit.** `stoppedSessions` (`AppleMediaServerLibraryStore.swift:213`) is written and never read. `confirmedVersionResume` stays true after a non-confirmation server error (`AppleDiscoverView.swift:6823` is only reached on success).

**Notes for the driver**

- Remote progress reporting goes live for the first time with this change: `attach(to:)` had no caller at HEAD, so `remoteProgressSink` was never set outside tests. `AppleDiscoverView.swift:6826` adds it. Good, but the Jellyfin outbox has never been exercised end to end from the title page. Spot-check a Jellyfin item on DevPlus and watch the trace for Playing/Progress/Stopped.
- `versionProgress.v1` and `preferredVersion.v1` are not backed up or synced. A restore on a new device keeps item positions and loses per-version scopes and sticky picks. Matches the design table, but worth a line in FEEDBACK.
- tvOS: a `Menu` nested inside `.contextMenu` on the pill (`AppleDiscoverView.swift:4563`). The build passes; no E2E opens it. Look at it once on the Apple TV sim.

VERDICT: FIX 1, 2, 3
