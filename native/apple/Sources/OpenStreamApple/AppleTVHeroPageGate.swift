#if os(tvOS)
import SwiftUI

/// The art one billboard page draws: what `AppleTVBillboard` will ask the
/// image caches for when that page is shown.
struct AppleTVHeroPageArt: Equatable {
    let id: String
    let backdrop: URL?
    /// Only when the page will draw it (`AppleTVBillboardTitleTreatment`).
    let wordmark: URL?

    /// Changes when the page's art is upgraded, so upgraded art is warmed again.
    var key: String { "\(id)|\(backdrop?.absoluteString ?? "")|\(wordmark?.absoluteString ?? "")" }
}

/// Holds the billboard on the page it is showing until the page the clock
/// asks for has decoded its backdrop and wordmark, then hands over the new
/// index so art, wordmark and copy change on the same frame. The rotation
/// clock itself is untouched; the next page is fetched a tick ahead, so the
/// change normally lands on time. See `AppleHeroPageSwap`.
struct AppleTVHeroPageGate<Content: View>: View {
    let pages: [AppleTVHeroPageArt]
    let requested: Int
    /// The page index to draw, and whether its wordmark failed to load (the
    /// billboard then falls back to the text title).
    @ViewBuilder let content: (_ index: Int, _ wordmarkFailed: Bool) -> Content

    @State private var shownID: String?
    @State private var readyKeys: Set<String> = []
    @State private var failedWordmarkKeys: Set<String> = []

    var body: some View {
        let index = shownIndex
        content(index, failedWordmarkKeys.contains(pages[index].key))
            .background {
                // Invisible, non-focusable copies at the billboard's own sizes,
                // so the swap finds both caches warm.
                ZStack {
                    ForEach(pagesToWarm, id: \.key) { page in
                        AppleTVHeroPagePreload(page: page) { wordmarkFailed in
                            if wordmarkFailed { failedWordmarkKeys.insert(page.key) }
                            readyKeys.insert(page.key)
                        }
                    }
                }
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: requestedPage, initial: true) { advance() }
            .onChange(of: readyKeys) { advance() }
    }

    private var requestedPage: AppleTVHeroPageArt { pages[requested] }

    private var shownIndex: Int {
        guard let shownID, let index = pages.firstIndex(where: { $0.id == shownID }) else { return requested }
        return index
    }

    private var pagesToWarm: [AppleTVHeroPageArt] {
        AppleHeroPageSwap.pagesToWarm(requested: requested, count: pages.count)
            .map { pages[$0] }
            .filter { $0.id != shownID && !readyKeys.contains($0.key) }
    }

    private func advance() {
        let current = pages.contains(where: { $0.id == shownID }) ? shownID : nil
        let requestedPage = requestedPage
        shownID = AppleHeroPageSwap.pageToShow(shown: current, requested: requestedPage.id) { _ in
            readyKeys.contains(requestedPage.key)
        }
    }
}

/// Fetches one page's backdrop and wordmark exactly as the billboard will,
/// and reports once both have settled.
private struct AppleTVHeroPagePreload: View {
    let page: AppleTVHeroPageArt
    let onReady: (_ wordmarkFailed: Bool) -> Void

    @State private var backdropSettled = false
    @State private var wordmarkResult: Bool?

    private typealias M = AppleTVBillboardMetrics

    var body: some View {
        ZStack {
            AppleCatalogArtwork(
                url: page.backdrop,
                onFailure: { backdropSettled = true; reportIfSettled() },
                onLoad: { backdropSettled = true; reportIfSettled() }
            )
            .frame(width: M.screenSize.width, height: M.artHeight)
            if let wordmark = page.wordmark {
                AppleTrimmedTitleLogo(url: wordmark, alignment: .leading) { loaded in
                    wordmarkResult = loaded
                    reportIfSettled()
                }
                .frame(width: M.copyColumnWidth * 0.62, height: M.titleFontSize * 2.2)
            }
        }
    }

    private func reportIfSettled() {
        guard backdropSettled, page.wordmark == nil || wordmarkResult != nil else { return }
        onReady(wordmarkResult == false)
    }
}
#endif
