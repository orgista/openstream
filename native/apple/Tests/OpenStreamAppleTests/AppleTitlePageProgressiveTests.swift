import Foundation
import CoreGraphics
import Testing
@testable import OpenStreamApple

#if OPENSTREAM_ADDONS
@Suite("Progressive title metadata", .timeLimit(.minutes(1)))
struct AppleTitlePageProgressiveTests {
    private func source(_ host: String) -> AppleSource {
        AppleSource(kind: .stremio, name: host,
            url: URL(string: "https://fixture.example/\(host)/manifest.json")!, manifestID: host, resources: ["meta"])
    }

    private func response(_ request: URLRequest, _ json: String) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    @Test func firstAnswerPublishesBeforePreferredProviderAndLateMergePreservesPriority() async throws {
        let preferred = source("preferred.fixture.example")
        let other = source("other.fixture.example")
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let updates = DetailUpdates()
        let client = AppleStremioMetadataClient(loader: { request in
            if request.url?.path.hasPrefix("/preferred.fixture.example/") == true {
                for await _ in gate.stream { break }
                try Task.checkCancellation()
                return response(request, #"{"meta":{"id":"fixture:film","type":"movie","name":"Preferred"}}"#)
            }
            return response(request, #"{"meta":{"id":"fixture:film","type":"movie","name":"First","description":"Early synopsis"}}"#)
        })
        let resolver = AppleMetadataResolver(sourceClient: client, requestDeadline: .seconds(20), overallDeadline: .seconds(20))
        let final = try await resolver.resolve(sources: [preferred, other], preferredSourceID: preferred.id,
            type: "movie", mediaID: "fixture:film", onUpdate: { value in
                await updates.append(value)
                if value.title == "First" { gate.continuation.yield(()) }
            })
        let values = await updates.values
        #expect(values.first?.title == "First")
        #expect(values.last?.title == "Preferred")
        #expect(values.last?.overview == "Early synopsis")
        #expect(final?.title == "Preferred")
        #expect(final?.overview == "Early synopsis")
    }

    @Test func identityFallbackRunsAtMostThreeSourcesTogetherAndPreservesPriority() async throws {
        let sources = (0..<6).map { source("source\($0).fixture.example") }
        let arrivals = IdentityArrivals()
        let client = AppleStremioMetadataClient(loader: { request in
            let component = request.url!.pathComponents[1]
            let index = Int(component.dropFirst(6).prefix(1))!
            await arrivals.begin()
            if index < 3 {
                try await Task.sleep(for: .milliseconds(20))
                await arrivals.end()
                return response(request, #"{"meta":{"id":"unmapped"}}"#)
            }
            await arrivals.end()
            return response(request, "{\"meta\":{\"imdb_id\":\"tt000000\(index)\"}}")
        })
        let id = await client.imdbIdentifier(sources: sources, preferredSourceID: sources[0].id,
            type: "movie", id: "fixture:film")
        #expect(id == "tt0000003")
        #expect(await arrivals.maximum <= 3)
    }

    @Test func duplicateIdentityLookupsShareWorkAndOneCancelledWaiterLeavesIndependently() async throws {
        let preferred = source("identity.fixture.example")
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let arrivals = IdentityArrivals()
        let client = AppleStremioMetadataClient(loader: { request in
            await arrivals.begin()
            for await _ in gate.stream { break }
            try Task.checkCancellation()
            return response(request, #"{"meta":{"imdb_id":"tt1234567"}}"#)
        })
        let first = Task { await client.imdbIdentifier(sources: [preferred], type: "movie", id: "fixture:film") }
        while await arrivals.calls == 0 { try Task.checkCancellation(); await Task.yield() }
        let second = Task { await client.imdbIdentifier(sources: [preferred], type: "movie", id: "fixture:film") }
        while await client.identityLookupWaiterCount < 2 { try Task.checkCancellation(); await Task.yield() }
        first.cancel()
        #expect(await first.value == nil)
        #expect(await arrivals.calls == 1)
        gate.continuation.yield(())
        #expect(await second.value == "tt1234567")
        #expect(await arrivals.calls == 1)
    }

    @Test func slowPreferredIdentityIsCancelledAndBoundedFallbackStillAnswers() async {
        let preferred = source("slow.fixture.example")
        let other = source("fast.fixture.example")
        let arrivals = IdentityArrivals()
        let client = AppleStremioMetadataClient(loader: { request in
            if request.url?.path.hasPrefix("/slow.fixture.example/") == true {
                do { try await Task.sleep(for: .seconds(20)) }
                catch {
                    await arrivals.recordCancellation()
                    throw error
                }
            }
            return response(request, #"{"meta":{"imdb_id":"tt1234567"}}"#)
        })
        let id = await client.imdbIdentifier(sources: [preferred, other], preferredSourceID: preferred.id,
            type: "movie", id: "fixture:film")
        #expect(id == "tt1234567")
        #expect(await arrivals.cancellations == 1)
    }

    @Test func cancelledResolutionDoesNotPublishLateAnswers() async throws {
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let arrivals = IdentityArrivals()
        let updates = DetailUpdates()
        let client = AppleStremioMetadataClient(loader: { request in
            await arrivals.begin()
            for await _ in gate.stream { break }
            try Task.checkCancellation()
            return response(request, #"{"meta":{"id":"fixture:film","type":"movie","name":"Late"}}"#)
        })
        // Only the cancellation may end the lookup, never its request deadline.
        let resolver = AppleMetadataResolver(sourceClient: client, clock: ManualClock())
        let task = Task {
            try await resolver.resolve(sources: [source("cancel.fixture.example")], type: "movie", mediaID: "fixture:film",
                onUpdate: { value in await updates.append(value) })
        }
        while await arrivals.calls == 0 { try Task.checkCancellation(); await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await updates.values.isEmpty)
    }
}

private actor DetailUpdates {
    var values: [AppleTMDBDetails] = []
    func append(_ value: AppleTMDBDetails) { values.append(value) }
}

private actor IdentityArrivals {
    var calls = 0
    var active = 0
    var maximum = 0
    var cancellations = 0
    func recordCancellation() { cancellations += 1 }
    func begin() { calls += 1; active += 1; maximum = max(maximum, active) }
    func end() { active -= 1 }
}

#endif

@Suite("Cached title header artwork")
struct AppleCachedTitleHeaderTests {
    private func image(_ dimension: Int) -> CGImage {
        CGContext(data: nil, width: dimension, height: dimension, bitsPerComponent: 8,
            bytesPerRow: dimension * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    @Test func shelfBitmapIsAvailableForTheFirstHeaderFrameAtAnotherDecodeSize() async throws {
        let calls = HeaderCacheCalls()
        let cache = AppleRemoteImageCache(loader: { _, dimension in
            await calls.record()
            return image(dimension)
        })
        let url = URL(string: "https://fixture.example/art/poster.jpg")!
        let shelf = try await cache.image(url: url, maximumPixelDimension: 320)
        #expect(cache.cachedImage(url: url, maximumPixelDimension: 1_280) == nil)
        let placeholder = try #require(cache.cachedPlaceholderImage(url: url))
        #expect(placeholder === shelf)
        #expect(await calls.count == 1)
        let header = try await cache.image(url: url, maximumPixelDimension: 1_280)
        #expect(cache.cachedPlaceholderImage(url: url) === header)
        #expect(await calls.count == 2)
        cache.removeAllCached()
        #expect(cache.cachedPlaceholderImage(url: url) == nil)
    }

    @Test func cachedPosterShowsWhileBetterBackdropIsUncachedThenBackdropWins() async throws {
        let calls = HeaderCacheCalls()
        let cache = AppleRemoteImageCache(loader: { _, dimension in
            await calls.record()
            return image(dimension)
        })
        let poster = URL(string: "https://fixture.example/art/poster.jpg")!
        let backdrop = URL(string: "https://fixture.example/art/backdrop.jpg")!
        let decodedPoster = try await cache.image(url: poster, maximumPixelDimension: 320)
        let first = try #require(AppleTitlePageSlotArt.chooseCached(backdrops: [backdrop], posters: [poster],
            cachedImage: { cache.cachedPlaceholderImage(url: $0) }))
        #expect(first.art == .posterCard(poster))
        #expect(first.image === decodedPoster)
        #expect(await calls.count == 1)
        let decodedBackdrop = try await cache.image(url: backdrop, maximumPixelDimension: 640)
        let later = try #require(AppleTitlePageSlotArt.chooseCached(backdrops: [backdrop], posters: [poster],
            cachedImage: { cache.cachedPlaceholderImage(url: $0) }))
        #expect(later.art == .backdrop(backdrop))
        #expect(later.image === decodedBackdrop)
        #expect(await calls.count == 2)
    }
}

private actor HeaderCacheCalls {
    var count = 0
    func record() { count += 1 }
}
