import Foundation

enum AppleCatalogShelfPolicy {
    enum Style: Equatable, Sendable { case poster, featured, ranked }

    static func title(for catalog: AppleStremioCatalog) -> String {
        appleCatalogShelfTitle(sourceName: "", catalogType: catalog.type, catalogName: catalog.name, catalogID: catalog.id)
    }

    static func style(for catalog: AppleStremioCatalog) -> Style {
        let name = title(for: catalog).lowercased()
        if name.hasPrefix("top 10") { return .ranked }
        if name.hasPrefix("featured") || (name.contains("emmy") && name.contains("winners")) { return .featured }
        return .poster
    }

    static func rankedSubtitle(for item: AppleCatalogItem) -> String {
        [item.year.map { String($0) } ?? item.releaseInfo, item.genres?.first]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// The rows Discover draws: active sources, non-empty, in title order,
    /// and never two rows under one heading (owner, 2026-09-24: "Prime Video"
    /// appeared twice). Each row carries its heading in `shelfTitle`.
    ///
    /// When one name covers catalogs of different types — Cinemeta's
    /// "Popular" movies and "Popular" series — each reads "<name> Movies" /
    /// "<name> Shows". When it covers the same type twice, two add-ons list
    /// the same thing and the first by id is kept.
    static func visibleSections(
        _ sections: [AppleCatalogSection], activeSourceIDs: Set<AppleSource.ID>
    ) -> [AppleCatalogSection] {
        let shown = sections.filter { activeSourceIDs.contains($0.sourceID) && !$0.items.isEmpty }
        let titles = shown.map { title(for: $0.catalog) }
        var typesByTitle = [String: Set<String>]()
        for (section, title) in zip(shown, titles) {
            typesByTitle[title.lowercased(), default: []].insert(section.catalog.type.lowercased())
        }
        var seenIDs = Set<String>()
        var seenTitles = Set<String>()
        return zip(shown, titles).map { section, title -> AppleCatalogSection in
            var section = section
            section.shelfTitle = (typesByTitle[title.lowercased()]?.count ?? 0) > 1
                ? typedTitle(title, type: section.catalog.type) : title
            return section
        }.sorted {
            let order = ($0.shelfTitle ?? "").localizedCaseInsensitiveCompare($1.shelfTitle ?? "")
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }.filter {
            seenIDs.insert($0.id).inserted && seenTitles.insert(($0.shelfTitle ?? "").lowercased()).inserted
        }
    }

    /// "Popular" → "Popular Movies" / "Popular Shows"; a name that already
    /// ends in a type word swaps it rather than stacking a second one.
    static func typedTitle(_ title: String, type: String) -> String {
        let suffix: String
        switch type.lowercased() {
        case "movie": suffix = "Movies"
        case "series": suffix = "Shows"
        default: return title
        }
        var words = title.split(separator: " ").map(String.init)
        if let last = words.last?.lowercased(), ["movies", "movie", "shows", "series", "tv"].contains(last), words.count > 1 {
            words.removeLast()
        }
        return (words + [suffix]).joined(separator: " ")
    }

    /// First occurrence wins. A shelf keys its `ForEach` on `id`, so a repeated
    /// id draws one card twice under one accessibility identifier — which
    /// SwiftUI treats as undefined and XCTest cannot resolve.
    static func uniqueByID<Value: Identifiable>(_ values: [Value]) -> [Value] {
        var seen = Set<Value.ID>()
        return values.filter { seen.insert($0.id).inserted }
    }
}

/// A Discover row's heading.
///
/// A streaming service's catalog reads "<Service> Movies" / "<Service> Shows"
/// by its content type, so a service that publishes both never draws two rows
/// with one name ("Prime Movies" and "Prime Shows", never "Prime Video" twice —
/// owner, 2026-09-24). Every other catalog keeps its own name. Runs of
/// whitespace collapse to one space: the Streaming Catalogs add-on names its
/// Prime movies "Prime  Video".
func appleCatalogShelfTitle(sourceName _: String, catalogType: String, catalogName: String? = nil,
                            catalogID: String? = nil) -> String {
    let name = (catalogName ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if let service = AppleCatalogServiceName.streamingService(catalogID: catalogID, name: name) {
        switch catalogType.lowercased() {
        case "movie": return "\(service) Movies"
        case "series": return "\(service) Shows"
        default: return service
        }
    }
    if !name.isEmpty { return name }
    // Unnamed catalogs still get a useful heading, never an add-on name.
    switch catalogType.lowercased() {
    case "movie": return "Movies"
    case "series": return "Shows"
    default: return "Catalog"
    }
}
