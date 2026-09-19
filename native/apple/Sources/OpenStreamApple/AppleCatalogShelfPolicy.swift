import Foundation

enum AppleCatalogShelfPolicy {
    enum Style: Equatable, Sendable { case poster, featured, ranked }

    static func title(for catalog: AppleStremioCatalog) -> String {
        appleCatalogShelfTitle(sourceName: "", catalogType: catalog.type, catalogName: catalog.name)
    }

    static func style(for catalog: AppleStremioCatalog) -> Style {
        let name = title(for: catalog).lowercased()
        if name.hasPrefix("top 10") { return .ranked }
        if name.hasPrefix("featured") { return .featured }
        return .poster
    }

    static func visibleSections(
        _ sections: [AppleCatalogSection], activeSourceIDs: Set<AppleSource.ID>
    ) -> [AppleCatalogSection] {
        var seen = Set<String>()
        return sections.filter {
            activeSourceIDs.contains($0.sourceID) && !$0.items.isEmpty
        }.sorted {
            let order = title(for: $0.catalog).localizedCaseInsensitiveCompare(title(for: $1.catalog))
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }.filter { seen.insert($0.id).inserted }
    }
}

func appleCatalogShelfTitle(sourceName _: String, catalogType: String, catalogName: String? = nil) -> String {
    let name = catalogName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !name.isEmpty { return name }
    // Unnamed catalogs still get a useful heading, never an add-on name.
    switch catalogType.lowercased() {
    case "movie": return "Movies"
    case "series": return "Shows"
    default: return "Catalog"
    }
}
