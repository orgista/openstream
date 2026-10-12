import Foundation

enum AppleRecommendationRowPolicy {
    /// Feed presentation may hide duplicate headings; candidate availability
    /// still includes every current catalog, and excludes disabled/stale routes.
    static func accessibleCatalogs(_ sections: [AppleCatalogSection], sources: [AppleSource]) -> [AppleCatalogSearchMatch] {
        let enabled = Dictionary(sources.filter(\.isEnabled).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return sections.flatMap { section -> [AppleCatalogSearchMatch] in
            guard AppleCatalogDiscoveryPolicy.isTitleType(section.catalog.type),
                  let source = enabled[section.sourceID],
                  section.sourceConfigurationID == AppleCatalogDiscoveryPolicy.sourceConfigurationID(for: source) else { return [] }
            return section.items.filter { AppleCatalogDiscoveryPolicy.isTitleType($0.type) }.map { AppleCatalogSearchMatch(item: $0, source: source) }
        }
    }

    static func appendingSeed<Rail>(_ seed: Rail?, to configured: [Rail]) -> [Rail] {
        guard let seed else { return configured }
        return configured + [seed]
    }

    static func heading(seed: String, count: Int, existing: [String]) -> String? {
        let title = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, count >= 6 else { return nil }
        let heading = "Because you watched \(title)"
        guard !existing.contains(where: { $0.compare(heading, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { return nil }
        return heading
    }
}
