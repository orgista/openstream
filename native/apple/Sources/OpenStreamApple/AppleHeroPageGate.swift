import SwiftUI

/// The art one billboard page draws: what the hero will ask the image caches
/// for when that page is shown.
struct AppleHeroPageArt: Equatable {
    let id: String
    let backdrop: URL?
    /// Nil when the page has none, or at the accessibility sizes, which draw the name.
    let wordmark: URL?

    /// Changes when the page's art is upgraded, so upgraded art is warmed again.
    var key: String { "\(id)|\(backdrop?.absoluteString ?? "")|\(wordmark?.absoluteString ?? "")" }
}

/// The frames the hero draws its backdrop and wordmark in. The image caches
/// are keyed by pixel size, so a page is only warm when it was fetched at
/// exactly these.
struct AppleHeroPageSlots: Equatable {
    /// Nil: as wide as the gate's own content, measured.
    var backdropWidth: CGFloat?
    var backdropHeight: CGFloat
    var wordmark: CGSize
}

/// Holds the billboard on the page it is showing until the page the clock
/// asks for has decoded its backdrop and wordmark, then hands over the new
/// index so art, wordmark and copy change on the same frame. The rotation
/// owner can start its dwell clock when `onPresent` reports settled art.
/// See `AppleHeroPageSwap`.
///
/// The Apple TV has used it since 2026-09-22 (674ff48); the iPad and a phone
/// on its side followed the same day, after the iPad showed one title's
/// wordmark over the next title's copy on a bare surface mid-rotation.
struct AppleHeroPageGate<Content: View>: View {
    let pages: [AppleHeroPageArt]
    let requested: Int
    let slots: AppleHeroPageSlots
    var presentationRequest: Int = 0
    /// The page index to draw, and whether its wordmark failed to load (the
    /// billboard then falls back to the text title).
    @ViewBuilder let content: (_ index: Int, _ wordmarkFailed: Bool) -> Content

    var onPresent: (_ index: Int) -> Void = { _ in }

    @State private var shownID: String?
    @State private var readyKeys: Set<String> = []
    @State private var failedWordmarkKeys: Set<String> = []
    @State private var measuredWidth: CGFloat = 0

    var body: some View {
        let index = shownIndex
        content(index, failedWordmarkKeys.contains(pages[index].key))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth = $0 }
            .background {
                // Invisible, non-interactive copies at the billboard's own
                // sizes, so the swap finds both caches warm.
                if backdropSize.width > 0 {
                    ZStack {
                        ForEach(pagesToWarm, id: \.key) { page in
                            AppleHeroPagePreload(page: page, backdropSize: backdropSize,
                                                 wordmarkSize: slots.wordmark) { wordmarkFailed in
                                if wordmarkFailed { failedWordmarkKeys.insert(page.key) }
                                readyKeys.insert(page.key)
                            }
                        }
                    }
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: requestedPage, initial: true) { advance() }
            .onChange(of: presentationRequest) { advance() }
            .onChange(of: readyKeys) { advance() }
            // A new size (a rotation) must be fetched again before it counts.
            .onChange(of: backdropSize) { readyKeys = [] }
    }

    private var backdropSize: CGSize {
        CGSize(width: slots.backdropWidth ?? measuredWidth, height: slots.backdropHeight)
    }

    private var requestedPage: AppleHeroPageArt { pages[requested] }

    private var shownIndex: Int {
        guard let shownID, let index = pages.firstIndex(where: { $0.id == shownID }) else { return requested }
        return index
    }

    private var pagesToWarm: [AppleHeroPageArt] {
        AppleHeroPageSwap.pagesToWarm(requested: requested, count: pages.count)
            .map { pages[$0] }
            .filter { !readyKeys.contains($0.key) }
    }

    private func advance() {
        let current = pages.contains(where: { $0.id == shownID }) ? shownID : nil
        let requestedPage = requestedPage
        let next = AppleHeroPageSwap.pageToShow(shown: current, requested: requestedPage.id) { _ in
            readyKeys.contains(requestedPage.key)
        }
        if next != shownID {
            appleTrace("hero page \(next) (requested \(requestedPage.id), ready=\(readyKeys.contains(requestedPage.key)))")
        }
        shownID = next
        if next == requestedPage.id, readyKeys.contains(requestedPage.key) {
            onPresent(shownIndex)
        }
    }
}

/// Fetches one page's backdrop and wordmark exactly as the billboard will,
/// and reports once both have settled.
private struct AppleHeroPagePreload: View {
    let page: AppleHeroPageArt
    let backdropSize: CGSize
    let wordmarkSize: CGSize
    let onReady: (_ wordmarkFailed: Bool) -> Void

    @State private var backdropSettled = false
    @State private var wordmarkResult: Bool?
    @State private var reported = false

    var body: some View {
        ZStack {
            AppleCatalogArtwork(
                url: page.backdrop,
                onFailure: { backdropSettled = true; reportIfSettled() },
                onLoad: { backdropSettled = true; reportIfSettled() }
            )
            .frame(width: backdropSize.width, height: backdropSize.height)
            if let wordmark = page.wordmark {
                AppleTrimmedTitleLogo(url: wordmark, alignment: .leading) { loaded in
                    wordmarkResult = loaded
                    reportIfSettled()
                }
                .frame(width: wordmarkSize.width, height: wordmarkSize.height)
            }
        }
        .task {
            try? await Task.sleep(for: AppleHeroPageSwap.artTimeout)
            guard !Task.isCancelled, !reported else { return }
            appleTrace("hero page art timed out: \(page.id)")
            reported = true
            onReady(AppleHeroPageSwap.wordmarkFailedAtTimeout(hasWordmark: page.wordmark != nil, result: wordmarkResult))
        }
    }

    private func reportIfSettled() {
        guard !reported, backdropSettled, page.wordmark == nil || wordmarkResult != nil else { return }
        reported = true
        onReady(wordmarkResult == false)
    }
}
