import SwiftUI

/// Settings › Discover Rows: the rows on Discover, in the order they are
/// drawn, which the viewer can rearrange. iPhone, iPad and Vision Pro drag
/// them in edit mode, the Mac has Move Up/Move Down beside each row, and the
/// Apple TV picks a row with Select and moves it from a menu.
@MainActor
struct AppleDiscoverRowsSettingsView: View {
    let settings: AppleSettingsStore
    let sourceStore: AppleSourceStore
    let catalogStore: AppleCatalogStore?

    struct Row: Identifiable, Hashable {
        let id: String
        let title: String
    }

    #if os(tvOS)
    @State private var picked: Row?
    @State private var showsMoveMenu = false
    #endif

    /// Every row Discover can draw right now, in its own order.
    private var defaultRows: [Row] {
        let enabled = sourceStore.sources.filter(\.isEnabled)
        var ids = [AppleDiscoverRowOrder.continueWatching, AppleDiscoverRowOrder.library]
        if enabled.contains(where: { $0.kind == .mediaServer }) { ids.append(AppleDiscoverRowOrder.mediaServers) }
        ids.append(AppleDiscoverRowOrder.topPicks)
        if settings.top10ListsEnabled { ids += [AppleDiscoverRowOrder.top10Movies, AppleDiscoverRowOrder.top10Shows] }
        var rows = ids.compactMap { id in AppleDiscoverRowOrder.title(forBuiltIn: id).map { Row(id: id, title: $0) } }
        let sections = AppleCatalogShelfPolicy.visibleSections(catalogStore?.sections ?? [],
                                                               activeSourceIDs: Set(enabled.map(\.id)))
        rows += sections.map { section in
            Row(id: AppleDiscoverRowOrder.catalogID(section.id),
                title: section.shelfTitle ?? AppleCatalogShelfPolicy.title(for: section.catalog))
        }
        return rows
    }

    private var rows: [Row] {
        let byID = Dictionary(defaultRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return AppleDiscoverRowOrder.resolve(available: defaultRows.map(\.id), custom: settings.discoverRowOrder)
            .compactMap { byID[$0] }
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
                Button("Reset to Default Order") {
                    settings.discoverRowOrder = nil
                }
                .disabled(settings.discoverRowOrder == nil)
                .accessibilityIdentifier("settings.discover.rows.reset")
            }
        }
        #if os(iOS) || os(visionOS)
        .toolbar { EditButton() }
        #endif
        #if os(tvOS)
        .confirmationDialog(picked?.title ?? "", isPresented: $showsMoveMenu, presenting: picked) { row in
            let index = rows.firstIndex(of: row) ?? 0
            if index > 0 {
                Button("Move to Top") { move(row, to: 0, in: rows) }
                Button("Move Up") { move(row, to: index - 1, in: rows) }
            }
            if index < rows.count - 1 {
                Button("Move Down") { move(row, to: index + 1, in: rows) }
                Button("Move to Bottom") { move(row, to: rows.count - 1, in: rows) }
            }
        }
        #endif
        .appleSettingsPage("Discover Rows")
    }

    @ViewBuilder
    private func rowView(_ row: Row, index: Int, count: Int) -> some View {
        #if os(tvOS)
        Button(row.title) {
            picked = row
            showsMoveMenu = true
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
        guard let index = rows.firstIndex(of: row), rows.indices.contains(target) else { return }
        var ids = rows.map(\.id)
        ids.remove(at: index)
        ids.insert(row.id, at: target)
        settings.discoverRowOrder = ids
    }
}
