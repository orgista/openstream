import Foundation

@MainActor enum AppleTop10ArtworkLookup {
    static func find(
        title: String, type: String, seasonTitle: String?, sources: [AppleSource],
        client: AppleStremioCatalogClient = AppleStremioCatalogClient(),
        deadline: Duration = .seconds(4), retryDeadline: Duration = .seconds(12)
    ) async -> AppleCatalogSearchMatch? {
        // Configured metadata catalogs are asked first. Four catalogs and two
        // concurrent requests bound the work for each lazily visible card.
        let eligible = sources.compactMap { source -> AppleSource? in
            guard source.isEnabled, source.kind == .stremio else { return nil }
            var value = source
            value.catalogs = Array(source.catalogs.filter { $0.type == type && $0.supportsSearch }.prefix(1))
            return value.catalogs.isEmpty ? nil : value
        }
        let searchable = searchSources(eligible, type: type)
        for (attempt, budget) in [deadline, retryDeadline].enumerated() {
            let store = AppleCatalogSearchStore(client: client, debounce: .zero, deadline: budget, maximumConcurrentRequests: 2)
            await store.search(query: title, sources: searchable, baseSections: []) { _ in [] }
            guard !Task.isCancelled else { return nil }
            let match = store.lookup.match(title: title, type: type, seasonTitle: seasonTitle, ignoringLeadingArticle: true)
            let candidates = searchable.flatMap { store.lookup.relatedItems(for: $0.id) }
            #if DEBUG
            AppleInteractionTrace.record(.network,
                "Top10 lookup title=\(title) attempt=\(attempt + 1) matched=\(match != nil) candidates=\(candidates.prefix(20).map(\.name).joined(separator: " | "))")
            #endif
            if let match { return match }
            // A cold metadata search can outlive the interactive search budget.
            // Retry once with more time; an answered, unmatched search is final.
            guard candidates.isEmpty, let metrics = store.metrics,
                  metrics.fetchDuration >= budget else { return nil }
        }
        return nil
    }

    /// The configured search catalogs, then Cinemeta's — the same fallback the
    /// library's title lookup uses. Without it a setup whose add-ons expose no
    /// search catalog (the iPhone review sim's only add-on lists `tmdb.top`,
    /// `tmdb.trending`… and none of them searchable) asked nobody, and every
    /// Top 10 tile stayed a grey box with its title in it (N11, 2026-09-23).
    static func searchSources(_ eligible: [AppleSource], type: String) -> [AppleSource] {
        var values = Array(eligible.prefix(4))
        var cinemeta = AppleStremioMetadataClient.defaultMetadataSource
        guard !values.contains(where: { $0.manifestID == cinemeta.manifestID }) else { return values }
        cinemeta.resources = ["catalog", "meta"]
        cinemeta.catalogs = [.init(type: type, id: "top", supportsSearch: true)]
        values.append(cinemeta)
        return values
    }
}
