# Contributing to OpenStream

OpenStream plays media you own from your devices, network shares and media servers. It does not provide content.

## Build and test

Apple development requires a Mac with Xcode 27 and Swift 6.2 or later. From the repository root:

```sh
swift build --package-path native/apple --scratch-path /tmp/openstream-swift-build
swift test --package-path native/apple --scratch-path /tmp/openstream-swift-build
```

Open `native/apple/Apps/OpenStreamApps.xcodeproj` to build a platform app. Choose your own signing team for device builds.

For the web app, use Node 20 and pnpm:

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm build
```

## Pull requests

Keep each change focused. Describe the problem, the resulting behavior, affected platforms and the checks you ran. Add regression coverage for behavior changes and screenshots for visible changes.

Use local fixtures and media you have permission to share. Remove credentials, private server URLs and personal paths from code, logs and screenshots. Preserve dependency licences and notices. Contributions are accepted under the [Apache License 2.0](LICENSE); dependencies retain their own licences.

Follow the [Code of Conduct](CODE_OF_CONDUCT.md).
