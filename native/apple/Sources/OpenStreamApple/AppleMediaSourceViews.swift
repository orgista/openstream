import SwiftUI

@MainActor
struct AppleLiveTVView: View {
    @State private var channels: [AppleIPTVChannel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playerPresentation: AppleStremioPlayerPresentation?

    let sourceStore: AppleSourceStore
    let settings: AppleSettingsStore
    let openSettings: () -> Void

    private let client = AppleIPTVClient()
    private let preparer = ApplePlaybackPreparer()

    var body: some View {
        Group {
            if isLoading, channels.isEmpty {
                ProgressView()
            } else if channels.isEmpty {
                ContentUnavailableView {
                    Label("No Live Channels", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    if let errorMessage { Text(errorMessage) }
                } actions: {
                    Button("Open Settings", action: openSettings)
                        .buttonStyle(.brandPrimary)
                }
            } else {
                List(channels) { channel in
                    Button { play(channel) } label: {
                        HStack(spacing: 12) {
                            channelLogo(channel)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name)
                                    .foregroundStyle(.primary)
                                if !channel.group.isEmpty {
                                    Text(channel.group)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                        }
                    }
                }
                .refreshable { await reload() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await reload() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task(id: sourceStore.sources) { await reload() }
        .modifier(AppleStremioPlayerPresentationModifier(presentation: $playerPresentation))
    }

    @ViewBuilder
    private func channelLogo(_ channel: AppleIPTVChannel) -> some View {
        AsyncImage(url: channel.logoURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "tv")
            }
        }
        .frame(width: 42, height: 32)
    }

    private func reload() async {
        let sources = sourceStore.sources.filter { $0.kind == .liveTV && $0.isEnabled }
        guard !sources.isEmpty else {
            channels = []
            errorMessage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        var loaded: [AppleIPTVChannel] = []
        var errors: [String] = []
        for source in sources {
            do {
                loaded.append(contentsOf: try await client.channels(source: source))
            } catch is CancellationError {
                return
            } catch {
                errors.append("\(source.name): \(error.localizedDescription)")
            }
        }
        channels = loaded
        errorMessage = errors.first
    }

    private func play(_ channel: AppleIPTVChannel) {
        errorMessage = nil
        Task { @MainActor in
            do {
                let prepared: ApplePreparedPlayback
                do {
                    let inspection = try await AppleAssetInspector.inspect(url: channel.streamURL)
                    let decision = AppleStremioPlaybackResolver.decision(for: inspection)
                    let request = gatewayConfig.map {
                        AppleGatewayTranscodeRequest(
                            config: $0,
                            source: .remoteURL(channel.streamURL),
                            maximumWidth: 3_840,
                            maximumHeight: 2_160
                        )
                    }
                    prepared = try await preparer.prepare(
                        sourceURL: channel.streamURL,
                        decision: decision,
                        inspectedAsset: inspection,
                        gatewayRequest: request
                    )
                } catch where gatewayConfig == nil {
                    // Some live providers reject AVAsset's preflight but accept
                    // the actual AVPlayer request. Let the player make that
                    // definitive attempt when no gateway is configured, carrying
                    // the playlist's User-Agent/Referer so header-gated IPTV
                    // origins don't 403.
                    prepared = ApplePreparedPlayback(
                        route: .direct(channel.streamURL),
                        url: channel.streamURL,
                        requestHeaders: channel.playbackHeaders
                    )
                }
                playerPresentation = AppleStremioPlayerPresentation(
                    title: channel.name,
                    mediaID: channel.id,
                    playback: prepared
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var gatewayConfig: AppleTranscodeGatewayConfig? {
        guard settings.gatewayEnabled else { return nil }
        return try? AppleTranscodeGatewayConfig(
            baseURL: settings.gatewayURL,
            sessionToken: settings.gatewayToken,
            isEnabled: true
        )
    }
}

@MainActor
struct AppleLibraryView: View {
    @State private var items: [AppleLibraryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playerPresentation: AppleStremioPlayerPresentation?

    let sourceStore: AppleSourceStore
    let openSettings: () -> Void
    private let scanner = AppleLibraryScanner()
    private let preparer = ApplePlaybackPreparer()

    var body: some View {
        Group {
            if isLoading, items.isEmpty {
                ProgressView()
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("Library Is Empty", systemImage: "books.vertical")
                } description: {
                    if let errorMessage { Text(errorMessage) }
                } actions: {
                    Button("Open Settings", action: openSettings)
                        .buttonStyle(.brandPrimary)
                }
            } else {
                List(items) { item in
                    Button { play(item) } label: {
                        HStack {
                            Image(systemName: "film")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .foregroundStyle(.primary)
                                Text(item.relativePath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if item.sizeBytes > 0 {
                                Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .refreshable { await reload() }
            }
        }
        .task(id: sourceStore.sources) { await reload() }
        .modifier(AppleStremioPlayerPresentationModifier(presentation: $playerPresentation))
    }

    private func reload() async {
        let sources = sourceStore.sources.filter { $0.kind == .library && $0.isEnabled }
        guard !sources.isEmpty else {
            items = []
            errorMessage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        var loaded: [AppleLibraryItem] = []
        var errors: [String] = []
        for source in sources {
            do {
                loaded.append(contentsOf: try await scanner.scan(source: source))
            } catch is CancellationError {
                return
            } catch {
                errors.append("\(source.name): \(error.localizedDescription)")
            }
        }
        items = loaded
        errorMessage = errors.first
    }

    private func play(_ item: AppleLibraryItem) {
        errorMessage = nil
        Task { @MainActor in
            do {
                guard let source = sourceStore.sources.first(where: { $0.id == item.sourceID }) else {
                    throw AppleLibrarySourceError.unavailable
                }
                let root = try AppleLibraryBookmark.resolve(source)
                let access = AppleSecurityScopedAccess(url: root)
                let inspection = try await AppleAssetInspector.inspect(url: item.url)
                let prepared = try await preparer.prepare(
                    sourceURL: item.url,
                    decision: AppleStremioPlaybackResolver.decision(for: inspection),
                    inspectedAsset: inspection,
                    gatewayRequest: nil
                )
                _ = access
                playerPresentation = AppleStremioPlayerPresentation(
                    title: item.name,
                    mediaID: item.id,
                    playback: prepared,
                    securityScopedURL: root
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
