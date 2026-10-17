import Foundation
import CoreGraphics

/// Pure policies for deciding what artwork to prefetch.
public enum AppleArtworkPrefetchPolicy {
    struct Request: Hashable, Sendable {
        let url: URL
        let maximumPixelDimension: Int
    }

    static func requests(items: [AppleCatalogItem], pixels: CGSize, landscape: Bool,
                         after itemID: String? = nil) -> [Request] {
        let start = itemID.flatMap { id in items.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
        var seen = Set<Request>()
        return items.dropFirst(start).prefix(20).compactMap { item in
            guard let candidate = AppleCatalogArtworkPolicy.candidates(item: item, landscape: landscape).first else { return nil }
            let purpose = AppleCatalogArtworkPolicy.purpose(of: candidate, item: item, fallback: nil,
                                                          preferred: landscape ? .resume : .poster)
            let display = AppleCatalogArtworkPolicy.displayRequest(url: candidate, pixels: pixels, purpose: purpose)
            guard let url = display.url else { return nil }
            let request = Request(url: url, maximumPixelDimension: display.fixedPixelDimension.map(AppleArtworkSizePolicy.bucket)
                ?? AppleArtworkSizePolicy.bucket(size: pixels, scale: 1))
            return seen.insert(request).inserted ? request : nil
        }
    }

    /// Returns the URLs to prefetch for a list of catalogue sections.
    ///
    /// Preserves order (first position wins) and removes duplicates.
    /// - Parameters:
    ///   - sections: The sections of items.
    ///   - perSection: The maximum number of items to inspect per section.
    public static func urls(sections: [[AppleCatalogItem]], perSection: Int = 20) -> [URL] {
        var urls: [URL] = []
        var seen: Set<URL> = []

        for section in sections {
            let items = section.prefix(perSection)
            for item in items {
                // The item's poster, backdrop/background and logo URLs (if available).
                // AppleCatalogItem currently provides posterURL and backgroundURL.
                let candidates = [item.posterURL, item.backgroundURL].compactMap { $0 }
                for url in candidates {
                    if !seen.contains(url) {
                        seen.insert(url)
                        urls.append(url)
                    }
                }
            }
        }
        return urls
    }

    /// Warm the next twenty items from the settled focus, excluding that item.
    public static func ahead(after itemID: String, in items: [AppleCatalogItem]) -> [URL] {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return [] }
        return urls(sections: [Array(items.dropFirst(index + 1).prefix(20))], perSection: 20)
    }

    /// Returns the URLs to prefetch for a detail view.
    ///
    /// Preserves order (first position wins) and removes duplicates.
    /// - Parameters:
    ///   - item: The primary item.
    ///   - episodeThumbnails: The thumbnails of the episodes to be shown.
    ///   - limit: The maximum number of episode thumbnails to include.
    public static func urls(forDetail item: AppleCatalogItem, episodeThumbnails: [URL], limit: Int = 20) -> [URL] {
        var urls: [URL] = []
        var seen: Set<URL> = []

        // The item's logo, backdrop, poster first.
        let candidates = [item.backgroundURL, item.posterURL].compactMap { $0 }
        for url in candidates {
            if !seen.contains(url) {
                seen.insert(url)
                urls.append(url)
            }
        }

        for url in episodeThumbnails.prefix(limit) {
            if !seen.contains(url) {
                seen.insert(url)
                urls.append(url)
            }
        }
        return urls
    }
}
