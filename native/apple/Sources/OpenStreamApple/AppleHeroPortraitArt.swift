import CoreGraphics
import Foundation

/// What the iPhone's portrait hero (Discover and Library) draws, chosen once,
/// before anything is shown, and never changed while the page is up (owner
/// items 6 and 19, spec `live-hero-redesign-2026-10-09` §4.2, Mythos §2.7).
///
/// Order, first hit wins:
/// 1. **Key art**: TMDB's textless (`null`-language) poster, with the wordmark
///    or the name drawn over it.
/// 2. **Backdrop**: TMDB's textless backdrop, cropped with a fixed top bias
///    (`focalPoint`).
/// 3. **Card**: titled art on a blurred copy of itself, never cropped: the
///    item's own poster, else its own backdrop. The text title is then
///    suppressed so the name never appears twice. Every hit is traced.
/// 4. Nothing: the name over black (`AppleHeroTitlePolicy`).
///
/// Only TMDB records which images are textless (a `null` language), so the
/// item's own poster and backdrop count as titled: aspect-filling one into
/// the full-bleed frame cut its printed title in half and put the wordmark
/// under it a second time (lead review 2026-10-14).
///
/// Media servers and IPTV map onto the same slots through the item:
/// Jellyfin `Primary` / Plex `thumb` / Xtream `stream_icon` are the poster,
/// Jellyfin `Backdrop` / Plex `art` / Xtream `backdrop_path` the backdrop,
/// Jellyfin `Logo` / Plex `clearLogo` the wordmark. None of them carries a
/// language, so they count as titled too.
public enum AppleHeroPortraitArt: Equatable, Sendable {
    case keyArt(URL)
    case backdrop(URL)
    case posterCard(URL)
    case none

    /// Every image a hero could draw, by kind.
    public struct Candidates: Equatable, Sendable {
        public var textlessPoster: URL?
        /// A poster whose language is unknown or set: treated as titled.
        public var poster: URL?
        public var textlessBackdrop: URL?
        /// A backdrop whose language is unknown or set: treated as titled.
        public var backdrop: URL?
        public var logo: URL?

        public init(textlessPoster: URL? = nil, poster: URL? = nil, textlessBackdrop: URL? = nil,
                    backdrop: URL? = nil, logo: URL? = nil) {
            self.textlessPoster = textlessPoster
            self.poster = poster
            self.textlessBackdrop = textlessBackdrop
            self.backdrop = backdrop
            self.logo = logo
        }

        /// A catalog, library, media-server or IPTV item, plus TMDB's answer
        /// when the item has an IMDB id and TMDB is configured.
        public init(item: AppleCatalogItem, tmdbPoster: URL? = nil, tmdbBackdrop: URL? = nil, tmdbLogo: URL? = nil) {
            self.init(textlessPoster: tmdbPoster, poster: item.posterURL, textlessBackdrop: tmdbBackdrop,
                      backdrop: item.backgroundURL, logo: tmdbLogo ?? item.logoURL)
        }
    }

    /// For the trace and the hit-rate tally.
    public enum Source: String, Sendable {
        case poster, backdrop, fallback, none
    }

    /// Constant top bias for slice 1 (a Vision focal point is slice 2).
    public static let focalPoint = CGPoint(x: 0.5, y: 0.35)

    /// The decode budget for the hero's still, in pixels on the long side.
    public static let pixelDimension = 1_800

    /// First hit wins; an image that failed to load is skipped.
    public static func choose(_ candidates: Candidates, failed: Set<URL> = []) -> AppleHeroPortraitArt {
        func usable(_ url: URL?) -> URL? { url.flatMap { failed.contains($0) ? nil : $0 } }
        if let poster = usable(candidates.textlessPoster) { return .keyArt(poster) }
        if let backdrop = usable(candidates.textlessBackdrop) { return .backdrop(backdrop) }
        if let titled = usable(candidates.poster) ?? usable(candidates.backdrop) { return .posterCard(titled) }
        return .none
    }

    public var imageURL: URL? {
        switch self {
        case .keyArt(let url), .backdrop(let url), .posterCard(let url): url
        case .none: nil
        }
    }

    public var source: Source {
        switch self {
        case .keyArt: .poster
        case .backdrop: .backdrop
        case .posterCard: .fallback
        case .none: .none
        }
    }

    /// False when the art already says the name (a titled poster): the hero
    /// then keeps only its metadata line and buttons, so the title never
    /// shows twice. Wordmark and text title alike are suppressed.
    public var showsTitle: Bool {
        if case .posterCard = self { return false }
        return true
    }

    /// The image's aspect-fill rect in a frame of `frame`, placed so that
    /// `focal` (normalised in the image) sits as close to the same place in
    /// the frame as the image's edges allow. Never leaves a gap.
    public static func fillRect(imageSize: CGSize, in frame: CGSize, focal: CGPoint = focalPoint,
                                subjectAnchor: CGPoint? = nil) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, frame.width > 0, frame.height > 0 else {
            return CGRect(origin: .zero, size: frame)
        }
        let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let overflowX = size.width - frame.width
        let overflowY = size.height - frame.height
        let x: CGFloat, y: CGFloat
        if let subjectAnchor {
            x = min(0, max(-overflowX, frame.width * subjectAnchor.x - size.width * focal.x))
            y = min(0, max(-overflowY, frame.height * subjectAnchor.y - size.height * focal.y))
        } else {
            x = -overflowX * min(max(focal.x, 0), 1)
            y = -overflowY * min(max(focal.y, 0), 1)
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// What the poster card leaves clear at the bottom of the art: the
    /// metadata line, the buttons and the page dots (its title is suppressed).
    public static let posterCardBottomReserve: CGFloat = 160
    /// The card's width as a share of the screen's, when the height allows.
    public static let posterCardWidthFraction: CGFloat = 0.6
    /// The same for a titled backdrop, which is wider than it is tall.
    public static let landscapeCardWidthFraction: CGFloat = 0.9

    /// Where the card (a titled poster, or a titled backdrop) sits in a full-height hero (`frame` from the top
    /// edge of the screen): centred across, and centred between the bottom
    /// of the large title (`topInset`) and the copy, shrunk to fit there, so
    /// the poster's own title is never under the navigation bar or the buttons.
    public static func posterCardRect(posterAspect: CGFloat, in frame: CGSize, topInset: CGFloat) -> CGRect {
        guard posterAspect > 0, frame.width > 0, frame.height > 0 else { return .zero }
        let top = max(topInset, 0) + 12
        let room = max(frame.height - posterCardBottomReserve - top, 0)
        var width = frame.width * (posterAspect > 1 ? landscapeCardWidthFraction : posterCardWidthFraction)
        var height = width / posterAspect
        if height > room {
            height = room
            width = height * posterAspect
        }
        return CGRect(x: (frame.width - width) / 2, y: top + (room - height) / 2, width: width, height: height)
    }
}

/// How often each art source has been drawn this run, for the trace
/// (owner: log how often the poster-card fallback is hit).
@MainActor
enum AppleHeroPortraitArtTally {
    private(set) static var counts: [AppleHeroPortraitArt.Source: Int] = [:]

    static func record(_ art: AppleHeroPortraitArt, item: String) {
        counts[art.source, default: 0] += 1
        let summary = [AppleHeroPortraitArt.Source.poster, .backdrop, .fallback, .none]
            .map { "\($0.rawValue)=\(counts[$0] ?? 0)" }.joined(separator: " ")
        appleTrace("hero portrait art \(art.source.rawValue) (\(item)) tally \(summary)")
    }
}
