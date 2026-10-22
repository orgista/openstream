import Foundation

/// Resolves identity through the existing metadata clients and the caller's Search pipeline.
/// No navigation or UI state is held here.
struct AppleSharedLinkResolution {
    let record: AppleMediaRecord?
    let item: AppleCatalogItem?
    let title: AppleSharedLinkResolver.Title?

    @MainActor
    static func resolve(_ link: SharedLink, records: [AppleMediaRecord], sources: [AppleSource],
                        configuration: AppleTMDBConfiguration?,
                        pageResolver: AppleSharedLinkResolver = AppleSharedLinkResolver(),
                        tmdb: AppleTMDBClient = AppleTMDBClient(),
                        search: (String) async -> [AppleMediaRecord]) async throws -> Self {
        var directItem: AppleCatalogItem?
        var directRecord: AppleMediaRecord?
        var title: AppleSharedLinkResolver.Title?
        switch link {
        case .imdb(let id):
            directRecord = records.first { $0.canonicalID == id }
            if directRecord == nil, let configuration = configuration {
                directItem = try? await tmdb.sharedLinkDetails(imdbID: id, configuration: configuration)
            }
        case .tmdb(let kind, let id):
            guard let configuration = configuration else { throw AppleSharedLinkError.unreadable }
            directItem = try await tmdb.sharedLinkDetails(id: id, kind: kind, configuration: configuration)
        default:
            title = try await pageResolver.title(for: link)
        }
        if let title {
            appleTrace("shared link title \(title.name) year=\(title.year.map(String.init) ?? "-")")
            let results = await search(title.name)
            directRecord = AppleSharedLinkResolver.bestMatch(title, records: results)
            if directRecord == nil, let configuration = configuration {
                let items = (try? await tmdb.sharedLinkSearch(title: title, configuration: configuration)) ?? []
                let records = items.map { AppleMediaRecord(canonicalID: $0.mediaID,
                    kind: $0.type == "movie" ? .movie : .series, title: $0.name, year: $0.year, availability: []) }
                if let match = AppleSharedLinkResolver.bestMatch(title, records: records),
                   let index = records.firstIndex(where: { $0.id == match.id }) {
                    let candidate = items[index]
                    let pieces = candidate.mediaID.split(separator: ":")
                    if pieces.count == 3, pieces[0] == "tmdb", let id = Int(pieces[2]) {
                        directItem = try await tmdb.sharedLinkDetails(id: id, kind: pieces[1] == "movie" ? .movie : .show, configuration: configuration)
                    } else { directItem = candidate }
                }
            }
        }
        if directItem == nil, let record = directRecord {
            directItem = AppleCatalogItem(mediaID: record.canonicalID ?? record.id,
                type: record.kind == .series ? "series" : "movie", name: record.title,
                posterURL: record.artworkURL, backgroundURL: record.backdropURL,
                summary: record.summary, releaseInfo: record.year.map(String.init), year: record.year)
        }
        try Task.checkCancellation()
        return Self(record: directRecord, item: directItem, title: title)
    }
}
