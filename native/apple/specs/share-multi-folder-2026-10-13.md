# Network shares: add several folders from one share, like Infuse (Codex, 2026-10-13)

Owner 2026-10-13: "if I add a share it lets me select one folder and that's it, I should be able to select or add
multiple like Infuse". Read AGENTS.md (workspace + native/apple) first. Stock Apple look, no explainer text.

## Today (mapped 2026-10-13)
One `.nas` `AppleSource` per folder; folder lives in `url`. Browse (`AppleNetworkShareSetupViews.swift:497-635`) only
offers "Add This Folder" → Confirm (`:659-`) → `AppleNetworkShareSetup.save` (`AppleNetworkShareSetup.swift:~376`) →
`AppleSourceStore.addNetworkShare` (`AppleSourceStore.swift:1487`), then the whole flow closes. Library ids are
`library|<source.id>|<share-relative path>`, so keys do not depend on the chosen folder.

## Build (lead's decision: option A, no schema change)
1. Keep **one source per folder**. No new fields, no migration; every progress/match/index key stays unchanged.
2. Browse: each folder row gets a select toggle (checkmark; tvOS: focusable row with a checkmark accessory, select
   with the remote's click on a separate control from drill-in, follow the existing tvOS row patterns). Keep drill-in.
   A primary button "Add Folders" / "Add N Folders" (iOS/visionOS toolbar or top section, macOS bottom bar, tvOS top
   section) commits all selected folders. Selection persists while drilling in and out across the share's tree.
   Folders already added from this share show as checked and disabled-with-checkmark (already a source).
3. Confirm page shows the list of folders with editable default names ("<folder> on <server>"); Add saves each via
   `addNetworkShare`. **One credential**: all new sources reuse the same `credentialReference` keychain entry when the
   server/user match (verify `updateNetworkCredentials` and removal keep it alive while any source references it;
   removing one source must not delete a credential another source uses).
4. Overlap: refuse selecting a folder that is inside, or contains, a selected or already-added folder of the same
   share (row shows it disabled); prevents double indexing under two source ids.
5. Sources list (`AppleSourcesSettingsView.swift:352-362`): group `.nas` sources by server+share under one header
   (share name on server), each folder a row with its existing edit page; add an "Add Folder" row under the group that
   opens Browse for that share already connected (skip Connect via saved credentials).
6. Scans: after Add, start scans for all new sources (existing per-source scanner and caps).
7. Backup/iCloud: confirm nothing changes in the snapshot shape; add a test that two folders from one share export,
   import and restore as two sources with their full addresses and working credentials.

## Tests (Swift Testing, pure where possible)
Multi-select state (select across subfolders, overlap rules, already-added), save of N folders producing N sources
with one shared credential reference, removing one keeps the other's credential, grouping policy for the list,
backup round trip. Extend UI tests if `sources.smb.addFolder` is driven anywhere (keep that id working for one-folder).

## Gates
Gate check; `scripts/mini.sh` under buildlock; serial swift test (baseline: current HEAD's count, all green); iOS,
tvOS and macOS builds (sim builds with `-derivedDataPath $HOME/Developer/sim-dd-internal`); E2E-tvOS and E2E-iOS via
`Tests/Fixtures/run-e2e.py` (baseline 20/0, 40/1 AirPlay). If a fixture SMB server exists in the E2E fixtures, add a
UI test that selects two folders and lands with two sources; else screenshot the flow on the iPhone and tvOS sims into
`verification-artifacts/share-multi-folder-2026-10-13/`. No commits. Close what you open.

## Report
Done / Not done / Gates, file:line per item, screenshots.
