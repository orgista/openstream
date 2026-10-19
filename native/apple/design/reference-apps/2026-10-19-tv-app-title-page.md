# Apple TV title-page reference — 2026-10-19

- Required target: Dev-Mini, iPhone 15 Pro Max, iOS 18.6, `7530ECB2-CE38-4BC6-B7E6-D4B3BEDDF48D`.
- Observation ran under the main build lock through this lane's `scripts/mini.sh` destination.
- `protected.py` saved and restored the owner's app, app/group data, host state and Keychain.
- Restoration hashes verified: Dev-Mini `/tmp/batch1018e-owner-ryzpk17o/restoration.json`.
- Mobile MCP enumerated the simulator, but launch and element-list calls failed: “Agent is not installed on the device”.
- `xcrun simctl listapps` lists no `com.apple.tv` application.
- The runtime's `Applications/AppleTV.app` contains localization resources and PlugIns only; no `Info.plist` or main executable.
- Direct `simctl launch … com.apple.tv` failed with `FBSOpenApplicationServiceErrorDomain`, code 4.
- Therefore the spec's assertion that TV.app is preinstalled and runnable on this simulator is unconfirmed and contradicted by these checks.
- Film/show navigation, back-button treatment, scroll transitions, hero inset and scrim measurements remain unknown.
- No Apple TV screenshots or element hierarchy could be collected; no substitute behavior has been inferred.
- OpenStream comparison and implementation await a usable reference: Apple TV on DevPlus or owner-provided film/show evidence.
- Source review: title chrome is in `AppleTabToolbarContext.swift`; scrolled status protection is in `AppleStatusBarShield.swift`.
- Discover/Library's solid navigation background is configured in `AppleAlignedTabTitle.swift`; those root bars are outside this job.
- Before edits: parallel Swift gate failed two playback-server tests; serial gate passed 3,596 tests in 446 suites.
