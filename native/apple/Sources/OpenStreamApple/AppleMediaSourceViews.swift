import AVKit
import SwiftUI
#if !os(macOS)
import UIKit
#endif

@MainActor
final class AppleReloadGate {
    private(set) var isRunning = false

    func begin() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    func end() { isRunning = false }
}

@MainActor
struct AppleLiveTVView: View {
    @State private var channels: [AppleIPTVChannel] = []
    @State private var channelGroups: [AppleIPTVChannelGroup] = []
    @State private var channelSnapshot = AppleLiveChannelSnapshot(channels: [], channelIDs: [], categories: ["All", "Favorites"])
    @State private var channelsRevision = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var query = ""
    @State private var selectedCategory = "All"
    @State private var selectedChannel: AppleIPTVChannel?
    @State private var playbackRevision = 0
    @State private var fullScreenRevision = 0
    @AppStorage("openstream.live.lastChannelID") private var lastWatchedChannelID = ""
    @State private var guideStore = AppleIPTVGuideStore()
    @State private var premierGuide: [AppleChannelLineupEntry] = []
    @State private var lineupIndex = AppleChannelLineupIndex([])
    @State private var playbackCoordinator = ApplePlaybackCoordinator()
    @State private var configuredEngine: ApplePlaybackEngineKind?
    @FocusState private var focusedChannelID: String?
    @State private var reloadGate = AppleReloadGate()
    @State private var sharePlay = AppleSharePlaySessionStore.shared
    @State private var sharedChannelChoices: [AppleIPTVChannel] = []
    @State private var showsSharedChannelChoices = false
    @State private var showsSearch = false
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var viewportSize: CGSize = .zero
    #endif
    #if os(tvOS)
    @State private var tvPlayer: AppleTVLivePlayerPresentation?
    @State private var tvFocusRestore = 0
    /// Owned here, not by the player screen: switching to a channel that
    /// needs the other engine rebuilds the screen, and the footer must stay
    /// open across that rebuild.
    // The channel strip only appears on a remote swipe, which no headless tool
    // can send, so it could never be checked in a capture. This opens it at
    // launch for review builds.
    #if DEBUG
    @State private var tvFooter = AppleTVLiveFooterState(
        phase: UserDefaults.standard.bool(forKey: "OpenStreamLiveFooterVisible") ? .shown : .hidden
    )
    #else
    @State private var tvFooter = AppleTVLiveFooterState()
    #endif
    #endif

    let sourceStore: AppleSourceStore
    let mediaIndex: AppleMediaIndexStore
    let settings: AppleSettingsStore
    let openSettings: () -> Void

    private let client = AppleIPTVClient()

    var body: some View {
        @Bindable var settings = settings

        Group {
            if isLoading, channels.isEmpty {
                ProgressView()
            } else if channels.isEmpty {
                AppleSourceEmptyState(
                    title: errorMessage ?? "No Live Channels",
                    actionTitle: "Open Settings",
                    action: openSettings
                )
            } else {
                #if os(tvOS)
                tvGuide
                #else
                #if os(iOS)
                let isPad = UIDevice.current.userInterfaceIdiom == .pad
                let isLandscape = isPad && (verticalSizeClass == .compact || viewportSize.width > viewportSize.height)
                #else
                let isLandscape = false
                #endif

                let videoColumn = VStack(spacing: 0) {
                    if let pendingProbe {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Connecting to \(pendingProbe.channel.name)…")
                                .lineLimit(2)
                        }
                        .font(.subheadline)
                        .padding(12)
                        .accessibilityIdentifier("live.connecting")
                    }
                    if let selectedChannel {
                        ZStack(alignment: .topTrailing) {
                            AppleLiveInlinePlayer(
                                request: selectedChannel.playbackRequest(),
                                coordinator: playbackCoordinator,
                                playbackRevision: playbackRevision,
                                fullScreenRevision: fullScreenRevision,
                                logoURL: selectedChannel.logoURL,
                                sharedChannel: try? AppleSharePlayChannel(channel: selectedChannel),
                                sharePlay: sharePlay,
                                liveChannel: selectedChannel,
                                channels: channelSnapshot.channels,
                                guide: guideStore.guide(for: channelSnapshot.channelIDs),
                                onSwitchChannel: { startChannel($0, shareSelection: true, present: false) }
                            )
                            .id(ObjectIdentifier(playbackCoordinator))
                            
                            #if os(iOS)
                            if isPad && verticalSizeClass == .compact {
                                Button {
                                    showsSearch = true
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .frame(width: 44, height: 44)
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.3), radius: 2)
                                }
                                .padding()
                            }
                            #endif
                        }
                        #if os(iOS)
                        .livePinnedPlayerLayout(viewportSize: viewportSize, verticalSizeClass: verticalSizeClass)
                        #else
                        .livePinnedPlayerLayout()
                        #endif
                        .accessibilityLabel("Live player for \(selectedChannel.name)")
                    } else {
                        lastWatchedCard
                    }
                    if isLandscape {
                        Spacer(minLength: 0)
                    }
                }

                let guideColumn = VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppleDesignTokens.spacingLarge) {
                            ForEach(channelSnapshot.categories, id: \.self) { category in
                                Button { selectedCategory = category } label: {
                                    Text(category)
                                        .font(AppleDesignTokens.fontSubheadline)
                                        .foregroundStyle(selectedCategory == category ? AppleDesignTokens.textPrimary : AppleDesignTokens.textSecondary)
                                        .padding(.vertical, 10)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(.rect)
                                }
                                .overlay(alignment: .bottom) {
                                    Capsule().fill(AppleDesignTokens.brandAccent)
                                        .frame(height: 2)
                                        .opacity(selectedCategory == category ? 1 : 0)
                                        .allowsHitTesting(false)
                                }
                                // The underline and the brighter text say which
                                // category is showing; neither reaches
                                // VoiceOver, which read all eleven pills
                                // identically (2026-09-19).
                                .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, AppleDesignTokens.spacingMedium)
                    }
                    .scrollIndicators(.hidden)

                    // One line, only when the cap kept channels off the guide.
                    // Not an explainer: the count is the whole message, and the
                    // way to narrow it is the package picker the viewer already
                    // has. Silent truncation was the thing to avoid.
                    if channelSnapshot.hiddenCount > 0 {
                        Text("Showing \(channelSnapshot.channels.count) of \(channelSnapshot.channels.count + channelSnapshot.hiddenCount) channels")
                            .font(AppleDesignTokens.fontCaption)
                            .foregroundStyle(AppleDesignTokens.textSecondary)
                            .padding(.horizontal, AppleDesignTokens.spacingMedium)
                            .accessibilityIdentifier("live.cap.notice")
                    }

                    AppleIPTVGuideGridView(
                        channels: channelSnapshot.channels,
                        guide: guideStore.guide(for: channelSnapshot.channelIDs),
                        guideRevision: guideStore.revision,
                        entries: premierGuide,
                        favoriteIDs: settings.favoriteChannelIDs,
                        onSelect: play,
                        onToggleFavorite: toggleFavorite,
                        onVisibleChannels: refreshGuide
                    )
                    .safeAreaPadding(.bottom, 8)
                }

                Group {
                    if isLandscape {
                        ScrollView(.vertical) {
                            VStack(spacing: 0) {
                                videoColumn
                                guideColumn
                                    .containerRelativeFrame(.vertical, count: 1, span: 1, spacing: 0)
                            }
                        }
                        .scrollIndicators(.hidden)
                    } else {
                        VStack(spacing: 0) {
                            videoColumn
                            guideColumn
                        }
                    }
                }
                #if os(iOS)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { viewportSize = $0 }
                #endif
                #endif
            }
        }
.modifier(AppleLiveSearchModifier(isEnabled: !channels.isEmpty, query: $query, selectionRevision: playbackRevision, showsSearch: $showsSearch) {
            AppleIPTVGuideGridView(
                channels: channelSnapshot.channels,
                guide: guideStore.guide(for: channelSnapshot.channelIDs),
                guideRevision: guideStore.revision,
                entries: premierGuide,
                favoriteIDs: settings.favoriteChannelIDs,
                onSelect: play,
                onToggleFavorite: toggleFavorite,
                onVisibleChannels: refreshGuide
            )
        })
        #if os(iOS)
        .toolbar(UIDevice.current.userInterfaceIdiom == .pad && verticalSizeClass == .compact ? .hidden : .visible, for: .navigationBar)
        #endif
        .task(id: settings.playbackEngine) {
            guard configuredEngine != settings.playbackEngine else { return }
            configuredEngine = settings.playbackEngine
            playbackCoordinator.stop()
            let (engine, fellBack) = ApplePlaybackEngineFactory.make(preferred: settings.playbackEngine)
            settings.engineFellBackToNative = fellBack
            engine.applyCaptionPreferences(
            preference: settings.captionsPreference,
            languages: settings.subtitleLanguages,
            languagesAreExplicit: settings.hasChosenSubtitleLanguages)
            playbackCoordinator = ApplePlaybackCoordinator(engine: engine)
        }
        .onChange(of: settings.captionsPreference) { _, preference in
            playbackCoordinator.engine.applyCaptionPreference(preference)
        }
        .task(id: reloadIdentity) { await reload() }
        .task(id: projectionIdentity) {
            await rebuildChannelGroups()
        }
        .task(id: "shareplay:\(sharePlay.revision):\(channelsRevision)") {
            resolveSharedChannel()
        }
        .confirmationDialog("Choose the source for this channel", isPresented: $showsSharedChannelChoices, titleVisibility: .visible) {
            ForEach(sharedChannelChoices) { channel in
                Button(sourceStore.sources.first(where: { $0.id == channel.sourceID })?.name ?? channel.name) {
                    startChannel(channel, shareSelection: false)
                }
            }
            Button("Leave SharePlay", role: .cancel) { sharePlay.leave() }
        }
        .alert("SharePlay", isPresented: Binding(
            get: { sharePlay.message != nil },
            set: { if !$0 { sharePlay.message = nil } }
        )) {
            Button("OK") { sharePlay.message = nil }
            if sharePlay.isActive {
                Button("Open Settings") { sharePlay.message = nil; openSettings() }
                Button("Leave SharePlay", role: .destructive) { sharePlay.message = nil; sharePlay.leave() }
            }
        } message: { Text(sharePlay.message ?? "") }
        .task(id: pendingProbe?.id) {
            guard probeSurfaceIsActive(isPlayer: false) else { return }
            await probePendingChannel()
        }
        .alert("Channel Unavailable", isPresented: probeFailureBinding(isPlayer: false)) {
            probeFailureActions
        } message: {
            Text(probeFailureMessage ?? "")
        }
        // The full-screen player owns the failure alert (Retry/Close). A second
        // alert here, bound to the same coordinator phase, collided with the
        // fullScreenCover and dismissed the player silently (2026-09-03).
    }

    private var reloadIdentity: String {
        ApplePlaybackIdentity.digest(for: sourceStore.sources
            .filter { $0.kind == .liveTV }
            .map { "\($0.id.uuidString)|\($0.configurationRevision)|\($0.isEnabled)" }
            .joined(separator: "\u{1f}"))
    }

    private var projectionIdentity: String {
        ApplePlaybackIdentity.digest(for: [
            String(channelsRevision),
            selectedCategory,
            query,
            settings.liveChannelScope.rawValue,
            settings.regionalZIPCode,
            String(settings.showPayPerViewChannels),
            String(settings.show24x7Channels),
            settings.liveChannelPackage.rawValue,
            settings.customChannelPackage.identity,
            settings.favoriteChannelIDs.sorted().joined(separator: "\u{1f}"),
        ].joined(separator: "\u{1e}"))
    }

    private func reload() async {
        guard reloadGate.begin() else { return }
        defer { reloadGate.end() }
        premierGuide = (try? AppleChannelLineupPresets.premierUS()) ?? []
        lineupIndex = AppleChannelLineupIndex(premierGuide)
        let sources = sourceStore.sources.filter { $0.kind == .liveTV && $0.isEnabled }
        await AppleIPTVChannelCache.shared.retain(Set(sources.map(\.id)))
        guard !sources.isEmpty else {
            channels = []
            channelGroups = []
            channelsRevision &+= 1
            errorMessage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }

        // Show the saved lineup first. Re-fetching all 9376 of the owner's
        // channels took 2137 ms before the guide could draw anything
        // (2026-09-15); a lineup changes rarely, so the saved copy goes up at
        // once and the network answer replaces it underneath.
        if channels.isEmpty {
            var cached: [AppleIPTVChannel] = []
            for source in sources {
                if let snapshot = await AppleIPTVChannelCache.shared.snapshot(for: source.id) {
                    cached.append(contentsOf: snapshot.channels)
                }
            }
            if !cached.isEmpty, !Task.isCancelled {
                channels = cached
                channelsRevision &+= 1
                #if DEBUG
                AppleLaunchClock.mark("live.cached(\(cached.count))")
                #endif
            }
        }

        var loaded: [AppleIPTVChannel] = []
        var errors: [String] = []
        for source in sources {
            do {
                let sourceChannels = try await client.channels(
                    source: source,
                    credentials: try sourceStore.iptvCredentials(for: source)
                )
                loaded.append(contentsOf: sourceChannels)
                await AppleIPTVChannelCache.shared.store(sourceChannels, for: source.id)
                sourceStore.recordValidationSuccess(
                    id: source.id,
                    summary: "Connected · \(sourceChannels.count) channels",
                    discoveredItemCount: sourceChannels.count,
                    capabilities: ["Live channels", "Playback"]
                )
                try? await mediaIndex.replace(
                    instanceID: source.id,
                    with: AppleMediaIngestion.channelRecords(source: source, channels: sourceChannels)
                )
            } catch is CancellationError {
                return
            } catch {
                sourceStore.recordValidationFailure(id: source.id, summary: error.localizedDescription)
                errors.append("\(source.name): \(error.localizedDescription)")
            }
        }
        channels = loaded
        channelsRevision &+= 1
        #if DEBUG
        AppleLaunchClock.mark("live.channels(\(loaded.count))")
        #endif
        errorMessage = errors.first
        if selectedChannel == nil, !sharePlay.isActive, let channel = lastWatchedChannel ?? channels.first {
            // On Apple TV this only fills the Now Playing strip; playback
            // starts from the guide, never on its own.
            startChannel(channel, shareSelection: false, present: false)
            #if os(tvOS) && DEBUG
            // Headless capture hook: `defaults write com.orgista.openstream
            // OpenStreamLiveAutoPlay -bool YES` opens the full-screen player
            // on the strip's channel as soon as the guide has loaded.
            if UserDefaults.standard.bool(forKey: "OpenStreamLiveAutoPlay") {
                // `OpenStreamLiveAutoPlayChannel` names the channel to open, so
                // a known-dead one can be opened on purpose; otherwise the
                // strip's channel.
                let wanted = UserDefaults.standard.string(forKey: "OpenStreamLiveAutoPlayChannel")
                let channel = wanted.flatMap { name in
                    channels.first { $0.name.localizedCaseInsensitiveContains(name) }
                } ?? channel
                print("[OpenStream] debug auto-play \(channel.name)")
                startChannel(channel, shareSelection: false)
                // `OpenStreamLiveAutoSwitchCount` then flips to the following
                // channels on a timer. The Siri Remote cannot be driven
                // headlessly, and channel switching is where the player
                // misbehaves, so this is the only way to capture that path.
                let hops = UserDefaults.standard.integer(forKey: "OpenStreamLiveAutoSwitchCount")
                if hops > 0 { scheduleDebugChannelHops(count: hops, from: channel) }
            }
            #endif
        }
    }

    #if os(tvOS) && DEBUG
    /// Simulator only: walk to the next channels every few seconds so the
    /// switch path can be captured. Never reachable without the default set.
    private func scheduleDebugChannelHops(count: Int, from channel: AppleIPTVChannel) {
        let list = channels
        guard let start = list.firstIndex(where: { $0.id == channel.id }), list.count > 1 else { return }
        let gap = UserDefaults.standard.object(forKey: "OpenStreamLiveAutoSwitchSeconds") as? Double ?? 8
        Task { @MainActor in
            for hop in 1 ... count {
                try? await Task.sleep(for: .seconds(max(0.2, gap)))
                let next = list[(start + hop) % list.count]
                print("[OpenStream] debug channel hop \(hop) -> \(next.name)")
                startChannel(next, shareSelection: false)
            }
        }
    }
    #endif

    /// The slice of the channel strip worth fetching EPG for: the channel being
    /// watched and its neighbours either side. Bounded, because the lineup can
    /// be thousands long and the strip only ever shows a handful at a time.
    private func stripGuideChannelIDs(around channel: AppleIPTVChannel, radius: Int = 20) -> [String] {
        let all = channelSnapshot.channels
        guard let index = all.firstIndex(where: { $0.id == channel.id }) else {
            return all.prefix(2 * radius).map(\.id)
        }
        let lower = max(all.startIndex, index - radius)
        let upper = min(all.endIndex, index + radius)
        return all[lower ..< upper].map(\.id)
    }

    private func refreshGuide(_ visibleIDs: Set<String>) async {
        guard !visibleIDs.isEmpty else { return }
        let sources = sourceStore.sources.filter { $0.kind == .liveTV && $0.isEnabled }
        guideStore.retainSources(Set(sources.map(\.id)))
        for source in sources {
            if source.iptvType == .xtream {
                guard let credentials = try? sourceStore.iptvCredentials(for: source) else { continue }
                guideStore.configure(xtreamBase: source.url, username: credentials.username, password: credentials.password, sourceID: source.id)
            } else {
                let sourceChannels = channels.filter { $0.sourceID == source.id }
                let mapping = sourceChannels.reduce(into: [String: String]()) { result, channel in
                    if let id = channel.guideID { result[channel.id] = id }
                }
                guideStore.configure(xmltvURL: sourceChannels.first?.guideURL, sourceID: source.id, channelMapping: mapping)
            }
        }
        await guideStore.refreshVisible(channelIDs: visibleIDs)
    }

    private func rebuildChannelGroups() async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
        }
        let updated = await AppleChannelProjection.buildGroupsOffMain(
            from: channels,
            scope: settings.liveChannelScope,
            showPayPerView: settings.showPayPerViewChannels,
            favoriteIDs: settings.favoriteChannelIDs,
            query: clean,
            regionalZIPCode: settings.regionalZIPCode,
            show24x7: settings.liveChannelPackage == .custom || settings.show24x7Channels
        )
        guard !Task.isCancelled else { return }
        #if DEBUG
        AppleLaunchClock.mark("live.groups(\(updated.count))")
        #endif
        let package = settings.liveChannelPackage
        let custom = settings.customChannelPackage
        let entries = premierGuide
        let favorites = settings.favoriteChannelIDs
        let category = selectedCategory
        let snapshot = await Task.detached(priority: .userInitiated) {
            AppleLiveChannelSnapshot.build(groups: updated, package: package, custom: custom,
                entries: entries, favoriteIDs: favorites, category: category)
        }.value
        guard !Task.isCancelled else { return }
        #if DEBUG
        print("[OpenStream] live lineup source=\(channels.count) package=\(package.rawValue) guide=\(snapshot.channels.count) categories=\(snapshot.categories.count)")
        AppleLaunchClock.mark("live.snapshot(\(snapshot.channels.count))")
        #endif
        channelGroups = updated
        channelSnapshot = snapshot
        let availableIDs = Set(snapshot.channelIDs)
        if focusedChannelID == nil || !availableIDs.contains(focusedChannelID ?? "") {
            focusedChannelID = updated.first?.channels.first?.id
        }
    }

    private func play(_ channel: AppleIPTVChannel) {
        startChannel(channel, shareSelection: true)
    }

    @State private var liveProbedKinds: [String: AppleIPTVStreamProbeResult.MediaKind] = [:]
    private let liveStreamProbe = AppleIPTVStreamProbe()
    private struct ChannelProbeRequest {
        let id = UUID()
        let channel: AppleIPTVChannel
        let shareSelection: Bool
        let present: Bool
    }
    @State private var pendingProbe: ChannelProbeRequest?
    @State private var failedProbe: ChannelProbeRequest?
    @State private var probeFailureMessage: String?

    private func probePendingChannel() async {
        guard let request = pendingProbe else { return }
        do {
            let result = try await liveStreamProbe.validate(channel: request.channel)
            let kind = result.mediaKind
            appleTrace("live preflight: HTTP \(result.statusCode), \(kind.rawValue)")
            try Task.checkCancellation()
            guard pendingProbe?.id == request.id else { return }
            liveProbedKinds[request.channel.id] = kind
            pendingProbe = nil
            startChannelNow(request.channel.withProbedMediaKind(kind),
                shareSelection: request.shareSelection, present: request.present)
        } catch {
            guard !Task.isCancelled, pendingProbe?.id == request.id else { return }
            pendingProbe = nil
            failedProbe = request
            appleTrace("live preflight failed: \(String(describing: type(of: error)))")
            probeFailureMessage = error.localizedDescription
        }
    }

    private func probeSurfaceIsActive(isPlayer: Bool) -> Bool {
        #if os(tvOS)
        (tvPlayer != nil) == isPlayer
        #else
        !isPlayer
        #endif
    }

    private func probeFailureBinding(isPlayer: Bool) -> Binding<Bool> {
        Binding(
            get: { probeSurfaceIsActive(isPlayer: isPlayer) && probeFailureMessage != nil },
            set: { presented in
                guard !presented, probeSurfaceIsActive(isPlayer: isPlayer) else { return }
                probeFailureMessage = nil
            }
        )
    }

    @ViewBuilder
    private var probeFailureActions: some View {
        Button("Retry") {
            guard let request = failedProbe else { return }
            startChannel(request.channel, shareSelection: request.shareSelection, present: request.present)
        }
        Button("Close", role: .cancel) { failedProbe = nil }
    }


    /// Every way a channel starts funnels through here. An extension-less URL
    /// gets one 32 KB look first so HLS goes to AVPlayer and raw TS to the
    /// engine (`AppleLiveStreamRoutePolicy`); the verdict is kept for the
    /// session. Anything with a telling extension starts at once.
    private func startChannel(_ channel: AppleIPTVChannel, shareSelection: Bool, present: Bool = true) {
        pendingProbe = nil
        probeFailureMessage = nil
        failedProbe = nil
        guard channel.probedMediaKind == nil, AppleLiveStreamRoutePolicy.needsProbe(channel.streamURL) else {
            startChannelNow(channel, shareSelection: shareSelection, present: present)
            return
        }
        if let known = liveProbedKinds[channel.id] {
            startChannelNow(channel.withProbedMediaKind(known), shareSelection: shareSelection, present: present)
            return
        }
        // Retire the previous attempt before showing a new channel's failure.
        // Otherwise its player alert can cover the preflight's Retry/Close alert.
        playbackCoordinator.stop()
        pendingProbe = ChannelProbeRequest(channel: channel, shareSelection: shareSelection, present: present)
    }

    private func startChannelNow(_ channel: AppleIPTVChannel, shareSelection: Bool, present: Bool = true) {
        if shareSelection { sharePlay.selected(channel) }
        // Alongside playback, never in front of it: one bounded read of this
        // channel's first segment, looking for CEA-608 captions the provider
        // never declared in its manifest. The answer only reaches the trace for
        // now — see `AppleLiveCaptionProbe` for why nothing acts on it yet.
        let probed = channel
        Task.detached(priority: .utility) {
            await AppleLiveCaptionProbe.shared.probe(
                channelID: probed.id,
                playlistURL: probed.streamURL,
                headers: AppleLiveCaptionProbe.headers(for: probed)
            )
        }
        #if os(tvOS)
        if present { ensureTVEngine(for: channel.playbackRequest()) }
        #endif
        playbackCoordinator.sharePlayChannel = try? AppleSharePlayChannel(channel: channel)
        playbackRevision &+= 1
        if present { fullScreenRevision &+= 1 }
        selectedChannel = channel
        lastWatchedChannelID = channel.id
        #if os(tvOS)
        if present, tvPlayer == nil {
            // A fresh player starts with the footer hidden: Menu shows it.
            #if DEBUG
            tvFooter = AppleTVLiveFooterState(
                phase: UserDefaults.standard.bool(forKey: "OpenStreamLiveFooterVisible") ? .shown : .hidden
            )
            #else
            tvFooter = AppleTVLiveFooterState()
            #endif
            tvPlayer = AppleTVLivePlayerPresentation()
        }
        #endif
    }

    #if os(tvOS)
    /// Guide as the tab root; playback is a full-screen cover with the stock
    /// player. The cover's identity is fixed so switching channels from the
    /// footer updates the player in place, and closing it hands focus back to
    /// the rail cell of the channel that was playing. SwiftUI clears
    /// `tvPlayer` itself when the cover is dismissed.
    private var tvGuide: some View {
        AppleTVLiveGuideScreen(
            channels: channelSnapshot.channels,
            categories: channelSnapshot.categories,
            hiddenCount: channelSnapshot.hiddenCount,
            selectedCategory: $selectedCategory,
            guide: guideStore.guide(for: channelSnapshot.channelIDs),
            guideRevision: guideStore.revision,
            entries: premierGuide,
            favoriteIDs: settings.favoriteChannelIDs,
            nowPlaying: selectedChannel ?? lastWatchedChannel ?? channels.first,
            hasActiveSearch: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            previewsEnabled: settings.autoPlayTrailer,
            isPlayerOpen: tvPlayer != nil,
            focusRestoreToken: tvFocusRestore,
            focusRestoreChannelID: lastWatchedChannelID,
            searchDestination: { AppleTVChannelSearchEditor(query: $query) },
            onSelect: play,
            onToggleFavorite: toggleFavorite,
            onVisibleChannels: refreshGuide
        )
        // The tab root draws no page title on a television; the tab bar names it.
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $tvPlayer, onDismiss: { tvFocusRestore &+= 1 }) { _ in
            if let channel = selectedChannel {
                AppleTVLivePlayerScreen(
                    channel: channel,
                    coordinator: playbackCoordinator,
                    footerChannels: channelSnapshot.channels,
                    footer: $tvFooter,
                    alternateLineup: channels,
                    guide: guideStore.guide(for: channelSnapshot.channelIDs),
                    onSwitch: { startChannel($0, shareSelection: true) }
                )
                .id(ObjectIdentifier(playbackCoordinator))
                // A full-screen cover can suspend the underlying view's task.
                // Footer channel switches and their errors belong to this
                // visible surface; the root is gated off while it is presented.
                .task(id: pendingProbe?.id) {
                    guard probeSurfaceIsActive(isPlayer: true) else { return }
                    await probePendingChannel()
                }
                .alert("Channel Unavailable", isPresented: probeFailureBinding(isPlayer: true)) {
                    probeFailureActions
                } message: {
                    Text(probeFailureMessage ?? "")
                }
                // The guide only fetches EPG for rows visible in the grid, so
                // a viewer who opened a channel without scrolling the guide had
                // no programme data for the strip's channels and the "what is
                // playing" line stayed blank. Ask for the ones the strip can
                // actually reach, around the channel being watched.
                .task(id: channel.id) {
                    await refreshGuide(Set(stripGuideChannelIDs(around: channel)))
                }
            }
        }
    }

    /// Task 9: the stock AVPlayer route whenever the container allows it. The
    /// engine is rebuilt only when the policy's answer differs from the one
    /// the coordinator already holds.
    private func ensureTVEngine(for request: ApplePlaybackRequest) {
        let kind = AppleTVPlaybackPresentationPolicy.engineKind(for: request, preferred: settings.playbackEngine)
        guard playbackCoordinator.engine.kind != kind else { return }
        playbackCoordinator.stop()
        let (engine, fellBack) = ApplePlaybackEngineFactory.make(preferred: kind)
        if kind == .openStream { settings.engineFellBackToNative = fellBack }
        engine.applyCaptionPreferences(
            preference: settings.captionsPreference,
            languages: settings.subtitleLanguages,
            languagesAreExplicit: settings.hasChosenSubtitleLanguages)
        playbackCoordinator = ApplePlaybackCoordinator(engine: engine)
    }
    #endif

    private func resolveSharedChannel() {
        guard let shared = sharePlay.channel, !channels.isEmpty else { return }
        let choices = shared.candidates(in: channels)
        if let selectedChannel, choices.contains(where: { $0.id == selectedChannel.id }) {
            playbackCoordinator.sharePlayChannel = shared
            sharePlay.refreshPlayback(playbackCoordinator, channel: shared)
        } else if choices.count == 1, let channel = choices.first {
            startChannel(channel, shareSelection: false)
        } else if choices.isEmpty {
            sharePlay.message = "Your TV sources do not have \(shared.title)."
        } else {
            sharedChannelChoices = choices
            showsSharedChannelChoices = true
        }
    }

    @ViewBuilder
    private var lastWatchedCard: some View {
        #if os(iOS)
        AppleLiveConnectingArtwork(logoURL: lastWatchedChannel?.logoURL ?? channels.first?.logoURL)
            .livePinnedPlayerLayout(isPlaceholder: true, viewportSize: viewportSize, verticalSizeClass: verticalSizeClass)
        #else
        AppleLiveConnectingArtwork(logoURL: lastWatchedChannel?.logoURL ?? channels.first?.logoURL)
            .livePinnedPlayerLayout(isPlaceholder: true)
        #endif
    }

    private var lastWatchedChannel: AppleIPTVChannel? {
        guard !lastWatchedChannelID.isEmpty else { return nil }
        return channels.first { $0.id == lastWatchedChannelID }
    }

    private func toggleFavorite(_ id: String) {
        settings.favoriteChannelIDs = AppleTVGuideRailCellModel.togglingFavorite(id, in: settings.favoriteChannelIDs)
    }

}

private struct AppleLiveConnectingArtwork: View {
    let logoURL: URL?
    var body: some View {
        ZStack {
            Color.black
            AsyncImage(url: logoURL) { image in
                image.resizable().scaledToFit()
            } placeholder: { Color.clear }
            .frame(width: 132, height: 76)
        }
        .accessibilityLabel("Connecting to live channel")
    }
}

private struct LivePinnedPlayerLayout: ViewModifier {
    let isPlaceholder: Bool
    #if os(iOS)
    let viewportSize: CGSize?
    let verticalSizeClass: UserInterfaceSizeClass?
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad && verticalSizeClass == .compact, let viewportSize = viewportSize {
            content
                .aspectRatio(16 / 9, contentMode: .fit)
                
                .frame(width: viewportSize.width, height: viewportSize.height)
                .background(Color.black)
                .ignoresSafeArea(.container, edges: .all)
        } else {
            let base = content
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(.container, edges: .horizontal)
                
            if isPlaceholder && isPad {
                base.containerRelativeFrame(.vertical, count: 100, span: 40, spacing: 0, alignment: .center)
            } else {
                base
            }
        }
        #else
        content
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
        #endif
    }
}

private extension View {
    #if os(iOS)
    func livePinnedPlayerLayout(isPlaceholder: Bool = false, viewportSize: CGSize? = nil, verticalSizeClass: UserInterfaceSizeClass? = nil) -> some View { 
        modifier(LivePinnedPlayerLayout(isPlaceholder: isPlaceholder, viewportSize: viewportSize, verticalSizeClass: verticalSizeClass)) 
    }
    #else
    func livePinnedPlayerLayout(isPlaceholder: Bool = false) -> some View { modifier(LivePinnedPlayerLayout(isPlaceholder: isPlaceholder)) }
    #endif
}

/// Inline Live-tab playback surface. The coordinator and AVKit host stay owned
/// by the tab so channel changes reload the same engine without presenting a
/// second player. AVKit owns transport controls and its full-screen affordance.
@MainActor
struct AppleLiveInlinePlayer: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var host: ApplePlayerHost
    @State private var audioSession: AppleAudioSessionCoordinator
    @State private var suspendedRequestID: String?
    @State private var suspendedPosition: Double?
    @State private var suspendedWasPlaying: Bool?
    @State private var isFullScreen = false
    @State private var lifetime = AppleLivePlaybackLifetime()

    let request: ApplePlaybackRequest
    let coordinator: ApplePlaybackCoordinator
    let playbackRevision: Int
    let fullScreenRevision: Int
    let logoURL: URL?
    let sharedChannel: AppleSharePlayChannel?
    let sharePlay: AppleSharePlaySessionStore
    let liveChannel: AppleIPTVChannel?
    let channels: [AppleIPTVChannel]
    let guide: AppleIPTVGuide
    let onSwitchChannel: ((AppleIPTVChannel) -> Void)?

    init(request: ApplePlaybackRequest, coordinator: ApplePlaybackCoordinator, playbackRevision: Int, fullScreenRevision: Int = 0, logoURL: URL?, sharedChannel: AppleSharePlayChannel?, sharePlay: AppleSharePlaySessionStore = .shared, liveChannel: AppleIPTVChannel? = nil, channels: [AppleIPTVChannel] = [], guide: AppleIPTVGuide = AppleIPTVGuide(programmes: []), onSwitchChannel: ((AppleIPTVChannel) -> Void)? = nil) {
        self.request = request
        self.coordinator = coordinator
        self.playbackRevision = playbackRevision
        self.fullScreenRevision = fullScreenRevision
        self.logoURL = logoURL
        self.sharedChannel = sharedChannel
        self.sharePlay = sharePlay
        self.liveChannel = liveChannel
        self.channels = channels
        self.guide = guide
        self.onSwitchChannel = onSwitchChannel
        let audioSession = AppleAudioSessionCoordinator()
        _audioSession = State(initialValue: audioSession)
        _host = State(initialValue: ApplePlayerHost(
            coordinator: coordinator,
            audioSession: audioSession
        ))
    }

    var body: some View {
        ZStack {
            #if os(macOS)
            if coordinator.route == .surface {
                if !isFullScreen { ApplePlaybackSurfaceView(engine: coordinator.engine) }
                AppleTransportOverlay(coordinator: coordinator, request: request,
                    onRequestFullScreen: {
                        lifetime.isFullScreen = true
                        isFullScreen = true
                    }, sharePlayMenu: sharePlayMenu)
            } else {
                AppleLiveMacPlayerRepresentable(playerView: host.playerView)
            }
            #else
            // Keep the container mounted across native/surface route changes.
            // Its over-full-screen presentation keeps the guide's load/probe tasks alive.
            AppleLivePlayerControllerRepresentable(
                viewController: host.viewController,
                coordinator: coordinator,
                request: request,
                fullScreenRevision: fullScreenRevision,
                liveMenu: sharePlayMenu,
                channels: channels,
                guide: guide,
                currentChannelID: liveChannel?.id,
                onSwitchChannel: onSwitchChannel,
                onFullScreenChanged: {
                    lifetime.isFullScreen = $0
                    isFullScreen = $0
                }
            )
            #endif
            if coordinator.phase.isBusy {
                AppleLiveConnectingArtwork(logoURL: logoURL)
                    .allowsHitTesting(false)
            }
        }
        .background(.black)
        .onChange(of: isFullScreen) { _, isFullScreen in
            #if !os(macOS)
            host.viewController.requiresLinearPlayback = !isFullScreen
            host.viewController.allowsPictureInPicturePlayback = isFullScreen
            #endif
        }
        .task(id: "\(requestIdentity):\(playbackRevision):\(scenePhase == .background)") {
            coordinator.sharePlayChannel = sharedChannel
            if scenePhase == .background, !request.isLive {
                let position = coordinator.engine.position
                if position.isFinite, position >= 0 {
                    suspendedRequestID = requestIdentity
                    suspendedPosition = position
                    suspendedWasPlaying = coordinator.engine.phase != .paused
                }
            }
            guard scenePhase != .background else {
                lifetime.stop(host: host, coordinator: coordinator)
                return
            }
            // SwiftUI can restart this task when a full-screen cover returns.
            // Only a new channel/retry or a real stop needs a new player item.
            guard lifetime.beginLoad(identity: "\(requestIdentity):\(playbackRevision)") else { return }
            coordinator.stop()
            host.activate()
            host.configureLivePlaybackControls()
            #if !os(macOS)
            host.viewController.requiresLinearPlayback = !lifetime.isFullScreen
            host.viewController.allowsPictureInPicturePlayback = lifetime.isFullScreen
            #endif
            try? await audioSession.prepareForPlayback()
            guard !Task.isCancelled else { return }
            var playbackRequest = request
            let keepPaused = !request.isLive && suspendedRequestID == requestIdentity && suspendedWasPlaying == false
            if !request.isLive, suspendedRequestID == requestIdentity {
                playbackRequest.resumePosition = suspendedPosition
            }
            if keepPaused { playbackRequest.autoplay = false }
            suspendedRequestID = nil
            suspendedPosition = nil
            suspendedWasPlaying = nil
            await coordinator.begin(playbackRequest)
        }
        .onDisappear {
            lifetime.inlineDisappeared(host: host, coordinator: coordinator)
        }
        .alert("Playback Failed", isPresented: failureBinding) {
            Button("Retry") { Task { await coordinator.retry() } }
            Button("Close", role: .cancel) { coordinator.stop() }
        } message: {
            if case .failed(let failure) = coordinator.phase {
                Text(request.isLive ? failure.liveChannelMessage : failure.message)
            }
        }
    }

    private var requestIdentity: String {
        "\(request.mediaID)|\(request.url.absoluteString)"
    }

    private var failureBinding: Binding<Bool> {
        Binding(
            get: {
                if case .failed(let failure) = coordinator.phase { return failure.kind != .cancelled }
                return false
            },
            set: { if !$0 { coordinator.reset() } }
        )
    }

    #if os(macOS)
    private var sharePlayMenu: AppleTransportOverlay.SharePlayMenu? { nil }
    #else
    private var sharePlayMenu: AppleTransportOverlay.SharePlayMenu? {
        guard let liveChannel else { return nil }
        if sharePlay.isActive {
            return .init(
                primaryTitle: "Leave SharePlay",
                primaryAction: { sharePlay.leave() },
                secondaryTitle: "End SharePlay for Everyone",
                secondaryAction: { sharePlay.endForEveryone() }
            )
        }
        return .init(primaryTitle: "Start SharePlay", primaryAction: { Task { await sharePlay.start(channel: liveChannel) } })
    }
    #endif
}

#if os(macOS)
private struct AppleLiveMacPlayerRepresentable: NSViewRepresentable {
    let playerView: AVPlayerView

    func makeNSView(context: Context) -> AVPlayerView { playerView }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
#else
private struct AppleLivePlayerControllerRepresentable: UIViewControllerRepresentable {
    let viewController: AVPlayerViewController
    let coordinator: ApplePlaybackCoordinator
    let request: ApplePlaybackRequest
    let fullScreenRevision: Int
    let liveMenu: AppleTransportOverlay.SharePlayMenu?
    let channels: [AppleIPTVChannel]
    let guide: AppleIPTVGuide
    let currentChannelID: String?
    let onSwitchChannel: ((AppleIPTVChannel) -> Void)?
    let onFullScreenChanged: (Bool) -> Void

    func makeUIViewController(context: Context) -> AppleLivePlayerContainerViewController {
        AppleLivePlayerContainerViewController(playerViewController: viewController,
            coordinator: coordinator, request: request, liveMenu: liveMenu,
            channels: channels, guide: guide, currentChannelID: currentChannelID,
            onSwitchChannel: onSwitchChannel,
            onFullScreenChanged: onFullScreenChanged)
    }

    func updateUIViewController(_ vc: AppleLivePlayerContainerViewController, context: Context) {
        vc.update(request: request, liveMenu: liveMenu, channels: channels,
                  guide: guide, currentChannelID: currentChannelID,
                  onSwitchChannel: onSwitchChannel, fullScreenRevision: fullScreenRevision)
        vc.attachPlayerIfNeeded()
    }
}
#endif

#if !os(macOS)
/// AVKit still renders native video and legible tracks underneath this view.
/// The same chrome and picker stay mounted when a channel changes its route.
private struct AppleLiveFullScreenControls: View {
    let coordinator: ApplePlaybackCoordinator
    let request: ApplePlaybackRequest
    let sharePlayMenu: AppleTransportOverlay.SharePlayMenu?
    let channels: [AppleIPTVChannel]
    /// What is on each channel now. The Live tab has already loaded it; the
    /// picker only reads it.
    let guide: AppleIPTVGuide
    let currentChannelID: String?
    let onSwitchChannel: ((AppleIPTVChannel) -> Void)?
    let onClose: () -> Void
    let channelPicker: AppleLiveChannelPickerState
    @State private var hideChromeSignal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The iPad browses channels in a strip along the bottom of the video;
    /// every other platform keeps the leading-edge panel.
    @ViewBuilder
    private var picker: some View {
        let onSelect: (AppleIPTVChannel) -> Void = { channel in
            channelPicker.select(channel) { switched in onSwitchChannel?(switched) }
        }
        let onDismiss: () -> Void = {
            channelPicker.dismiss()
            hideChromeSignal.toggle()
        }
        // While the picker is up the transport is out of the hit-test tree, so
        // its Close button cannot be reached: without this there is no way back
        // to the Live tab's guide except closing the picker first and waiting
        // for the chrome to come back (owner, 2026-09-20). Playback survives —
        // this is the same dismissal the Close button performs.
        // tvOS is left alone: its picker is a focus destination and a new
        // focusable control in the header would change where the remote lands.
        #if os(tvOS)
        let onBack: (() -> Void)? = nil
        #else
        let onBack: (() -> Void)? = {
            channelPicker.dismiss()
            onClose()
        }
        #endif
        switch AppleLiveChannelPickerPresentation.current {
        case .bottomStrip:
            AppleLiveChannelStripOverlay(
                channels: channels, guide: guide, currentChannelID: currentChannelID,
                onSelect: onSelect, onDismiss: onDismiss, onBack: onBack)
                .ignoresSafeArea(edges: .horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom))
        case .panel:
            AppleLiveChannelPickerOverlay(
                channels: channels, guide: guide, currentChannelID: currentChannelID,
                onSelect: onSelect, onDismiss: onDismiss, onBack: onBack)
                .frame(maxWidth: 340)
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .leading))
        }
    }

    /// tvOS keeps its focus catcher: the picker there is a focus destination,
    /// not a touch target, and removing the surface would strand the engine.
    private var transportIsObscured: Bool {
        #if os(tvOS)
        false
        #else
        channelPicker.isPresented
        #endif
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if coordinator.route == .surface {
                ApplePlaybackSurfaceView(engine: coordinator.engine)
                    .ignoresSafeArea()
            }
            let transport = AppleTransportOverlay(
                coordinator: coordinator,
                request: request,
                onShowChannels: channels.isEmpty ? nil : { channelPicker.show() },
                isObscured: transportIsObscured,
                onBackgroundTap: { wasHidden in
                    if wasHidden {
                        if !channels.isEmpty { channelPicker.show() }
                    } else if channelPicker.isPresented {
                        channelPicker.dismiss()
                    }
                },
                onControlsVisibilityChanged: { isVisible in
                    if !isVisible && channelPicker.isPresented {
                        channelPicker.dismiss()
                    }
                },
                hideChromeSignal: hideChromeSignal,
                onClose: onClose,
                sharePlayMenu: sharePlayMenu
            )
            // Hidden from accessibility as well as from touch, on every
            // platform. `allowsHitTesting(false)` alone leaves the transport's
            // full-screen "Show playback controls" surface in the tree, and it
            // is then the element found at every point over the channel panel:
            // VoiceOver read the surface instead of the rows, and XCTest
            // reported every visible row unhittable (2026-09-19).
            transport
                .allowsHitTesting(!channelPicker.isPresented)
                .accessibilityHidden(channelPicker.isPresented)
            if channelPicker.isPresented {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture {
                        channelPicker.dismiss()
                        hideChromeSignal.toggle()
                    }
                picker
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : Animation.default, value: channelPicker.isPresented)
    }
}

/// Keeps the single AVPlayerViewController mounted while a live player moves
/// between the guide and a full-screen modal. Re-parenting this controller,
/// instead of rebuilding it on a size-class change, preserves the current item
/// and lets AVKit resize its layer during rotation.
private final class AppleLivePlayerContainerViewController: AppleLiveChromeViewController {
    private let playerViewController: AVPlayerViewController
    private let coordinator: ApplePlaybackCoordinator
    private var request: ApplePlaybackRequest
    private var fullScreenRevision = 0
    private var presentedRevision = 0
    private var presentationTask: Task<Void, Never>?
    private var liveMenu: AppleTransportOverlay.SharePlayMenu?
    private var playPauseButton: UIButton!
    private var muteButton: UIButton!
    private var fullscreenButton: UIButton!
    private var surfaceHost: UIHostingController<ApplePlaybackSurfaceView>?
    private weak var presentedFullscreen: AppleLiveFullscreenPlayerViewController?
    private var channels: [AppleIPTVChannel]
    private var guide: AppleIPTVGuide
    private var currentChannelID: String?
    private var onSwitchChannel: ((AppleIPTVChannel) -> Void)?
    private let onFullScreenChanged: (Bool) -> Void

    private var playerObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var muteObservation: NSKeyValueObservation?

    init(playerViewController: AVPlayerViewController, coordinator: ApplePlaybackCoordinator, request: ApplePlaybackRequest, liveMenu: AppleTransportOverlay.SharePlayMenu?, channels: [AppleIPTVChannel] = [], guide: AppleIPTVGuide = AppleIPTVGuide(programmes: []), currentChannelID: String? = nil, onSwitchChannel: ((AppleIPTVChannel) -> Void)? = nil, onFullScreenChanged: @escaping (Bool) -> Void) {
        self.playerViewController = playerViewController
        self.onFullScreenChanged = onFullScreenChanged
        self.coordinator = coordinator
        self.request = request
        self.liveMenu = liveMenu
        self.channels = channels
        self.guide = guide
        self.currentChannelID = currentChannelID
        self.onSwitchChannel = onSwitchChannel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        playPauseButton = UIButton(type: .system)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34)), for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.accessibilityLabel = "Play"
        playPauseButton.accessibilityIdentifier = "player.play-pause"
        playPauseButton.addTarget(self, action: #selector(togglePlayPause), for: .primaryActionTriggered)
        
        muteButton = menuButton(imageName: "speaker.wave.3.fill", accessibilityLabel: "Mute", menu: nil)
        muteButton.accessibilityIdentifier = "player.mute"
        muteButton.addTarget(self, action: #selector(toggleMute), for: .primaryActionTriggered)
        
        fullscreenButton = menuButton(imageName: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Full Screen", menu: nil)
        fullscreenButton.accessibilityIdentifier = "player.fullscreen"
        fullscreenButton.addTarget(self, action: #selector(requestFullScreen), for: .primaryActionTriggered)
        
        view.addSubview(playPauseButton)
        view.addSubview(muteButton)
        view.addSubview(fullscreenButton)
        
        NSLayoutConstraint.activate([
            playPauseButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            playPauseButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            playPauseButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            
            muteButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            muteButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            
            fullscreenButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            fullscreenButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
        ])
        
        chromeButtons = [playPauseButton, muteButton, fullscreenButton]
        attachPlayerIfNeeded()
        
        // KVO calls back on whichever thread changed the value, with no main-queue
        // guarantee, so every observer below hops to the main actor explicitly.
        playerObservation = playerViewController.observe(\.player, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observePlayer(self.playerViewController.player)
            }
        }
    }
    
    private func observePlayer(_ player: AVPlayer?) {
        // The hops can land out of order, so each one re-reads the player's current
        // state on the main actor instead of carrying the value it was fired with.
        timeControlObservation = player?.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updatePlayPauseButton() }
        }
        muteObservation = player?.observe(\.isMuted, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateMuteButton() }
        }
    }

    private func updatePlayPauseButton() {
        let isPlaying = playerViewController.player?.timeControlStatus == .playing
        let config = UIImage.SymbolConfiguration(pointSize: 34)
        playPauseButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill", withConfiguration: config), for: .normal)
        playPauseButton.accessibilityLabel = isPlaying ? "Pause" : "Play"
    }

    private func updateMuteButton() {
        let isMuted = playerViewController.player?.isMuted ?? false
        muteButton.setImage(UIImage(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill"), for: .normal)
        muteButton.accessibilityLabel = isMuted ? "Unmute" : "Mute"
    }
    
    @objc private func togglePlayPause() {
        if coordinator.phase == .playing {
            coordinator.engine.pause()
        } else {
            coordinator.engine.play()
        }
    }
    
    @objc private func toggleMute() {
        guard let player = playerViewController.player else { return }
        player.isMuted.toggle()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachPlayerIfNeeded()
        updateInlineSurface()
        presentRequestedFullScreen()
    }

    func attachPlayerIfNeeded() {
        guard playerViewController.parent == nil, presentedFullscreen == nil else { return }
        playerViewController.showsPlaybackControls = false
        playerViewController.videoGravity = .resizeAspect
        addChild(playerViewController)
        playerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(playerViewController.view, at: 0)
        NSLayoutConstraint.activate([
            playerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        playerViewController.didMove(toParent: self)
    }

    private func updateInlineSurface() {
        guard coordinator.route == .surface, presentedFullscreen == nil else {
            removeInlineSurface()
            return
        }
        guard surfaceHost == nil, playerViewController.parent === self else { return }
        let hosting = UIHostingController(rootView: ApplePlaybackSurfaceView(engine: coordinator.engine))
        hosting.view.backgroundColor = .clear
        hosting.view.isUserInteractionEnabled = false
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)
        view.insertSubview(hosting.view, aboveSubview: playerViewController.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        surfaceHost = hosting
    }

    private func removeInlineSurface() {
        surfaceHost?.willMove(toParent: nil)
        surfaceHost?.view.removeFromSuperview()
        surfaceHost?.removeFromParent()
        surfaceHost = nil
    }

    func update(request: ApplePlaybackRequest, liveMenu: AppleTransportOverlay.SharePlayMenu?,
                channels: [AppleIPTVChannel], guide: AppleIPTVGuide, currentChannelID: String?,
                onSwitchChannel: ((AppleIPTVChannel) -> Void)?,
                fullScreenRevision: Int) {
        self.request = request
        self.liveMenu = liveMenu
        self.channels = channels
        self.guide = guide
        self.currentChannelID = currentChannelID
        self.onSwitchChannel = onSwitchChannel
        self.fullScreenRevision = fullScreenRevision
        if isViewLoaded { updateInlineSurface() }
        if isViewLoaded {
            let playing = coordinator.phase == .playing
            playPauseButton.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 34)), for: .normal)
            playPauseButton.accessibilityLabel = playing ? "Pause" : "Play"
        }
        presentedFullscreen?.update(request: request, liveMenu: liveMenu,
                                    channels: channels, guide: guide, currentChannelID: currentChannelID,
                                    onSwitchChannel: onSwitchChannel)
        // UIKit presentation calls back into SwiftUI state; leave this update first.
        if fullScreenRevision != presentedRevision, presentationTask == nil {
            presentationTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                self.presentationTask = nil
                self.presentRequestedFullScreen()
            }
        }
    }

    private func presentRequestedFullScreen() {
        guard fullScreenRevision != presentedRevision, viewIfLoaded?.window != nil else { return }
        if presentedFullscreen != nil {
            presentedRevision = fullScreenRevision
        } else {
            requestFullScreen()
        }
    }

    func restorePlayer() {
        presentedFullscreen = nil
        attachPlayerIfNeeded()
        updateInlineSurface()
        onFullScreenChanged(false)
        showControls()
    }

    @objc private func requestFullScreen() {
        guard presentedFullscreen == nil, presentedViewController == nil,
              playerViewController.presentingViewController == nil else { return }
        presentedRevision = fullScreenRevision
        onFullScreenChanged(true)
        removeInlineSurface()
        playerViewController.willMove(toParent: nil)
        playerViewController.view.removeFromSuperview()
        playerViewController.removeFromParent()
        let fullscreen = AppleLiveFullscreenPlayerViewController(
            playerViewController: playerViewController,
            inlineContainer: self,
            coordinator: coordinator,
            request: request,
            liveMenu: liveMenu,
            channels: channels,
            guide: guide,
            currentChannelID: currentChannelID,
            onSwitchChannel: onSwitchChannel
        )
        presentedFullscreen = fullscreen
        // Retain the guide's view hierarchy and its loading task while AVKit
        // owns the single player controller in the modal.
        fullscreen.modalPresentationStyle = .overFullScreen
        present(fullscreen, animated: true)
    }
}

private final class AppleLiveFullscreenPlayerViewController: UIViewController {
    private let playerViewController: AVPlayerViewController
    private let coordinator: ApplePlaybackCoordinator
    private weak var inlineContainer: AppleLivePlayerContainerViewController?
    private let controlsHost: UIHostingController<AppleLiveFullScreenControls>
    private let channelPicker = AppleLiveChannelPickerState()

    init(playerViewController: AVPlayerViewController, inlineContainer: AppleLivePlayerContainerViewController,
         coordinator: ApplePlaybackCoordinator, request: ApplePlaybackRequest,
         liveMenu: AppleTransportOverlay.SharePlayMenu?, channels: [AppleIPTVChannel],
         guide: AppleIPTVGuide, currentChannelID: String?,
         onSwitchChannel: ((AppleIPTVChannel) -> Void)?) {
        self.playerViewController = playerViewController
        self.inlineContainer = inlineContainer
        self.coordinator = coordinator
        controlsHost = UIHostingController(rootView: AppleLiveFullScreenControls(
            coordinator: coordinator, request: request, sharePlayMenu: liveMenu,
            channels: channels, guide: guide, currentChannelID: currentChannelID,
            onSwitchChannel: onSwitchChannel, onClose: {},
            channelPicker: channelPicker))
        super.init(nibName: nil, bundle: nil)
        update(request: request, liveMenu: liveMenu, channels: channels,
               guide: guide, currentChannelID: currentChannelID, onSwitchChannel: onSwitchChannel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(request: ApplePlaybackRequest, liveMenu: AppleTransportOverlay.SharePlayMenu?,
                channels: [AppleIPTVChannel], guide: AppleIPTVGuide, currentChannelID: String?,
                onSwitchChannel: ((AppleIPTVChannel) -> Void)?) {
        controlsHost.rootView = AppleLiveFullScreenControls(
            coordinator: coordinator, request: request, sharePlayMenu: liveMenu,
            channels: channels, guide: guide, currentChannelID: currentChannelID,
            onSwitchChannel: onSwitchChannel,
            onClose: { [weak self] in self?.dismiss(animated: true) },
            channelPicker: channelPicker)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // AVKit owns picture/caption rendering; the shared overlay owns all controls.
        view.accessibilityViewIsModal = true
        playerViewController.showsPlaybackControls = false
        playerViewController.videoGravity = .resizeAspect
        controlsHost.view.backgroundColor = .clear
        for child in [playerViewController, controlsHost] as [UIViewController] {
            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child.view)
            NSLayoutConstraint.activate([
                child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.view.topAnchor.constraint(equalTo: view.topAnchor),
                child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            child.didMove(toParent: self)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if os(iOS)
        AppleOrientationLock.shared.allowsLandscape = true
        #endif
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        #if os(iOS)
        AppleOrientationLock.shared.allowsLandscape = false
        #endif
        playerViewController.willMove(toParent: nil)
        playerViewController.view.removeFromSuperview()
        playerViewController.removeFromParent()
        controlsHost.willMove(toParent: nil)
        controlsHost.view.removeFromSuperview()
        controlsHost.removeFromParent()
        inlineContainer?.restorePlayer()
    }

    #if os(iOS)
    override var prefersStatusBarHidden: Bool { true }
    #endif
}

/// The inline preview has one timer for its play, mute and full-screen buttons.
private class AppleLiveChromeViewController: UIViewController, UIGestureRecognizerDelegate {
    var chromeButtons: [UIButton] = []
    private var hideTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(showControls))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showControls()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        hideTask?.cancel()
    }

    @objc func showControls() {
        hideTask?.cancel()
        chromeButtons.forEach { $0.isHidden = false }
        hideTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.chromeButtons.forEach { $0.isHidden = true }
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touched = touch.view
        while let current = touched {
            if current is UIControl { showControls(); return false }
            touched = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    func menuButton(imageName: String, accessibilityLabel: String, menu: UIMenu?) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: imageName), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = accessibilityLabel
        button.menu = menu
        button.showsMenuAsPrimaryAction = menu != nil
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

}

#endif

private struct AppleLiveSearchModifier<Results: View>: ViewModifier {
    let isEnabled: Bool
    @Binding var query: String
    let selectionRevision: Int
    @Binding var showsSearch: Bool
    @ViewBuilder let results: () -> Results
    #if !os(tvOS)
    @FocusState private var searchFocused: Bool
    #endif

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        if isEnabled {
            content
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsSearch = true
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .accessibilityLabel("Search")
                    }
                    #else
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showsSearch = true
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .accessibilityLabel("Search")
                    }
                    #endif
                }
                .navigationDestination(isPresented: $showsSearch) {
                    results()
                        .searchable(text: $query, prompt: "Channels and groups")
                        .searchFocused($searchFocused)
                        .onChange(of: selectionRevision) { _, _ in
                            searchFocused = false
                            showsSearch = false
                        }
                        .onAppear {
                            // Focus search field automatically when pushing the screen
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(250))
                                searchFocused = true
                            }
                        }
                        .navigationTitle("Search")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                }
        } else {
            content
        }
        #endif
    }
}

#if os(tvOS)
struct AppleTVChannelSearchEditor: View {
    @Binding var query: String

    var body: some View {
        Form {
            Section {
                TextField("Channel or group", text: $query)
            }
            if !query.isEmpty {
                Section {
                    Button("Clear Search", role: .destructive) {
                        query = ""
                    }
                }
            }
        }
        .navigationTitle("Search Channels")
    }
}
#endif

private extension View {
    @ViewBuilder
    func appleTVFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }
}

@MainActor
enum AppleSMBPlaybackRequestFactory {
    static func make(
        source: AppleSource,
        item: AppleLibraryItem,
        playbackURL: URL
    ) -> ApplePlaybackRequest {
        ApplePlaybackRequest(
            url: playbackURL,
            headers: [:],
            isLive: false,
            mediaID: AppleMediaIngestion.libraryRecord(source: source, item: item).id,
            title: AppleLibraryTitleParser.parse(item).title,
            sourceKind: .networkShare,
            hints: ApplePlaybackRequest.Hints(filename: item.name)
        )
    }
}

@MainActor
struct AppleLibraryView: View {
    @State private var library = AppleLocalLibraryStore.shared
    @State private var viewportSize: CGSize = .zero
    @State private var selectedHero: AppleLibrarySeries?
    @State private var selectedHeroAutoPlay = false
    @State private var showsSelectedHero = false
    /// Textless hero art, keyed by media id, once TMDB has been asked for it.
    /// Empty is the normal state on first paint — see `upgradeHeroArtwork`.
    @State private var heroArtwork: [String: AppleHeroArtworkUpgrade.Artwork] = [:]
    @AppStorage("openstream.library.sort") private var sort = AppleLibrarySort.added
    let sourceStore: AppleSourceStore
    let mediaIndex: AppleMediaIndexStore
    let settings: AppleSettingsStore
    let openSettings: () -> Void

    private var groups: [AppleLibrarySeries] { library.sorted(sort) }

    #if os(tvOS)
    private let sectionSpacing: CGFloat = AppleTVBillboardMetrics.sectionSpacing
    private let heroHorizontalPadding: CGFloat = -AppleTVChromeMetrics.horizontalSafeInset
    #else
    private let sectionSpacing: CGFloat = 30
    private let heroHorizontalPadding: CGFloat = 16
    #endif

    /// Nothing at all to draw: no titles, nothing in progress, no hero.
    ///
    /// The empty state is a sibling of the ScrollView rather than a row inside
    /// it, which is the only way it lands in the same place as Discover's.
    /// Inside the stack it was centred on `viewportSize − 32` while Discover's
    /// centred on the whole tab area, so "Open Settings" jumped 94 pt when the
    /// viewer flipped between the two empty tabs — measured y=504 against
    /// y=598 (owner: "when you flip the placement of open settings changes",
    /// 2026-09-16).
    private var hasNothingToShow: Bool {
        groups.isEmpty && library.continueWatching.isEmpty
            && library.featuredCandidates.isEmpty && !library.isLoading
    }

    var body: some View {
        Group {
            if hasNothingToShow {
                AppleSourceEmptyState(title: "No Videos", actionTitle: "Open Settings", action: openSettings)
            } else {
                libraryScroll
            }
        }
        .navigationDestination(isPresented: $showsSelectedHero) {
            if let selectedHero {
                detail(selectedHero, autoPlay: selectedHeroAutoPlay)
            }
        }
        .appleTraceScreen("library", detail: "\(groups.count) titles, loading=\(library.isLoading)")
    }

    /// Extracted from `libraryScroll` because the whole scroll body stopped
    /// type-checking on visionOS — "unable to type-check this expression in
    /// reasonable time", which is what had kept that target from building at all
    /// (2026-09-17). The visionOS branches add enough overloads to tip an
    /// expression the other platforms still managed. Same shape, one level of
    /// nesting moved out.
    @ViewBuilder
    private func rotatingHero(_ heroes: [AppleLibrarySeries]) -> some View {
        TimelineView(.periodic(from: .now, by: AppleHeroRotation.interval)) { context in
            if let index = AppleHeroRotation.index(at: context.date, count: heroes.count) {
                let featured = heroes[index]
                let item = heroItem(featured)
                // The wordmark was never passed. `AppleFeaturedHero.wordmark`
                // defaults to nil, so `AppleTVBillboardTitleTreatment` could
                // only ever answer `.text` here, which is exactly what the
                // owner saw on the Apple TV Library hero (2026-09-20).
                AppleFeaturedHero(
                    item: item,
                    viewportSize: viewportSize,
                    wordmark: item.logoURL,
                    rotationCount: heroes.count,
                    rotationIndex: index
                ) {
                    AppleFeaturedActions(
                        viewportSize: viewportSize,
                        onPlay: { selectHero(featured, autoPlay: true) },
                        onDetails: { selectHero(featured, autoPlay: false) }
                    )
                }
                .padding(.horizontal, heroHorizontalPadding)
            }
        }
        .task(id: heroUpgradeIdentity(heroes)) { await upgradeHeroArtwork(heroes) }
    }

    /// The hero's own record, with any textless art that has since arrived.
    private func heroItem(_ group: AppleLibrarySeries) -> AppleCatalogItem {
        let item = library.catalogItem(for: group)
        guard let upgrade = heroArtwork[item.mediaID] else { return item }
        return item.withHeroArtwork(backgroundURL: upgrade.backdropURL, logoURL: upgrade.logoURL)
    }

    private func heroUpgradeIdentity(_ heroes: [AppleLibrarySeries]) -> String {
        heroes.map { library.catalogItem(for: $0).mediaID }.joined(separator: ",")
    }

    /// Asks TMDB for a backdrop with no title burned into it, for the handful
    /// of titles the billboard rotates through.
    ///
    /// Never on the way to first paint: the hero has already drawn the art the
    /// Library resolver cached for it, and this only swaps that art if a
    /// textless one exists. `AppleHeroArtworkUpgrade` answers from the
    /// metadata disk cache after the first visit, so the swap is a first-run
    /// event, not something the viewer sees every time.
    private func upgradeHeroArtwork(_ heroes: [AppleLibrarySeries]) async {
        guard settings.metadataEnabled,
              let configuration = try? AppleTMDBConfiguration(credential: settings.tmdbAPIKey) else { return }
        for group in heroes {
            let item = library.catalogItem(for: group)
            guard heroArtwork[item.mediaID] == nil,
                  let imdbID = AppleHeroArtworkUpgrade.upgradeableIMDBID(for: item) else { continue }
            let upgrade = await AppleHeroArtworkUpgrade.shared.artwork(
                imdbID: imdbID,
                kind: item.type == "series" ? .series : .movie,
                configuration: configuration
            )
            guard !Task.isCancelled else { return }
            // Nothing to show for it is still an answer worth holding on to:
            // it stops the loop asking again every time the view reappears.
            heroArtwork[item.mediaID] = upgrade
        }
    }

    private func selectHero(_ group: AppleLibrarySeries, autoPlay: Bool) {
        selectedHero = group
        selectedHeroAutoPlay = autoPlay
        showsSelectedHero = true
    }

    /// The per-source, per-kind shelves. Extracted for the same reason as
    /// `rotatingHero`: two nested `ForEach`es carrying four `let` bindings and a
    /// closure were more than the visionOS type-checker would finish.
    private var sourceShelves: some View {
        // Once, not once per shelf: it filters every group per source.
        let accessory = accessoryShelf
        return ForEach(library.sources) { source in
            let local = groups.filter { $0.items.first?.sourceID == source.id }
            ForEach([AppleLibraryTitle.Kind.movie, .show, .other], id: \.rawValue) { kind in
                let titles = local.filter { $0.parsed.kind == kind }
                if !titles.isEmpty {
                    // One library source reads "Movies" / "Shows"; the
                    // source name only disambiguates when there are several (Z9).
                    let kindName = kind == .movie ? "Movies" : kind == .show ? "Shows" : "Other"
                    let name = library.sources.count > 1 ? "\(kindName) · \(source.name)" : kindName
                    let isFirstShelf = accessory.map {
                        $0.sourceIndex == library.sources.firstIndex(where: { $0.id == source.id })
                            && $0.kind == kind
                    } ?? false
                    shelf(name, titles, accessory: isFirstShelf ? sortAccessory : nil)
                }
            }
        }
    }

    private var libraryScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                let heroes = library.featuredCandidates
                if !heroes.isEmpty {
                    rotatingHero(heroes)
                }
                if let error = library.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").padding(.horizontal, 16)
                }
                let resumable = library.continueWatching
                if !resumable.isEmpty { shelf("Continue Watching", resumable, progress: true) }
                sourceShelves
                if !groups.isEmpty { shelf("Recently Added", library.sorted(.added).prefix(24).map { $0 }) }
                if library.isLoading && groups.isEmpty {
                    AppleSourceLoadingState()
                        .appleCentredInViewport(viewportSize)
                }
            }
            #if os(tvOS)
            .padding(.bottom, AppleTVBillboardMetrics.contentBottomInset)
            #else
            .padding(.vertical)
            #endif
        }.scrollIndicators(AppleDesignTokens.scrollIndicatorVisibility)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
        #if os(tvOS)
        // The billboard runs under the top safe area (see Discover). No
        // Refresh on a TV home (X4); Sort sits on the first shelf's header
        // line (`sortAccessory`), so nothing floats over the art.
        .ignoresSafeArea(edges: .top)
        .scrollClipDisabled()
        .background(Color.black.ignoresSafeArea())
        #else
        .toolbar {
            ToolbarItem(placement: libraryActionPlacement) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(AppleLibrarySort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: { Label("Sort library", systemImage: "arrow.up.arrow.down") }
                #if os(visionOS)
                .buttonStyle(.borderless)
                .appleVisionActionTarget()
                #endif
            }
            ToolbarItem(placement: libraryActionPlacement) {
                Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .appleVisionActionTarget()
                    .disabled(library.isLoading)
            }
        }
        #endif
        .refreshable { await reload() }
        .task { library.refreshProgress(); if library.groups.isEmpty { await reload() } }
        .onAppear { library.refreshProgress() }
    }
    private var libraryActionPlacement: ToolbarItemPlacement {
        #if os(visionOS)
        .bottomOrnament
        #else
        .primaryAction
        #endif
    }
    private func reload() async { await library.reload(sourceStore: sourceStore, mediaIndex: mediaIndex, settings: settings) }
    private func shelf(_ title: String, _ groups: [AppleLibrarySeries], progress: Bool = false, accessory: AnyView? = nil) -> some View {
        AppleLocalTitleShelf(title: title, groups: groups, sourceStore: sourceStore,
            mediaIndex: mediaIndex, settings: settings, openSettings: openSettings, showsProgress: progress, accessory: accessory)
    }

    /// The first kind a source actually has, so the Sort control lands on the
    /// first shelf drawn for the first source.
    /// The shelf that carries the sort control: the first one actually drawn.
    ///
    /// Not "the first source", which loses the control entirely when that
    /// source draws nothing — an offline NAS is enough to do it.
    private var accessoryShelf: (sourceIndex: Int, kind: AppleLibraryTitle.Kind)? {
        let perSource = library.sources.map { source -> [String] in
            let local = groups.filter { $0.items.first?.sourceID == source.id }
            return [AppleLibraryTitle.Kind.movie, .show, .other]
                .filter { kind in local.contains { $0.parsed.kind == kind } }
                .map(\.rawValue)
        }
        guard let pick = AppleLibraryShelfLayout.accessoryShelf(sourcesWithKinds: perSource),
              let kind = AppleLibraryTitle.Kind(rawValue: pick.kind) else { return nil }
        return (pick.sourceIndex, kind)
    }

    private func firstKind(in local: [AppleLibrarySeries]) -> AppleLibraryTitle.Kind? {
        [AppleLibraryTitle.Kind.movie, .show, .other].first { kind in local.contains { $0.parsed.kind == kind } }
    }

    /// tvOS only: the Sort menu as a bare glyph on the first shelf's header
    /// line. Other platforms keep it in the toolbar.
    private var sortAccessory: AnyView? {
        #if os(tvOS)
        AnyView(
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(AppleLibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: { Image(systemName: "arrow.up.arrow.down") }
            .accessibilityLabel("Sort library")
            .buttonStyle(AppleTVGlyphStyle())
            .font(.system(size: AppleTVChromeMetrics.glyphFontSize, weight: .semibold))
        )
        #else
        nil
        #endif
    }
    private func detail(_ group: AppleLibrarySeries, autoPlay: Bool = false) -> some View {
        AppleLocalTitleDestination(group: group, sourceStore: sourceStore, mediaIndex: mediaIndex,
            settings: settings, openSettings: openSettings, autoPlay: autoPlay)
    }
}
