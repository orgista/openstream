import CoreGraphics
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
            values += kinds.compactMap { imageServiceURL(kind: $0, mediaID: item.mediaID) }
        }
        values += (landscape ? [fallback?.backgroundURL, fallback?.posterURL]
                            : [fallback?.posterURL, fallback?.backgroundURL]).compactMap { $0 }
        var seen = Set<URL>()
        return values.filter { seen.insert($0).inserted }
    }

    /// Cinemeta's image-service art for an IMDb id: "poster" or "background".
    static func imageServiceURL(kind: String, mediaID: String) -> URL? {
        guard AppleStremioMetadataClient.isIMDBIdentifier(mediaID) else { return nil }
        return URL(string: "https://images.metahub.space/\(kind)/medium/\(mediaID)/img")
    }

    /// How long a card that has run out of art waits before trying its
    /// candidates again, by how many times it already has; nil stops.
    ///
    /// A load that fails once — a timeout while a Library shelf asks for a
    /// hundred posters at once — used to latch the card to its title tile for
    /// as long as it stayed on screen: the grey tiles in Library › Movies
    /// for titles Discover showed posters for (owner, 2026-09-24).
    /// What a poster is printed on. Some "posters" are a logo on a plate —
    /// transparent, or pure black ("Law & Order", "The Chosen", N32 #16) —
    /// and on the black page the card's edge vanishes, so the logo floats.
    /// Those draw on the card's dark rounded tile, as the Apple TV app does.
    enum Plate: Equatable, Sendable { case none, transparent, black }

    /// Reads the image's border at a 12 × 18 sample. A plate is at least 85 %
    /// of the border clear or true black (a JPEG plate decodes to 0–3); a
    /// band of colour reaching the edge, as Law & Order's does, still counts.
    static func plate(of image: CGImage) -> Plate {
        let width = 12, height = 18
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return .none }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var border: [(UInt8, UInt8, UInt8, UInt8)] = []
        for y in 0 ..< height {
            for x in 0 ..< width where x == 0 || y == 0 || x == width - 1 || y == height - 1 {
                let i = (y * width + x) * 4
                border.append((data[i], data[i + 1], data[i + 2], data[i + 3]))
            }
        }
        return plate(border: border)
    }

    static func plate(border: [(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)]) -> Plate {
        guard !border.isEmpty else { return .none }
        let needed = Double(border.count) * 0.85
        let clear = border.filter { $0.alpha < 250 }.count
        if Double(clear) >= needed { return .transparent }
        let black = border.filter { $0.alpha < 250 || max($0.red, $0.green, $0.blue) <= 8 }.count
        return Double(black) >= needed ? .black : .none
    }

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
