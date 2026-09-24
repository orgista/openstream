import Foundation
#if DEBUG
import CryptoKit
#endif

/// Ordered image attempts, shared by portrait and landscape catalog cards.
/// An HTTP/decode failure must advance to the next URL, just like a nil URL.
enum AppleCatalogArtworkPolicy {
    #if DEBUG
    /// Correlates image attempts without recording URLs, hosts, or credentials.
    static func traceID(_ url: URL?) -> String {
        guard let url else { return "nil" }
        return SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
    }
    #endif

    static func candidates(item: AppleCatalogItem, landscape: Bool,
                           fallback: AppleArtworkResolver.Artwork? = nil) -> [URL] {
        let supplied = landscape
            ? [item.backgroundURL, item.posterURL]
            : [item.posterURL, item.backgroundURL]
        var values = supplied.compactMap { $0 }
        // Cinemeta's image service also works when an add-on returns no art,
        // or a stale art URL. It requires a canonical IMDb id, never a title
        // guessed from the rail or an add-on's private identifier.
        if AppleStremioMetadataClient.isIMDBIdentifier(item.mediaID) {
            let kinds = landscape ? ["background", "poster"] : ["poster", "background"]
            values += kinds.compactMap {
                URL(string: "https://images.metahub.space/\($0)/medium/\(item.mediaID)/img")
            }
        }
        values += (landscape ? [fallback?.backgroundURL, fallback?.posterURL]
                            : [fallback?.posterURL, fallback?.backgroundURL]).compactMap { $0 }
        var seen = Set<URL>()
        return values.filter { seen.insert($0).inserted }
    }

    /// How long a card that has run out of art waits before trying its
    /// candidates again, by how many times it already has; nil stops.
    ///
    /// A load that fails once — a timeout while a Library shelf asks for a
    /// hundred posters at once — used to latch the card to its title tile for
    /// as long as it stayed on screen: the grey tiles in Library › Movies
    /// for titles Discover showed posters for (owner, 2026-09-24).
    static func retryDelay(afterRetries retries: Int) -> Duration? {
        switch retries {
        case 0: .seconds(3)
        case 1: .seconds(10)
        default: nil
        }
    }

    static func next(in candidates: [URL], failed: Set<URL>) -> URL? {
        candidates.first { !failed.contains($0) }
    }
}
