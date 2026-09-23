import SwiftUI

@MainActor
@Observable
private final class GuideScrollState {
    var horizontalOffset: CGFloat = 0
}

/// A lazy schedule with one shared timeline and a pinned channel rail.
public struct AppleIPTVGuideGridView: View {
    let channels: [AppleIPTVChannel]
    let guide: AppleIPTVGuide
    /// Bumped by `AppleIPTVGuideStore` whenever programmes arrive. Without it
    /// in the projection's identity the grid kept whatever it had projected
    /// before the guide loaded — every row reading "No information" until the
    /// next minute tick happened to rebuild it (measured on the iPad,
    /// 2026-09-20: the channel picker listed real programmes while the grid
    /// behind it still said there were none).
    let guideRevision: Int
    let entries: [AppleChannelLineupEntry]
    let favoriteIDs: Set<String>
    let onSelect: (AppleIPTVChannel) -> Void
    let onToggleFavorite: (String) -> Void
    let onVisibleChannels: (Set<String>) async -> Void
    /// Last health result per channel id, built by the Live tab once per
    /// lineup or history change. Rows only look their own id up.
    let health: [String: AppleChannelHealthResult]
    let onShowHealth: ((AppleIPTVChannel) -> Void)?
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    @State private var rows: [AppleGuideRowModel] = []
    @State private var headerSlots: [AppleGuideGridHeaderSlot] = []
    @State private var scrollState = GuideScrollState()
    @State private var visibleIDs = Set<String>()
    
    @ScaledMetric(relativeTo: .body) private var rowHeight = 76.0

    public init(channels: [AppleIPTVChannel], guide: AppleIPTVGuide, guideRevision: Int = 0,
                entries: [AppleChannelLineupEntry],
                favoriteIDs: Set<String>, onSelect: @escaping (AppleIPTVChannel) -> Void,
                onToggleFavorite: @escaping (String) -> Void,
                onVisibleChannels: @escaping (Set<String>) async -> Void,
                health: [String: AppleChannelHealthResult] = [:],
                onShowHealth: ((AppleIPTVChannel) -> Void)? = nil) {
        self.channels = channels
        self.guide = guide
        self.guideRevision = guideRevision
        self.entries = entries
        self.favoriteIDs = favoriteIDs
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
        self.onVisibleChannels = onVisibleChannels
        self.health = health
        self.onShowHealth = onShowHealth
    }

    private let railWidth: CGFloat = 144
    private let cellWidth: CGFloat = 160

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let window = AppleGuideChannelProjection.window(day: context.date, now: context.date)
            let timelineWidth = CGFloat(window.duration / 1800) * cellWidth
            let tick = floor(context.date.timeIntervalSince1970 / 60)
            
            VStack(spacing: 0) {
                if rows.isEmpty {
                    ContentUnavailableView("No Channels", systemImage: "tv")
                } else if dynamicTypeSize.isAccessibilitySize {
                    accessibleSchedule(window: window)
                } else {
                    GeometryReader { geometry in
                        ScrollView(.horizontal, showsIndicators: false) {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                    Section {
                                        ForEach(rows) { row in
                                            HStack(spacing: 0) {
                                                GuideChannelRail(row: row, isFavorite: favoriteIDs.contains(row.id),
                                                    health: AppleChannelHealthIndicator(result: health[row.id]),
                                                    scrollState: scrollState, railWidth: railWidth,
                                                    onSelect: { onSelect(row.channel) }, onToggleFavorite: { onToggleFavorite(row.id) },
                                                    onShowHealth: health[row.id] == nil ? nil : onShowHealth.map { show in { show(row.channel) } })
                                                    .frame(width: railWidth, height: rowHeight)
                                                    .background(Color.black)
                                                    .zIndex(1)
                                                GuideScheduleRow(row: row, cellWidth: cellWidth, height: rowHeight,
                                                    onSelect: { onSelect(row.channel) })
                                                    .equatable()
                                            }
                                            .onAppear { visibleIDs.insert(row.id) }
                                            .onDisappear { visibleIDs.remove(row.id) }
                                        }
                                    } header: {
                                        HStack(spacing: 0) {
                                            Text("Channels").font(.caption.bold())
                                                .padding(.leading, 8)
                                                .frame(width: railWidth, height: 36, alignment: .leading)
                                                .background(Color.black)
                                                .offset(x: scrollState.horizontalOffset).zIndex(1)
                                            HStack(spacing: 0) {
                                                ForEach(headerSlots) { slot in
                                                    Text(slot.label)
                                                        .font(.caption).foregroundStyle(.secondary)
                                                        .frame(width: cellWidth, height: 36, alignment: .leading)
                                                }
                                            }
                                            .background(Color.black)
                                        }
                                    }
                                }
                                .overlay(alignment: .topLeading) {
                                    if context.date >= window.start && context.date < window.end {
                                        let offset = context.date.timeIntervalSince(window.start) / 1800
                                        Rectangle().fill(AppleDesignTokens.brandAccent).frame(width: 2)
                                            .offset(x: railWidth + CGFloat(offset) * cellWidth)
                                            .padding(.top, 36)
                                            .allowsHitTesting(false).accessibilityHidden(true)
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .frame(width: railWidth + timelineWidth, height: geometry.size.height)
                        }
                        .scrollIndicators(.hidden)
                        .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentOffset.x) } action: { _, offset in
                            scrollState.horizontalOffset = offset
                        }
                    }
                }
            }
            .background(Color.black)
            .task(id: GuideProjectionInput(channels: channels, guideRevision: guideRevision, entries: entries, favoriteIDs: favoriteIDs, window: window, tick: tick)) {
                let input = GuideProjectionInput(channels: channels, guideRevision: guideRevision, entries: entries, favoriteIDs: favoriteIDs, window: window, tick: tick)
                let now = context.date
                
                let result = await Task.detached(priority: .userInitiated) {
                    let projected = AppleGuideChannelProjection.rows(channels: input.channels, entries: input.entries,
                        favoriteIDs: input.favoriteIDs, favoritesOnly: false, sortByNumber: true)
                    let channelIDs = projected.map { $0.id }
                    
                    let gridIndex = AppleGuideGridModel.index(
                        channels: channelIDs,
                        guide: guide,
                        window: input.window,
                        slotWidthMinutes: 30,
                        now: now
                    )
                    
                    let newRows = projected.map { channel in
                        let cells = gridIndex.cells(for: channel.id)
                        let spans = cells.map { cell in
                            AppleGuideProgrammeSpan(
                                id: cell.id,
                                startOffset: cell.columnOffset,
                                width: cell.columnSpan,
                                title: cell.title,
                                subtitle: cell.subtitle,
                                isNow: cell.isLive || (cell.start <= now && cell.end > now)
                            )
                        }
                        return AppleGuideRowModel(id: channel.id, channel: channel.channel, number: channel.number, spans: spans)
                    }
                    return (newRows, gridIndex.headerSlots)
                }.value
                
                guard !Task.isCancelled else { return }
                self.rows = result.0
                self.headerSlots = result.1
            }
        }
        .task(id: visibleIDs) {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await onVisibleChannels(visibleIDs)
        }
    }

    private func accessibleSchedule(window: DateInterval) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            let indicator = AppleChannelHealthIndicator(result: health[row.id])
                            Button { onSelect(row.channel) } label: {
                                HStack(spacing: 8) {
                                    Text((row.number.map { "\($0) · " } ?? "") + row.channel.name)
                                        .font(.headline).multilineTextAlignment(.leading)
                                    if let indicator { AppleChannelHealthDot(indicator: indicator, size: 10) }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play \(row.channel.name)")
                            .accessibilityValue(indicator?.accessibilityLabel ?? "")
                            .contextMenu {
                                if health[row.id] != nil, let onShowHealth {
                                    Button("Channel Health", systemImage: "info.circle") { onShowHealth(row.channel) }
                                }
                            }
                            Button { onToggleFavorite(row.id) } label: {
                                Image(systemName: favoriteIDs.contains(row.id) ? "heart.fill" : "heart")
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(favoriteIDs.contains(row.id) ? "Remove" : "Add") \(row.channel.name) \(favoriteIDs.contains(row.id) ? "from" : "to") favorites")
                        }
                        let programmes = guide.programmes(channelID: row.id, in: window)
                        if programmes.isEmpty { Text("No information").foregroundStyle(.secondary) }
                        ForEach(programmes) { programme in
                            Button { onSelect(row.channel) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(programme.start, format: .dateTime.hour().minute()).font(.caption)
                                    Text(programme.title).font(.body)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).background(AppleDesignTokens.surface)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onAppear { visibleIDs.insert(row.id) }
                    .onDisappear { visibleIDs.remove(row.id) }
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }
}

private struct GuideProjectionInput: Equatable, Sendable {
    let channels: [AppleIPTVChannel]
    let guideRevision: Int
    let entries: [AppleChannelLineupEntry]
    let favoriteIDs: Set<String>
    let window: DateInterval
    let tick: Double
}

private struct GuideChannelRail: View {
    let row: AppleGuideRowModel
    let isFavorite: Bool
    let health: AppleChannelHealthIndicator?
    let scrollState: GuideScrollState
    let railWidth: CGFloat
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    /// Nil when the channel has never been checked: the menu then has no
    /// health item, like the row has no dot.
    let onShowHealth: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let logoURL = row.channel.logoURL {
                            AppleRemoteImage(url: logoURL, contentMode: .fit, placeholderSystemImage: "")
                                .frame(width: 34, height: 24)
                        }
                        if let number = row.number {
                            Text(number, format: AppleChannelNumberFormat.style)
                                .font(.caption.monospacedDigit())
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(row.channel.name).font(.caption.bold()).lineLimit(2)
                        if let health {
                            AppleChannelHealthDot(indicator: health)
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(row.channel.name)")
            .accessibilityValue(health?.accessibilityLabel ?? "")
            .accessibilityIdentifier("guide.play.\(row.id)")
            .contextMenu {
                Button("Play", systemImage: "play.fill", action: onSelect)
                Button(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                       systemImage: isFavorite ? "heart.fill" : "heart", action: onToggleFavorite)
                if let onShowHealth {
                    Button("Channel Health", systemImage: "info.circle", action: onShowHealth)
                }
            }
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFavorite ? AppleDesignTokens.brandAccent : .secondary)
            .accessibilityLabel("\(isFavorite ? "Remove" : "Add") \(row.channel.name) \(isFavorite ? "from" : "to") favorites")
            .accessibilityIdentifier("guide.favorite.\(row.id)")
        }
        .padding(.leading, 8)
        .offset(x: scrollState.horizontalOffset)
    }
}

private struct GuideScheduleRow: View, Equatable {
    let row: AppleGuideRowModel
    let cellWidth: CGFloat
    let height: CGFloat
    let onSelect: () -> Void
    
    nonisolated static func == (lhs: GuideScheduleRow, rhs: GuideScheduleRow) -> Bool {
        lhs.row == rhs.row && lhs.cellWidth == rhs.cellWidth && lhs.height == rhs.height
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(row.spans) { cell in
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cell.title).font(.caption.bold()).lineLimit(2)
                        if let subtitle = cell.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    .padding(8)
                    .frame(width: cellWidth * CGFloat(cell.width), height: height, alignment: .topLeading)
                    .background(cell.isNow ? AppleDesignTokens.brandAccent.opacity(0.14) : AppleDesignTokens.surface)
                    .overlay(Rectangle().stroke(.white.opacity(0.08), lineWidth: 1))
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.channel.name), \(cell.title)")
            }
        }
    }
}
