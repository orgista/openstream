import SwiftUI

/// Settings › Discover Rows: the rows on Discover, in the order they are
/// drawn, which the viewer can rearrange. iPhone, iPad and Vision Pro drag
/// them in edit mode, the Mac has Move Up/Move Down beside each row, and the
/// Apple TV opens a row and picks where it goes on a small pushed page.
@MainActor
struct AppleDiscoverRowsSettingsView: View {
    let settings: AppleSettingsStore
    let sourceStore: AppleSourceStore
    let catalogStore: AppleCatalogStore?

    struct Row: Identifiable, Hashable {
        let id: String
        let title: String
    }

    /// Every row Discover can draw right now, in the viewer's order.
    static func rows(settings: AppleSettingsStore, sourceStore: AppleSourceStore,
                     catalogStore: AppleCatalogStore?) -> [Row] {
        let enabled = sourceStore.sources.filter(\.isEnabled)
        var ids = [AppleDiscoverRowOrder.continueWatching, AppleDiscoverRowOrder.library]
        if enabled.contains(where: { $0.kind == .mediaServer }) { ids.append(AppleDiscoverRowOrder.mediaServers) }
        ids.append(AppleDiscoverRowOrder.topPicks)
        if settings.top10ListsEnabled { ids += [AppleDiscoverRowOrder.top10Movies, AppleDiscoverRowOrder.top10Shows] }
        var defaultRows = ids.compactMap { id in AppleDiscoverRowOrder.title(forBuiltIn: id).map { Row(id: id, title: $0) } }
        let sections = AppleCatalogShelfPolicy.visibleSections(catalogStore?.sections ?? [],
                                                               activeSourceIDs: Set(enabled.map(\.id)))
        defaultRows += sections.map { section in
            Row(id: AppleDiscoverRowOrder.catalogID(section.id),
                title: section.shelfTitle ?? AppleCatalogShelfPolicy.title(for: section.catalog))
        }
        let byID = Dictionary(defaultRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return AppleDiscoverRowOrder.resolve(available: defaultRows.map(\.id), custom: settings.discoverRowOrder)
            .compactMap { byID[$0] }
    }

    static func move(_ row: Row, to target: Int, in rows: [Row], settings: AppleSettingsStore) {
        guard let index = rows.firstIndex(of: row), rows.indices.contains(target) else { return }
        var ids = rows.map(\.id)
        ids.remove(at: index)
        ids.insert(row.id, at: target)
        settings.discoverRowOrder = ids
    }

    private var rows: [Row] {
        Self.rows(settings: settings, sourceStore: sourceStore, catalogStore: catalogStore)
    }

    var body: some View {
        let rows = rows
        Form {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row, index: index, count: rows.count)
                }
                .onMove { source, destination in
                    var ids = rows.map(\.id)
                    ids.move(fromOffsets: source, toOffset: destination)
                    settings.discoverRowOrder = ids
                }
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
        #if os(iOS) || os(visionOS)
        .toolbar { EditButton() }
        #endif
        #if os(tvOS)
        // A confirmationDialog drew its focused choice white on the white
        // focus fill (N71 capture) and takes no label styling, so the Apple
        // TV pushes a page of choices instead.
        .navigationDestination(for: AppleTVDiscoverRowMoveRoute.self) { route in
            AppleTVDiscoverRowMovePage(row: route.row, settings: settings, sourceStore: sourceStore,
                                       catalogStore: catalogStore)
        }
        #endif
        .appleSettingsPage("Discover Rows")
        .task(id: catalogConfigurationIdentity(sourceStore.sources)) {
            // Catalogue shelves are read from the cache by Discover; opening
            // Settings first (or with Discover hidden) listed only the
            // built-in rows. Never while a refresh runs: loading the cache
            // cancels it, and the refresh publishes the shelves itself.
            guard let catalogStore else { return }
            appleTrace("discoverRows.catalogs sections=\(catalogStore.sections.count) loading=\(catalogStore.isLoading) sources=\(sourceStore.sources.count)")
            guard catalogStore.sections.isEmpty, !catalogStore.isLoading else { return }
            await catalogStore.loadCachedSections(sources: sourceStore.sources)
            appleTrace("discoverRows.catalogs loaded=\(catalogStore.sections.count)")
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, index: Int, count: Int) -> some View {
        #if os(tvOS)
        // A link, not a Button: the Form's links flip to black text on the
        // white focus fill, its Buttons kept the app's white tint (N71).
        NavigationLink(value: AppleTVDiscoverRowMoveRoute(row: row)) {
            AppleTVNavigationLabel(row.title)
        }
        .accessibilityIdentifier("settings.discover.row.\(row.id)")
        #elseif os(macOS)
        HStack {
            Text(row.title)
            Spacer()
            Button("Move Up", systemImage: "chevron.up") { move(row, to: index - 1, in: rows) }
                .disabled(index == 0)
            Button("Move Down", systemImage: "chevron.down") { move(row, to: index + 1, in: rows) }
                .disabled(index == count - 1)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .accessibilityIdentifier("settings.discover.row.\(row.id)")
        #else
        Text(row.title)
            .accessibilityIdentifier("settings.discover.row.\(row.id)")
        #endif
    }

    private func move(_ row: Row, to target: Int, in rows: [Row]) {
        Self.move(row, to: target, in: rows, settings: settings)
    }
}

#if os(tvOS)
struct AppleTVDiscoverRowMoveRoute: Hashable {
    let row: AppleDiscoverRowsSettingsView.Row
}

/// "Move <Row>": where the picked row goes. A choice moves it and pops back
/// to the list, Menu leaves the order as it was.
@MainActor
private struct AppleTVDiscoverRowMovePage: View {
    let row: AppleDiscoverRowsSettingsView.Row
    let settings: AppleSettingsStore
    let sourceStore: AppleSourceStore
    let catalogStore: AppleCatalogStore?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let rows = AppleDiscoverRowsSettingsView.rows(settings: settings, sourceStore: sourceStore,
                                                      catalogStore: catalogStore)
        let index = rows.firstIndex(of: row)
        Form {
            Section {
                if let index, index > 0 {
                    choice("Move to Top", id: "top", to: 0, in: rows)
                    choice("Move Up", id: "up", to: index - 1, in: rows)
                }
                if let index, index < rows.count - 1 {
                    choice("Move Down", id: "down", to: index + 1, in: rows)
                    choice("Move to Bottom", id: "bottom", to: rows.count - 1, in: rows)
                }
            }
        }
        .appleSettingsPage("Move \(row.title)")
    }

    private func choice(_ title: String, id: String, to target: Int,
                        in rows: [AppleDiscoverRowsSettingsView.Row]) -> some View {
        Button {
            AppleDiscoverRowsSettingsView.move(row, to: target, in: rows, settings: settings)
            dismiss()
        } label: {
            AppleTVFocusReadableText(title)
        }
        .accessibilityIdentifier("settings.discover.move.\(id)")
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
