import CoreGraphics
import Foundation
import Network

/// Opening Live shows its rows at once (owner 2026-10-22: "once live is added
/// it starts fetching at minimum like 100 channels"). After launch, and again
/// whenever a Live source is added or changed, every enabled playlist without
/// a fresh saved copy is fetched into `AppleIPTVChannelCache`, and the first
/// `leadingCount` channels' logos and listings go into the artwork and guide
/// disk caches the Live tab reads first. It waits out the launch window and
/// stays off cellular and Low Data Mode.
@MainActor
enum AppleLivePrefetch {
    nonisolated static let leadingCount = 100

    /// Reads the stores on the main actor; the downloads, parsing and the
    /// saved-copy decode run off it (`loadLeadingChannels`).
    static func run(sourceStore: AppleSourceStore, settings: AppleSettingsStore, displayScale: CGFloat) async {
        let sources = sourceStore.sources.filter { $0.kind == .liveTV && $0.isEnabled }
        guard settings.liveTVEnabled, !sources.isEmpty else { return }
        try? await Task.sleep(for: AppleLaunchWorkPolicy.remainingLaunchWindow(processAge: AppleLaunchMarks.launchAge()))
        guard !Task.isCancelled else { return }
        guard await networkAllowsPrefetch() else {
            appleTrace("live prefetch skipped: cellular or Low Data Mode")
            return
        }
        let started = ContinuousClock.now
        let playlists = sources.map { PlaylistRequest(source: $0, credentials: try? sourceStore.iptvCredentials(for: $0)) }
        let (fetched, leading) = await loadLeadingChannels(playlists,
            preferredIDs: AppleLiveWatchHistoryStore.shared.history.channelIDs + settings.favoriteLiveChannelOrder
                + settings.favoriteChannelIDs.sorted(),
            hiddenIDs: settings.hiddenLiveChannelIDs, entries: AppleChannelLineupPresets.current)
        guard !leading.isEmpty, !Task.isCancelled else { return }
        await AppleRemoteImageCache.shared.prefetch(logoRequests(leading, displayScale: displayScale))
        guard !Task.isCancelled else { return }
        // Only the leading channels: the guide's per-channel setup runs on the main actor.
        let guide = AppleIPTVGuideStore()
        guide.configure(liveSources: sources, channels: leading, sourceStore: sourceStore, settings: settings)
        await guide.refreshVisible(channelIDs: Set(leading.map(\.id)))
        appleTrace("live prefetch: \(fetched)/\(sources.count) playlists fetched, \(leading.count) channels warmed "
            + "in \(AppleLaunchMarks.milliseconds(started.duration(to: .now)))ms")
    }

    struct PlaylistRequest: Sendable {
        let source: AppleSource
        let credentials: AppleIPTVCredentials?
    }

    /// Every playlist without a fresh saved copy is fetched and saved; the
    /// saved ones are read back. Returns how many were fetched and the
    /// channels to warm.
    @concurrent
    nonisolated static func loadLeadingChannels(_ playlists: [PlaylistRequest], preferredIDs: [String],
                                                hiddenIDs: Set<String>,
                                                entries: [AppleChannelLineupEntry]) async -> (fetched: Int, leading: [AppleIPTVChannel]) {
        let client = AppleIPTVClient()
        var channels: [AppleIPTVChannel] = []
        var fetched = 0
        for playlist in playlists {
            guard !Task.isCancelled else { break }
            let source = playlist.source
            if let saved = await AppleIPTVChannelCache.shared.snapshot(for: source.id), !saved.isStale() {
                channels += saved.channels
                continue
            }
            do {
                let received = try await AppleLivePlaylistFetches.shared.channels(
                    source: source, credentials: playlist.credentials, client: client)
                channels += await AppleIPTVChannelCache.shared.reconcileAndStore(received, for: source.id)
                fetched += 1
            } catch {
                // The Live tab names the failure when it is opened.
                appleTrace("live prefetch: \(source.name) did not load")
            }
        }
        return (fetched, leadingChannels(channels, preferredIDs: preferredIDs, hiddenIDs: hiddenIDs, entries: entries))
    }

    /// The channels Live is likely to draw first: the ones watched and
    /// favourited, then the imported lineup's numbers when there is one (the
    /// order Live sorts by), then the playlists' own order, skipping hidden ones.
    nonisolated static func leadingChannels(_ channels: [AppleIPTVChannel], preferredIDs: [String],
                                            hiddenIDs: Set<String>, entries: [AppleChannelLineupEntry] = [],
                                            limit: Int = leadingCount) -> [AppleIPTVChannel] {
        var visible = channels.filter { !hiddenIDs.contains($0.id) }
        if !entries.isEmpty {
            let index = AppleChannelLineupIndex(entries)
            visible = visible.enumerated()
                .map { (number: index.match($0.element.name)?.number ?? .max, offset: $0.offset, channel: $0.element) }
                .sorted { ($0.number, $0.offset) < ($1.number, $1.offset) }
                .map(\.channel)
        }
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [AppleIPTVChannel] = []
        for channel in preferredIDs.compactMap({ byID[$0] }) + visible {
            guard result.count < limit else { break }
            if seen.insert(channel.id).inserted { result.append(channel) }
        }
        return result
    }

    /// Logos at the size this platform's Live rows decode them, so the warm
    /// entry is the one they ask for (`AppleRemoteImageCache` keys by size).
    nonisolated static func logoRequests(_ channels: [AppleIPTVChannel],
                                         displayScale: CGFloat) -> [AppleArtworkPrefetchPolicy.Request] {
        let pixels = AppleArtworkSizePolicy.bucket(size: rowLogoSize, scale: displayScale)
        return channels.compactMap(\.logoURL).map {
            AppleArtworkPrefetchPolicy.Request(url: $0, maximumPixelDimension: pixels)
        }
    }

    /// The logo frame of a Live channel row here: the Paramount+ row on
    /// iPhone and iPad, the guide rail's tile less its 6 pt padding on Apple
    /// TV (`AppleTVGuideLogoTile`), the plain row elsewhere (`AppleLiveOnNowRow`).
    nonisolated static var rowLogoSize: CGSize {
        #if os(tvOS)
        let tile = AppleTVGuideMetrics.standard.logoSize
        return CGSize(width: tile.width - 12, height: tile.height - 12)
        #elseif os(iOS)
        return AppleLiveStagePolicy.phoneLogoSize
        #else
        return CGSize(width: 48, height: 32)
        #endif
    }

    /// Wi-Fi or wired, and not in Low Data Mode.
    private static func networkAllowsPrefetch() async -> Bool {
        for await path in NWPathMonitor() {
            return path.status == .satisfied && !path.isExpensive && !path.isConstrained
        }
        return false
    }
}

/// One download per playlist at a time: Live opened while the launch
/// prefetch is still fetching waits for that download instead of starting a
/// second one, and the other way round.
actor AppleLivePlaylistFetches {
    static let shared = AppleLivePlaylistFetches()
    private var inFlight: [String: Task<[AppleIPTVChannel], any Error>] = [:]

    func channels(source: AppleSource, credentials: AppleIPTVCredentials?,
                  client: AppleIPTVClient) async throws -> [AppleIPTVChannel] {
        let key = "\(source.id.uuidString)|\(source.configurationRevision)"
        if let running = inFlight[key] { return try await running.value }
        let download = Task { try await client.channels(source: source, credentials: credentials) }
        inFlight[key] = download
        defer { inFlight[key] = nil }
        return try await download.value
    }
}
