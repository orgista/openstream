import Foundation
import Testing
@testable import OpenStreamApple

/// The title page fill (speed item D2): the per-opening timeline, the episode
/// lookup that no longer waits on add-ons one after another, and which titles
/// a focused poster may warm.
@Suite("Detail fill timeline")
@MainActor
struct AppleDetailFillTimelineTests {
    /// A clock the test moves by hand.
    private final class ManualClock {
        let base = ContinuousClock.now
        var offset: Duration = .zero
        var now: ContinuousClock.Instant { base.advanced(by: offset) }
    }

    @Test func milestonesAreMeasuredFromTheOpeningAndRecordedOnce() {
        let clock = ManualClock()
        let timeline = AppleDetailFillTimeline(now: { clock.now })
        timeline.begin(title: "Breaking Bad")
        #expect(timeline.mark(.paint) == "detail fill \"Breaking Bad\" paint +0ms")
        clock.offset = .milliseconds(664)
        #expect(timeline.mark(.episodes, detail: "80") == "detail fill \"Breaking Bad\" episodes +664ms 80")
        clock.offset = .milliseconds(900)
        #expect(timeline.mark(.episodes) == nil)
    }

    @Test func nothingIsRecordedBeforeTheFirstOpening() {
        let timeline = AppleDetailFillTimeline()
        #expect(timeline.mark(.overview) == nil)
    }

    @Test func aNewOpeningStartsAFreshTimeline() {
        let clock = ManualClock()
        let timeline = AppleDetailFillTimeline(now: { clock.now })
        timeline.begin(title: "One")
        timeline.mark(.metadata)
        clock.offset = .seconds(30)
        timeline.begin(title: "Two")
        clock.offset = .seconds(30) + .milliseconds(250)
        #expect(timeline.mark(.metadata) == "detail fill \"Two\" metadata +250ms")
    }

    @Test func subMillisecondTimesRoundToTheNearestMillisecond() {
        #expect(AppleDetailFillTimeline.line(title: "T", milestone: .done, elapsed: .microseconds(1_600))
            == "detail fill \"T\" done +2ms")
    }
}

@Suite("Parallel episode lookup")
struct AppleParallelEpisodeLookupTests {
    private func source(_ host: String, manifestID: String? = nil) -> AppleSource {
        AppleSource(
            kind: .stremio,
            name: host,
            url: URL(string: "https://\(host)/manifest.json")!,
            manifestID: manifestID,
            resources: ["meta"]
        )
    }

    private func response(_ request: URLRequest, _ videos: String) -> (Data, URLResponse) {
        (
            Data("{\"meta\":{\"videos\":[\(videos)]}}".utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    /// A slow add-on listed first used to hold the list back for its whole
    /// timeout. Now the fast answer is used once the grace runs out.
    @Test func aSlowAddOnDoesNotHoldBackAFastOne() async throws {
        let slow = source("slow.fixture", manifestID: "com.linvo.cinemeta")
        let fast = source("fast.fixture")
        let client = AppleStremioMetadataClient(
            loader: { request in
                if request.url?.host == "slow.fixture" {
                    try await Task.sleep(for: .seconds(10))
                }
                return response(request, #"{"id":"tt1234567:1:1","title":"Pilot","season":1,"episode":1}"#)
            },
            metadataCache: nil,
            mergeGrace: .milliseconds(100)
        )

        let clock = ContinuousClock()
        let start = clock.now
        let episodes = try await client.episodes(
            sources: [slow, fast],
            preferredSourceID: slow.id,
            mediaID: "tt1234567"
        )

        #expect(episodes.map(\.id) == ["tt1234567:1:1"])
        #expect(start.duration(to: clock.now) < .seconds(3))
    }

    /// Both answer within the grace: the preferred add-on still wins a
    /// duplicate, exactly as the one-at-a-time walk did.
    @Test func answersAreMergedInCandidateOrder() async throws {
        let preferred = source("preferred.fixture", manifestID: "com.linvo.cinemeta")
        let other = source("other.fixture")
        let client = AppleStremioMetadataClient(
            loader: { request in
                if request.url?.host == "preferred.fixture" {
                    // Answers second, but is first in line.
                    try await Task.sleep(for: .milliseconds(50))
                    return response(request, #"{"id":"tt1234567:1:1","title":"Preferred","season":1,"episode":1}"#)
                }
                return response(request, #"""
                    {"id":"tt1234567:1:1","title":"Other","season":1,"episode":1},
                    {"id":"tt1234567:1:2","title":"Second","season":1,"episode":2}
                    """#)
            },
            metadataCache: nil,
            mergeGrace: .seconds(5)
        )

        let episodes = try await client.episodes(
            sources: [other, preferred],
            preferredSourceID: preferred.id,
            mediaID: "tt1234567"
        )

        #expect(episodes.map(\.title) == ["Preferred", "Second"])
    }

    @Test func everyAddOnFailingIsStillAnError() async {
        let client = AppleStremioMetadataClient(
            loader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
            },
            metadataCache: nil
        )
        await #expect(throws: (any Error).self) {
            try await client.episodes(
                sources: [source("a.fixture", manifestID: "com.linvo.cinemeta"), source("b.fixture")],
                mediaID: "tt1234567"
            )
        }
    }
}

@Suite("Parallel metadata resolution")
struct AppleParallelMetadataResolutionTests {
    private func source(_ host: String, manifestID: String) -> AppleSource {
        AppleSource(
            kind: .stremio,
            name: host,
            url: URL(string: "https://\(host)/manifest.json")!,
            manifestID: manifestID,
            resources: ["meta"]
        )
    }

    /// The preferred add-on answers last but still wins every field it has;
    /// the others only fill the gaps, as in the one-at-a-time walk.
    @Test func thePreferredAddOnWinsEvenWhenItAnswersLast() async throws {
        let preferred = source("preferred.fixture", manifestID: "com.preferred")
        let other = source("other.fixture", manifestID: "com.other")
        let client = AppleStremioMetadataClient { request in
            let body: String
            if request.url?.host == "preferred.fixture" {
                try await Task.sleep(for: .milliseconds(80))
                body = #"{"meta":{"id":"tt1234567","type":"movie","name":"Preferred"}}"#
            } else {
                body = #"{"meta":{"id":"tt1234567","type":"movie","name":"Other","description":"Other overview"}}"#
            }
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        let resolver = AppleMetadataResolver(
            sourceClient: client,
            requestDeadline: .seconds(2),
            overallDeadline: .seconds(3),
            defaultSource: source("default.fixture", manifestID: "com.linvo.cinemeta")
        )

        let details = try await resolver.resolve(
            sources: [other, preferred],
            preferredSourceID: preferred.id,
            type: "movie",
            mediaID: "tt1234567"
        )

        #expect(details?.title == "Preferred")
        #expect(details?.overview == "Other overview")
    }

    /// Three add-ons that each time out used to cost three deadlines in a
    /// row; together they cost one.
    @Test func slowAddOnsCostOneDeadlineNotOneEach() async throws {
        let client = AppleStremioMetadataClient { request in
            if request.url?.host != "default.fixture" {
                try await Task.sleep(for: .seconds(10))
            }
            let body = #"{"meta":{"id":"tt1234567","type":"movie","name":"Default"}}"#
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        let resolver = AppleMetadataResolver(
            sourceClient: client,
            requestDeadline: .milliseconds(300),
            overallDeadline: .seconds(3),
            defaultSource: source("default.fixture", manifestID: "com.linvo.cinemeta")
        )

        let clock = ContinuousClock()
        let start = clock.now
        let details = try await resolver.resolve(
            sources: [source("a.fixture", manifestID: "a"), source("b.fixture", manifestID: "b"),
                      source("c.fixture", manifestID: "c")],
            type: "movie",
            mediaID: "tt1234567"
        )

        #expect(details?.title == "Default")
        #expect(start.duration(to: clock.now) < .milliseconds(850))
    }
}

@Suite("Focus prefetch target")
struct AppleFocusPrefetchTargetTests {
    @Test func aCanonicalMovieOrSeriesIsWarmed() {
        #expect(AppleMetadataPrefetcher.detailTarget(type: "Series", mediaID: "tt0903747")
            == .init(type: "series", mediaID: "tt0903747"))
        #expect(AppleMetadataPrefetcher.detailTarget(type: "movie", mediaID: " tt6751668 ")?.mediaID == "tt6751668")
    }

    /// A catalog-specific id would need a lookup the page does not cache, and
    /// a channel or video has no title page to warm.
    @Test func otherIdsAndKindsAreLeftAlone() {
        #expect(AppleMetadataPrefetcher.detailTarget(type: "series", mediaID: "tmdb:203769") == nil)
        #expect(AppleMetadataPrefetcher.detailTarget(type: "tv", mediaID: "tt0903747") == nil)
    }
}

@Suite("Downloaded episode lookup")
struct AppleDownloadedEpisodeLookupTests {
    /// One manifest read answers for every episode: only ids with a record
    /// whose file is still on disk count as downloaded.
    @Test func onlyRecordsWithAFileOnDiskCount() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "fill-lookup-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appending(path: "library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let present = library.appending(path: "present.mp4")
        try Data([0]).write(to: present)
        let manifest = [
            "tt1:1:1": AppleOfflineRecord(mediaID: "tt1:1:1", localURL: present, sourceExtension: "mp4"),
            "tt1:1:2": AppleOfflineRecord(
                mediaID: "tt1:1:2", localURL: library.appending(path: "gone.mp4"), sourceExtension: "mp4"),
        ]
        try JSONEncoder().encode(manifest).write(to: library.appending(path: "manifest.json"))
        let store = AppleOfflineMediaStore(rootDirectory: library, allowedDirectories: [root])

        let downloaded = await store.downloadedMediaIDs(among: ["tt1:1:1", "tt1:1:2", "tt1:1:3"])

        #expect(downloaded == ["tt1:1:1"])
    }
}
