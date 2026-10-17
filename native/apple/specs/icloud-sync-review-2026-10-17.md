**Verdict: FIX (1 item), everything else ships.**

1. **`Sources/OpenStreamApple/AppleConfigurationController.swift:580` — send guard can stall publishing forever.** `writeNow` returns false whenever the stored copy's `savedAt` is newer than `localSavedAt`, trusting the next `readCloud` to apply it. If that copy is one `readCloud` rejects (`decide` throws `tooLarge`, `validate()` fails, or `apply` throws), it is never applied, `localSavedAt` never catches up, and this device stamps every edit but never sends again. Before the diff the write replaced such a copy. Exact fix: hold only when the copy would actually be applied:
   ```swift
   if let stored, stored.savedAt > localSavedAt ?? .distantPast,
      (try? AppleCloudConfigurationRead.decide(data: cloud.data(forKey: Self.cloudKey), localSavedAt: localSavedAt)) != nil {
       appleTrace("configuration sync: iCloud has a newer copy, reading it before sending")
       return false
   }
   ```
   Add a controller test: cloud holds a newer but invalid payload, local edit, `syncNow()` → `publishedSnapshot` is the local copy.

Checked and clean:

- **Edit stamps** (`AppleConfigurationSyncPolicy.swift:81`): monotonic, +1 ms past the applied copy when the clock is behind. Dates encode as doubles, so the millisecond survives iCloud. Used at both stamp sites (local edit, file restore) and in `readCloud` for local-only sources and tombstones.
- **Merge, not replace** (`AppleConfigurationController.swift:507`, `AppleSourceStore.swift:2057`): both receive paths merge. A source only this device has survives every read. `merging` on send (`AppleConfigurationSnapshot.swift:193`) unions sources and tombstones, so a send cannot drop another device's source either.
- **Tombstones**: no pruning anywhere. Receive removes by incoming tombstone and skips tombstoned incoming sources; send filters tombstoned sources. A deletion cannot resurrect unless a source is re-created with the same UUID, which no code path does. Offline deletion is re-stamped and re-sent (test covers it).
- **tvOS keychain**: retry loop gated off, "N need sign-in" status, "Set Up from iPhone" shows only while sources wait. Correct per Apple's tvOS limit.
- **Buttons**: "Resume iCloud Sync" and the existing `receiveTitle`, stock, no footer or explainer text in the UI (the only sentence is a code comment). tvOS root passes `backupController` (`OpenStreamRootView.swift:778`), so the button can appear.
- **Scan is not an edit**: `validationSummary` is already nil'd by `portableSource`; `lastValidatedAt`, failure date and item count are stripped by `withoutCheckResults`.
- **Resume/hold**: `restoreFromCloud` clears both the hold and `savedAt`, so a held DevTV applies what iCloud holds. Debug flag and its enum are fully inside `#if DEBUG`, call site too.

Notes, no change required:

- `capabilities` (written by `recordValidationSuccess` for add-on manifests) is not stripped from the fingerprint, so a manifest whose resources change still counts as an edit. Rare.
- Race window: a settings edit or source rename queued when a newer copy arrives is overwritten and not re-sent (only added sources and deletions are). Same as before the diff, worker disclosed it.
- Spurious extra send when both sides hold the same tombstone id with different dates. Harmless, converges.
- I did not run the gates (read-only review, no Xcode here). The worker reports 79/79 scoped, 3480/3483 full with the 3 failures unrelated, tvOS and iOS compile builds green, zero-byte check clean. Device check on DevTV is still not done.
