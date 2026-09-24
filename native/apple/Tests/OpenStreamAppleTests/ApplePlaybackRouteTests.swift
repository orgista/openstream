import Foundation
import Testing
@testable import OpenStreamApple

struct ApplePlaybackRouteTests {
    private let movie = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Fixture")
    private let series = AppleCatalogItem(mediaID: "tt1234567", type: "series", name: "Fixture")

    private func source(_ kind: AppleSourceKind = .stremio, resources: [String] = [], enabled: Bool = true) -> AppleSource {
        var value = AppleSource(kind: kind, name: "Fixture", url: URL(string: "https://fixture.example/manifest.json")!, resources: resources)
        value.isEnabled = enabled
        return value
    }

    @Test(arguments: [["stream"], ["STREAM"], ["catalog", "Stream", "meta"]])
    func streamingAddOnIsPlayable(resources: [String]) {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: movie, sources: [source(resources: resources)]))
    }

    @Test func metadataOnlyAddOnOffersTrailer() {
        let playable = AppleTitlePagePolicy.hasPlaybackRoute(item: movie, sources: [source(resources: ["catalog", "meta"])])
        #expect(playable == false)
        #expect(AppleTitlePagePolicy.primaryAction(type: movie.type, progress: nil, selectedEpisode: nil,
                                                 isPlayable: playable, hasTrailer: true) == .playTrailer)
    }

    @Test func disabledStreamingSourceIsNotPlayable() {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: movie, sources: [source(resources: ["stream"], enabled: false)]) == false)
    }

    @Test func nonStremioSourceIsPlayable() {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: movie, sources: [source(.library)]))
    }

    @Test func mediaServerItemNeedsNoAddOn() {
        let item = AppleCatalogItem(mediaID: "ms:00000000-0000-0000-0000-000000000001:fixture", type: "series", name: "Fixture")
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: item, sources: [], episodesUnavailable: true))
    }

    @Test func finishedDownloadWorksWithoutSourcesOrEpisodes() {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: series, sources: [], hasCompletedDownload: true, episodesUnavailable: true))
    }

    @Test func localGroupWorksWithoutSourcesOrEpisodes() {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: series, sources: [], hasLocalGroup: true, episodesUnavailable: true))
    }

    @Test func seriesWithoutEpisodesCannotStream() {
        #expect(AppleTitlePagePolicy.hasPlaybackRoute(item: series, sources: [source(resources: ["stream"])], episodesUnavailable: true) == false)
    }

    @Test func heroResumesExactSavedEpisode() throws {
        let first = AppleStremioEpisode(id: "tt1234567:1:1", title: "First", season: 1, episode: 1, releaseInfo: nil)
        let saved = AppleStremioEpisode(id: "tt1234567:2:3", title: "Saved", season: 2, episode: 3, releaseInfo: nil)
        let progress = ApplePlaybackProgress(position: 742, duration: 3_000, partID: saved.id)
        let selected = try #require(AppleTitlePagePolicy.heroEpisode(item: series, progress: progress, episodes: [first, saved]))
        #expect(selected.id == saved.id)
        #expect(progress.resumePosition == 742)
        #expect(AppleTitlePagePolicy.primaryAction(type: "series", progress: progress, selectedEpisode: selected,
            isPlayable: AppleTitlePagePolicy.hasPlaybackRoute(item: series, sources: [source(resources: ["stream"])]),
            hasTrailer: true) == .resume(episode: "S2, E3"))
    }

    @Test func mediaServerHeroRetainsResumeWithOpaqueEpisodeID() throws {
        let item = AppleCatalogItem(mediaID: "ms:00000000-0000-0000-0000-000000000001:fixture", type: "series", name: "Fixture")
        let progress = ApplePlaybackProgress(position: 742, duration: 3_000, partID: "server-episode")
        let selected = try #require(AppleTitlePagePolicy.heroEpisode(item: item, progress: progress, episodes: []))
        #expect(selected.id == progress.partID)
        #expect(AppleTitlePagePolicy.primaryAction(type: item.type, progress: progress, selectedEpisode: selected,
            isPlayable: AppleTitlePagePolicy.hasPlaybackRoute(item: item, sources: [], episodesUnavailable: true),
            hasTrailer: true) == .resume(episode: nil))
    }


    @Test func downloadedPlayLabelAgreesOnHeroAndTitlePage() {
        #expect(AppleTitlePagePolicy.PrimaryAction.play.displayTitle(hasCompletedDownload: true) == "Play Offline")
        #expect(AppleTitlePagePolicy.PrimaryAction.play.displayTitle(hasCompletedDownload: false) == "Play")
        #expect(AppleTitlePagePolicy.PrimaryAction.resume(episode: "S2, E3").displayTitle(hasCompletedDownload: true) == "Resume S2, E3")
    }


    @Test func heroChoosesSameNextUnwatchedEpisodeAsTitlePage() {
        let first = AppleStremioEpisode(id: "tt1234567:1:1", title: "First", season: 1, episode: 1, releaseInfo: nil)
        let next = AppleStremioEpisode(id: "tt1234567:1:2", title: "Next", season: 1, episode: 2, releaseInfo: nil)
        #expect(AppleTitlePagePolicy.heroEpisode(item: series, progress: nil, episodes: [first, next],
                                               completedIDs: [first.id]) == next)
        #expect(AppleTitlePagePolicy.heroEpisode(item: series, progress: nil, episodes: [first, next],
                                               localResumeEpisode: next) == next)
    }

}
