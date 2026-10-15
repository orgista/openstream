import SwiftUI

/// The iPhone portrait hero's art (Discover and Library), from the top edge of
/// the screen to 73 % of it; the trailer plays over it (`AppleHomeBillboard`).
///
/// The art and its crop are settled before anything is drawn
/// (`AppleHeroPortraitArt`): TMDB is asked first (cache, or at most
/// `lookupDeadline` of network), the chosen image is decoded, and only then
/// does it fade in over black. Once a title's art has been shown it is
/// remembered for the run, so a later TMDB answer, a page coming back round
/// the carousel, or a re-render never re-crops or swaps it in front of the
/// viewer (owner items 6 and 19).
struct AppleHomePhonePortraitStage: View {
    let item: AppleCatalogItem
    /// The bottom of the large title, from the top of the art: the poster
    /// card stays below it (`AppleHeroPortraitArt.posterCardRect`).
    var topInset: CGFloat = 0
    /// Called once the art is on screen: the choice, its image (for the
    /// still's luminance reading) and the wordmark the choice brought.
    var onReady: (AppleHeroPortraitDecision, CGImage?) -> Void = { _, _ in }
    /// Set by a hero whose trailer can play: receives what the art is drawn
    /// from, at the frame's size, so the trailer can draw its cover from the
    /// same pixels and nothing jumps (`AppleHeroPortraitCover`). Nothing is
    /// rendered here; the trailer renders it once it has a video to play.
    var onCover: ((AppleHeroPortraitCover?) -> Void)? = nil

    @Environment(\.appleTMDBConfiguration) private var configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var shown: Shown?
    @State private var size: CGSize = .zero

    struct Shown: Equatable {
        let decision: AppleHeroPortraitDecision
        let image: CGImage?
        var focal: CGPoint = AppleHeroPortraitArt.focalPoint
        static func == (lhs: Shown, rhs: Shown) -> Bool {
            lhs.decision == rhs.decision && lhs.image === rhs.image && lhs.focal == rhs.focal
        }
    }

    private struct CoverRequest: Equatable {
        let shown: Shown?
        let size: CGSize
        let topInset: CGFloat
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let shown, let image = shown.image, size.width > 0, size.height > 0 {
                AppleHeroPortraitArtView(art: shown.decision.art, image: image, size: size, focal: shown.focal,
                                         topInset: topInset)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .accessibilityHidden(true)
        .task(id: item.mediaID) { await settle() }
        .onChange(of: CoverRequest(shown: shown, size: size, topInset: topInset), initial: true) { reportCover() }
    }

    /// Hands the shown art and the frame's size to the trailer, for its cover.
    private func reportCover() {
        guard let onCover else { return }
        guard let shown, let image = shown.image, size.width > 0, size.height > 0 else {
            onCover(nil)
            return
        }
        onCover(AppleHeroPortraitCover(art: shown.decision.art, image: image, size: size, focal: shown.focal,
                                       topInset: topInset, scale: displayScale))
    }

    private func settle() async {
        appleTrace("hero portrait settle \(item.name)")
        if let remembered = AppleHeroPortraitMemory.decision(for: item.mediaID) {
            var image: CGImage?
            if let url = remembered.art.imageURL {
                image = try? await AppleRemoteImageCache.shared.image(
                    url: url, maximumPixelDimension: AppleHeroPortraitArt.pixelDimension)
            }
            let focal = await focalPoint(for: remembered.art, image: image)
            guard !Task.isCancelled else { return }
            show(Shown(decision: remembered, image: image, focal: focal), animated: false)
            return
        }
        let started = ContinuousClock.now
        let tmdb = await tmdbArtwork()
        guard !Task.isCancelled else { return }
        appleTrace("hero portrait tmdb \(tmdb == nil ? "none" : "answered") after \(Self.ms(since: started)) (\(item.name))")
        let candidates = AppleHeroPortraitArt.Candidates(item: item, tmdbPoster: tmdb?.posterURL,
                                                         tmdbBackdrop: tmdb?.backdropURL, tmdbLogo: tmdb?.logoURL)
        var failed = Set<URL>()
        while true {
            let art = AppleHeroPortraitArt.choose(candidates, failed: failed)
            let decision = AppleHeroPortraitDecision(art: art, logo: candidates.logo)
            guard let url = art.imageURL else {
                AppleHeroPortraitMemory.remember(decision, for: item.mediaID)
                AppleHeroPortraitArtTally.record(art, item: item.name)
                show(Shown(decision: decision, image: nil), animated: false)
                return
            }
            do {
                let image = try await AppleRemoteImageCache.shared.image(
                    url: url, maximumPixelDimension: AppleHeroPortraitArt.pixelDimension)
                appleTrace("hero portrait image \(art.source.rawValue) decoded after \(Self.ms(since: started)) (\(item.name))")
                let focal = await focalPoint(for: art, image: image)
                guard !Task.isCancelled else { return }
                AppleHeroPortraitMemory.remember(decision, for: item.mediaID)
                AppleHeroPortraitArtTally.record(art, item: item.name)
                show(Shown(decision: decision, image: image, focal: focal), animated: true)
                return
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                appleTrace("hero portrait art failed \(art.source.rawValue), trying the next (\(item.name))")
                failed.insert(url)
            }
        }
    }

    private static func ms(since start: ContinuousClock.Instant) -> String {
        let elapsed = start.duration(to: .now).components
        return "\(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)ms"
    }

    private func tmdbArtwork() async -> AppleHeroArtworkUpgrade.Artwork? {
        guard let configuration, let imdbID = AppleHeroArtworkUpgrade.upgradeableIMDBID(for: item) else { return nil }
        return await AppleHeroArtworkUpgrade.shared.artwork(
            imdbID: imdbID, kind: item.type == "series" ? .series : .movie,
            configuration: configuration, deadline: AppleHeroPortraitMemory.lookupDeadline)
    }

    private func focalPoint(for art: AppleHeroPortraitArt, image: CGImage?) async -> CGPoint {
        guard case .backdrop(let url) = art, let image else { return AppleHeroPortraitArt.focalPoint }
        return (try? await AppleHeroFocalPoint.shared.point(image: image, url: url)) ?? CGPoint(x: 0.5, y: 0.5)
    }

    private func show(_ value: Shown, animated: Bool) {
        let duration = animated && !reduceMotion ? 0.25 : 0
        withAnimation(duration > 0 ? .easeOut(duration: duration) : nil) { shown = value }
        onReady(value.decision, value.image)
        AppleLaunchReadiness.shared.markFirstScreenReady()
    }
}

/// The hero's settled choice: its art and the wordmark that came with it.
struct AppleHeroPortraitDecision: Equatable, Sendable {
    let art: AppleHeroPortraitArt
    let logo: URL?
}

/// One answer per title per run: once shown, a hero's art never changes.
@MainActor
enum AppleHeroPortraitMemory {
    /// The longest the hero waits for TMDB before choosing from what it has.
    static let lookupDeadline: Duration = .milliseconds(1_500)
    private static var decisions: [String: AppleHeroPortraitDecision] = [:]

    static func decision(for mediaID: String) -> AppleHeroPortraitDecision? { decisions[mediaID] }
    static func remember(_ decision: AppleHeroPortraitDecision, for mediaID: String) {
        if decisions[mediaID] == nil { decisions[mediaID] = decision }
    }
}

/// The portrait hero's art as the stage draws it, for the trailer's cover:
/// the still under a starting or ending trailer is these pixels, at the
/// frame's size. Rendered only when a trailer is about to play (Fable review
/// 2026-10-14: rendering it on every settle stalled the main thread inside
/// the page slide, hero or no trailer).
struct AppleHeroPortraitCover: Equatable {
    let art: AppleHeroPortraitArt
    let image: CGImage
    let size: CGSize
    let focal: CGPoint
    let topInset: CGFloat
    let scale: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.art == rhs.art && lhs.image === rhs.image && lhs.size == rhs.size && lhs.focal == rhs.focal
            && lhs.topInset == rhs.topInset && lhs.scale == rhs.scale
    }

    /// Key art and backdrops are a plain crop, drawn off the main actor; the
    /// poster card's blur needs SwiftUI, so it goes through `ImageRenderer`.
    @MainActor
    func render() async -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let imageSize = CGSize(width: image.width, height: image.height)
        let rect: CGRect
        switch art {
        case .keyArt:
            rect = AppleHeroPortraitArt.fillRect(imageSize: imageSize, in: size)
        case .backdrop:
            rect = AppleHeroPortraitArt.fillRect(imageSize: imageSize, in: size, focal: focal,
                                                 subjectAnchor: CGPoint(x: 0.5, y: 0.4))
        case .posterCard:
            let renderer = ImageRenderer(content:
                AppleHeroPortraitArtView(art: art, image: image, size: size, focal: focal, topInset: topInset)
                    .frame(width: size.width, height: size.height)
                    .background(Color.black))
            renderer.scale = scale
            renderer.isOpaque = true
            return renderer.cgImage
        case .none:
            return nil
        }
        let (image, size, scale) = (image, size, scale)
        return await Task.detached(priority: .userInitiated) {
            Self.draw(image, in: rect, frame: size, scale: scale)
        }.value
    }

    /// `image` at `rect` (points, top-left origin) in an opaque black frame.
    nonisolated static func draw(_ image: CGImage, in rect: CGRect, frame: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((frame.width * scale).rounded())
        let height = Int((frame.height * scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        // Core Graphics counts up from the bottom.
        context.draw(image, in: CGRect(x: rect.minX, y: frame.height - rect.maxY, width: rect.width, height: rect.height))
        return context.makeImage()
    }
}

/// One portrait hero's art at `size`: drawn on screen by the stage, and once
/// more off screen for the trailer's cover.
struct AppleHeroPortraitArtView: View {
    let art: AppleHeroPortraitArt
    let image: CGImage
    let size: CGSize
    var focal: CGPoint = AppleHeroPortraitArt.focalPoint
    var topInset: CGFloat = 0

    var body: some View {
        let imageSize = CGSize(width: image.width, height: image.height)
        switch art {
        case .keyArt:
            AppleHeroCroppedImage(image: image, imageSize: imageSize, size: size)
        case .backdrop:
            AppleHeroCroppedImage(image: image, imageSize: imageSize, size: size, focal: focal,
                                  subjectAnchor: CGPoint(x: 0.5, y: 0.4))
        case .posterCard:
            let card = AppleHeroPortraitArt.posterCardRect(posterAspect: imageSize.width / max(imageSize.height, 1),
                                                           in: size, topInset: topInset)
            ZStack(alignment: .topLeading) {
                AppleHeroCroppedImage(image: image, imageSize: imageSize, size: size, focal: CGPoint(x: 0.5, y: 0.5))
                    .blur(radius: 40)
                    .overlay(Color.black.opacity(0.35))
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: card.width, height: card.height)
                    .clipShape(.rect(cornerRadius: 12))
                    .offset(x: card.minX, y: card.minY)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        case .none:
            Color.black
        }
    }
}

/// An image at its aspect-fill scale, placed by `AppleHeroPortraitArt.fillRect`.
struct AppleHeroCroppedImage: View {
    let image: CGImage
    let imageSize: CGSize
    let size: CGSize
    var focal: CGPoint = AppleHeroPortraitArt.focalPoint
    var subjectAnchor: CGPoint? = nil

    var body: some View {
        let rect = AppleHeroPortraitArt.fillRect(imageSize: imageSize, in: size, focal: focal, subjectAnchor: subjectAnchor)
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
    }
}
