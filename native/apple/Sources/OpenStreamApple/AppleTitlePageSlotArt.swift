import CoreGraphics
import Foundation

/// The iPhone title page's header art: a 16:9 slot the trailer crossfades
/// over (Mythos §5). Known catalog art draws immediately; better metadata
/// can replace it after decoding, while the previous image stays visible.
public enum AppleTitlePageSlotArt: Equatable, Sendable {
    /// Fills the 16:9 slot exactly.
    case backdrop(URL)
    /// No backdrop anywhere: the poster as a card on a blurred copy of itself.
    case posterCard(URL)

    /// Backdrops first (textless first), then posters; failed images skipped.
    public static func choose(backdrops: [URL?], posters: [URL?], failed: Set<URL> = []) -> AppleTitlePageSlotArt? {
        if let url = backdrops.lazy.compactMap({ $0 }).first(where: { !failed.contains($0) }) { return .backdrop(url) }
        if let url = posters.lazy.compactMap({ $0 }).first(where: { !failed.contains($0) }) { return .posterCard(url) }
        return nil
    }

    /// Prefer a decoded backdrop, then a decoded poster, without starting
    /// any I/O. An uncached better candidate can replace this later.
    public static func chooseCached(backdrops: [URL?], posters: [URL?],
        cachedImage: (URL) -> CGImage?) -> (art: AppleTitlePageSlotArt, image: CGImage)? {
        let candidates = backdrops.compactMap { $0 }.map(Self.backdrop)
            + posters.compactMap { $0 }.map(Self.posterCard)
        for art in candidates {
            if let image = cachedImage(art.url) { return (art, image) }
        }
        return nil
    }

    /// An answer with no art is a stable placeholder; known art never waits
    /// for a provider or a timer to become eligible.
    public static func isReady(knownArt: AppleTitlePageSlotArt?, detailsAnswered: Bool) -> Bool {
        knownArt != nil || detailsAnswered
    }

    public static func updating(_ current: AppleTitlePageSlotArt?, with candidate: AppleTitlePageSlotArt?) -> AppleTitlePageSlotArt? {
        guard let candidate else { return current }
        if let current, case .backdrop = current, case .posterCard = candidate { return current }
        return candidate
    }

    /// Keep a first usable picture while a better candidate is still loading;
    /// after a picture is displayed, obsolete completions cannot replace it.
    public static func acceptsLoadedArt(_ loaded: AppleTitlePageSlotArt,
        requested: AppleTitlePageSlotArt?, displayed: AppleTitlePageSlotArt?) -> Bool {
        loaded == requested || displayed == nil
    }

    public var url: URL {
        switch self {
        case .backdrop(let url), .posterCard(let url): url
        }
    }

    public var isPosterCard: Bool {
        if case .posterCard = self { return true }
        return false
    }

    /// The slot's height: 16:9 of the width.
    public static func slotHeight(width: CGFloat) -> CGFloat {
        max(0, (width * 9 / 16).rounded())
    }
}
