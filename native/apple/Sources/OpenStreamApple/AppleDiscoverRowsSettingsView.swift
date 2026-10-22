import SwiftUI

/// Settings › Discover Rows: the rows on Discover, in the order they are
/// drawn, which the viewer can rearrange. iPhone, iPad, Vision Pro and the Mac
/// drag them (the list is always in reorder mode); the Apple TV picks a row up
/// with Select, carries it with up and down, and puts it down with Select or
/// Menu. Every row also has Move Up, Move Down and Move to Top for VoiceOver.
@MainActor
struct AppleDiscoverRowsSettingsView: View {
    let settings: AppleSettingsStore
    let sourceStore: AppleSourceStore
    #if os(tvOS)
    /// The row the remote is carrying, if any.
    @State private var carriedRowID: String?
    @FocusState private var focusedRowID: String?
    #endif

    struct Row: Identifiable, Hashable {
        let id: String
        let title: String
    }

    /// Every row Discover can draw right now, in the viewer's order.
    static func rows(settings: AppleSettingsStore, sourceStore: AppleSourceStore) -> [Row] {
        let enabled = sourceStore.sources.filter(\.isEnabled)
        var ids = [AppleDiscoverRowOrder.continueWatching, AppleDiscoverRowOrder.library]
        if enabled.contains(where: { $0.kind == .mediaServer }) { ids.append(AppleDiscoverRowOrder.mediaServers) }
        ids.append(AppleDiscoverRowOrder.topPicks)
        if settings.top10ListsEnabled, settings.top10ListsAvailable { ids += [AppleDiscoverRowOrder.top10Movies, AppleDiscoverRowOrder.top10Shows] }
        let defaultRows = ids.compactMap { id in AppleDiscoverRowOrder.title(forBuiltIn: id).map { Row(id: id, title: $0) } }
        let byID = Dictionary(defaultRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return AppleDiscoverRowOrder.resolve(available: defaultRows.map(\.id), custom: settings.discoverRowOrder)
            .compactMap { byID[$0] }
    }

    static func move(_ row: Row, to target: Int, in rows: [Row], settings: AppleSettingsStore) {
        guard let ids = AppleDiscoverRowOrder.moved(rows.map(\.id), id: row.id, to: target) else { return }
        settings.discoverRowOrder = ids
    }

    private var rows: [Row] {
        Self.rows(settings: settings, sourceStore: sourceStore)
    }

    var body: some View {
        let rows = rows
        list(rows)
        #if os(iOS) || os(visionOS)
        // Always reordering: the stock drag handles, no Edit button to find.
        .environment(\.editMode, .constant(.active))
        #endif
        #if os(tvOS)
        .onChange(of: focusedRowID) { _, focused in carry(to: focused) }
        .onExitCommand(perform: carriedRowID == nil ? nil : { carriedRowID = nil })
        #endif
        .appleSettingsPage("Discover Rows")
    }

    @ViewBuilder
    private func list(_ rows: [Row]) -> some View {
        #if os(tvOS)
        Form { sections(rows) }
        #else
        List { sections(rows) }
        #endif
    }

    @ViewBuilder
    private func sections(_ rows: [Row]) -> some View {
        Section {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowView(row)
                    .accessibilityActions { moveActions(row, index: index, rows: rows) }
            }
            #if !os(tvOS)
            .onMove { source, destination in
                settings.discoverRowOrder = AppleDiscoverRowOrder.moved(rows.map(\.id), fromOffsets: source,
                                                                       toOffset: destination)
            }
            #endif
        }
        Section {
            Button {
                settings.discoverRowOrder = nil
            } label: {
                #if os(tvOS)
                AppleTVFocusReadableText("Reset to Default Order")
                #else
                Text("Reset to Default Order")
                #endif
            }
            .disabled(settings.discoverRowOrder == nil)
            .accessibilityIdentifier("settings.discover.rows.reset")
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        #if os(tvOS)
        Button {
            carriedRowID = carriedRowID == row.id ? nil : row.id
            appleTrace("discoverRows.carry id=\(row.id) carrying=\(carriedRowID != nil)")
        } label: {
            HStack {
                AppleTVFocusReadableText(row.title)
                Spacer()
                if carriedRowID == row.id {
                    AppleTVCarriedRowGlyph()
                }
            }
        }
        .focused($focusedRowID, equals: row.id)
        .accessibilityValue(carriedRowID == row.id ? "Moving" : "")
        .accessibilityIdentifier("settings.discover.row.\(row.id)")
        #else
        Text(row.title)
            .accessibilityIdentifier("settings.discover.row.\(row.id)")
        #endif
    }

    @ViewBuilder
    private func moveActions(_ row: Row, index: Int, rows: [Row]) -> some View {
        // In reorder mode iOS and visionOS already give each row Move Up and
        // Move Down; only Move to Top is added there.
        #if os(iOS) || os(visionOS)
        let addsSteps = false
        #else
        let addsSteps = true
        #endif
        if index > 0 {
            if addsSteps {
                Button("Move Up") { Self.move(row, to: index - 1, in: rows, settings: settings) }
            }
            Button("Move to Top") { Self.move(row, to: 0, in: rows, settings: settings) }
        }
        if addsSteps, index < rows.count - 1 {
            Button("Move Down") { Self.move(row, to: index + 1, in: rows, settings: settings) }
        }
    }

    #if os(tvOS)
    /// Up and down move focus to the next row as usual; while a row is
    /// carried, it takes that row's place and focus comes back to it, so a
    /// long swipe carries it several rows at once. Focus leaving the rows
    /// (Reset, the sidebar, the tab bar) puts it down where it is.
    private func carry(to focused: String?) {
        guard let carried = carriedRowID, focused != carried else { return }
        let rows = rows
        guard let focused, let target = rows.firstIndex(where: { $0.id == focused }),
              let row = rows.first(where: { $0.id == carried }) else {
            carriedRowID = nil
            return
        }
        Self.move(row, to: target, in: rows, settings: settings)
        focusedRowID = carried
    }
    #endif
}

#if os(tvOS)
/// The carried row's mark, black on the white focus fill like its title.
private struct AppleTVCarriedRowGlyph: View {
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Image(systemName: "arrow.up.arrow.down")
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .accessibilityHidden(true)
    }
}

/// Button text for a tvOS settings Form. The app tints its controls white,
/// and a Form Button draws its label in the tint on the white focus fill too,
/// so the focused row read as a blank capsule; black while focused. A
/// destructive row (Cancel Download, Leave SharePlay) is system red both
/// ways, red on the white capsule while focused as tvOS's destructive alert
/// buttons draw. The focus platter maps a label's brightness to transparency
/// (black stays black, red came out pale pink, even for a
/// `role: .destructive` Button: N74 capture), so the red text is flattened
/// into one opaque layer first.
struct AppleTVFocusReadableText: View {
    private let title: String
    private let isDestructive: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, isDestructive: Bool = false) {
        self.title = title
        self.isDestructive = isDestructive
    }

    var body: some View {
        if isDestructive {
            Text(title)
                .foregroundStyle(isEnabled ? Color.red : Color.secondary)
                .drawingGroup()
        } else {
            Text(title)
                .foregroundStyle(isFocused ? Color.black : (isEnabled ? Color.white : Color.secondary))
        }
    }
}
#endif
