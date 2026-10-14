# Mac Release launch on Dev-Mini (Codex, 2026-10-13)
Follow-up to specs/ship19-prep-2026-10-13.md item 2. The owner approved a new profile, now installed on Dev-Mini:
"OpenStream Mac Development 2026-10-13" (ASC 5CLWYB44Z7, devices Dev-Mini + Mac Studio, certs "Created via API"
6BCK8Q8A2P and DCJ4PSN9C6). Build the Mac app in Release config, development-signed with that profile and the
"Created via API" identity (build.keychain-db; never print its password), and prove it launches to home (log line or
screenshot in verification-artifacts/ship19-macos-launch-2026-10-13.*), then quit it. Do not create or change anything
in ASC. No commits. Gate via buildlock; close everything you open. Report Done / Not done / evidence.
