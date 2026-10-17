import Foundation
import Testing
@testable import OpenStreamApple

@Suite("Metadata matching fixes", .serialized)
struct AppleMetadataMatchFixTests {
    private func file(_ path: String) -> AppleLibraryItem {
        .init(sourceID: UUID(), name: (path as NSString).lastPathComponent,
              url: URL(string: "https://fixture.example/movie")!, relativePath: path, sizeBytes: 1)
    }

    @Test(arguments: [
        ("ISO-STAGE-93-John-Wick-Chapter-4-2023-UHD.iso", "John Wick Chapter 4", 2023),
        ("ISO-STAGE-434-The-Goonies-1985-UHD.iso", "The Goonies", 1985),
        ("ISO-STAGE-215-The-Wild-Robot-2024-UHD.iso", "The Wild Robot", 2024),
        ("sharphd-avatar.2009.ext-uhd.iso", "avatar", 2009),
        ("ISO-STAGE-237-TRON-Legacy-2010-UHD.iso", "TRON Legacy", 2010),
        ("A.Marvel.Television.Special.Presentation.--.The.Punisher.One.Last.Kill.2026.2160p.DSNP.WEB-DL.DDP5.1.Atmos.DV.HDR10Plus.H.265-Kitsune.mkv", "The Punisher One Last Kill", 2026)
    ])
    func observedMisses(_ value: (String, String, Int)) {
        let parsed = AppleLibraryTitleParser.parse(name: value.0)
        let query = AppleLibraryMetadataResolver.searchQueries(parsed).first
        #expect(query?.title == value.1)
        #expect(query?.year == value.2)
    }

    /// The search form is cleaned; the stored identity title is not (D1).
    @Test(arguments: [("1917.mkv", "1917", "1917"), ("2001.A.Space.Odyssey.mkv", "2001 A Space Odyssey", "2001 A Space Odyssey"),
                      ("93-John-Wick.mkv", "93-John-Wick", "93 John Wick"), ("UnknownGroup-Avatar.mkv", "UnknownGroup-Avatar", "UnknownGroup Avatar")])
    func negativeLookalikes(_ value: (String, String, String)) {
        let parsed = AppleLibraryTitleParser.parse(name: value.0)
        #expect(parsed.title == value.1)
        #expect(parsed.kind == .movie)
        #expect(AppleLibraryMetadataResolver.searchQueries(parsed).first?.title == value.2)
    }

    /// Numeric titles still match through search + `bestMatch`, not only the parser.
    @Test(arguments: [("1917.mkv", "1917"), ("2001.A.Space.Odyssey.mkv", "2001: A Space Odyssey")])
    func numericTitlesStillMatchThroughSearch(_ value: (String, String)) async throws {
        let client = AppleTMDBClient { request in
            let path = request.url!.path
            let body = path.hasPrefix("/3/search/")
                ? #"{"results":[{"id":11,"title":"\#(value.1)","release_date":"2019-12-25"},{"id":12,"title":"\#(value.1): The Making Of","release_date":"2020-01-01"},{"id":13,"title":"Numbers","release_date":"2001-01-01"}]}"#
                : #"{"id":11,"title":"\#(value.1)","release_date":"2019-12-25"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let query = try #require(AppleLibraryMetadataResolver.searchQueries(AppleLibraryTitleParser.parse(name: value.0)).first)
        let result = try await client.librarySearch(query, configuration: .init(credential: "fixture"))
        #expect(result?.mediaID == "tmdb:movie:11")
    }

    @Test func folderEvidenceAndAmbiguity() throws {
        let parsed = AppleLibraryTitleParser.parse(name: "Dune.mkv", parentPath: "Movies/Dune (2021)")
        #expect(parsed.year == nil)
        #expect(parsed.alternatives.contains { $0.provenance == .parentFolder && $0.year == 2021 })
        let query = try #require(AppleLibraryMetadataResolver.searchQueries(parsed).first)
        #expect(query.year == 2021)
        let items = [AppleCatalogItem(mediaID: "old", type: "movie", name: "Dune", releaseInfo: "1984"),
                     AppleCatalogItem(mediaID: "new", type: "movie", name: "Dune", releaseInfo: "2021")]
        #expect(AppleLibraryMetadataResolver.bestMatch(items, parsed: query)?.mediaID == "new")
        #expect(AppleLibraryMetadataResolver.bestMatch(items, parsed: AppleLibraryTitleParser.parse(name: "Dune.mkv")) == nil)
        let tied = items.map { AppleCatalogItem(mediaID: $0.mediaID, type: "movie", name: "Dune", releaseInfo: "2021") }
        #expect(AppleLibraryMetadataResolver.bestMatch(tied, parsed: query) == nil)
        #expect(AppleLibraryMetadataResolver.bestMatch([items[1]], parsed: AppleLibraryTitleParser.parse(name: "Dune Messiah.mkv")) == nil)
        #expect(AppleLibraryMetadataResolver.bestMatch([items[1]], parsed: AppleLibraryTitleParser.parse(name: "Dune Messiah.mkv"), aliases: ["new": ["Dune Messiah"]])?.mediaID == "new")
    }

    @Test(arguments: ["00001.m2ts", "Film.S01E01.mkv"])
    func parentSelectedTitleRetainsItsProvenance(_ name: String) {
        let parsed = AppleLibraryTitleParser.parse(name: name, parentPath: "Movies/Film (2024)")
        #expect(parsed.alternatives.first?.provenance == .parentFolder)
        #expect(parsed.alternatives.first?.title == "Film")
    }

    /// D5: short playlist numbers still defer to a title folder; with no
    /// folder a bare number is the title. Five-digit playlists never are.
    @Test func discPlaylistNumbersDeferToTheTitleFolder() {
        for name in ["0001.mkv", "00800.mpls", "01.m2ts"] {
            let parsed = AppleLibraryTitleParser.parse(name: name, parentPath: "Movies/Film (2024)")
            #expect(parsed.title == "Film")
            #expect(parsed.year == 2024)
        }
        #expect(AppleLibraryTitleParser.parse(name: "00800.mpls").kind == .other)
        #expect(AppleLibraryTitleParser.parse(name: "1917.mkv", parentPath: "Movies").title == "1917")
    }

    @Test(arguments: [("imdbid-tt1234567", "imdb", "tt1234567"), ("tmdb-123", "tmdb", "123"), ("tmdbid-123", "tmdb", "123"), ("tvdbid=456", "tvdb", "456")])
    func typedIDs(_ value: (String, String, String)) {
        #expect(AppleLibraryTitleParser.parse(name: "Wrong {\(value.0)}.mkv").explicitIDs[value.1] == value.2)
    }

    @Test(arguments: ["tmdb", "imdb", "tvdb"])
    func directLookupIgnoresMisleadingTitle(_ provider: String) async throws {
        let client = AppleTMDBClient { request in
            let path = request.url!.path
            #expect(!path.contains("search"))
            let body = path.contains("find") ? #"{"movie_results":[{"id":123}],"tv_results":[]}"# : #"{"id":123,"title":"Correct Title","release_date":"2024-01-01","external_ids":{"imdb_id":"tt1234567"}}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        var parsed = AppleLibraryTitleParser.parse(name: "Misleading.1999.mkv")
        parsed.explicitIDs[provider] = provider == "imdb" ? "tt1234567" : "123"
        let result = try await AppleLibraryMetadataResolver.directLookup(parsed, client: client, configuration: .init(credential: "fixture"))
        #expect(result?.name == "Correct Title")
        #expect(result?.mediaID == "tt1234567")
    }

    /// D1: group ids, match records and unresolved `local-…` ids keep the
    /// pre-change identity; only the search query is normalised.
    @MainActor
    @Test(arguments: [("Spider-Man.2002.mkv", "spider-man", 2002, "Spider Man"),
                      ("Blade.Runner.Directors.Cut.1982.mkv", "blade runner directors cut", 1982, "Blade Runner")])
    func manualMatchSavedUnderThePreChangeIDIsHonoured(_ value: (String, String, Int, String)) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = file(value.0)
        let legacyID = "\(item.sourceID):movie:\(value.1):\(value.2)"
        let group = try #require(AppleLibrarySeries.groups([item]).first)
        #expect(group.id == legacyID)
        #expect(AppleLocalLibraryStore().catalogItem(for: group).mediaID == "local-" + ApplePlaybackIdentity.digest(for: legacyID))
        let manual = AppleCatalogItem(mediaID: "tt0145487", type: "movie", name: "Owner Pick")
        let record = AppleLibraryMetadataResolver.MatchRecord(candidate: manual, explicitIDs: [:], provider: "manualSearch",
            confidence: 1, isManual: true, matchedAt: .now)
        let matches = root.appendingPathComponent("Matches")
        try FileManager.default.createDirectory(at: matches, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: matches.appendingPathComponent(ApplePlaybackIdentity.digest(for: legacyID) + ".json"))
        let resolver = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in
            Issue.record("A manual match must not be looked up again")
            return nil
        }
        #expect(try await resolver.resolve(item, sources: [], tmdbKey: "", omdbKey: "") == manual)
        #expect(await resolver.cachedLookups(for: [group]).metadata[legacyID] == manual)
        #expect(AppleLibraryMetadataResolver.searchQueries(AppleLibraryTitleParser.parse(item)).first?.title == value.3)
    }

    /// D3: a dated title searches with TMDB's year filter, then once without.
    @Test func tmdbSearchSendsTheYearAndRetriesWithoutIt() async throws {
        let log = RequestLog()
        let client = AppleTMDBClient { request in
            await log.append(request.url!)
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let year = query.first { $0.name == "year" }?.value
            let body: String
            if request.url!.path.hasPrefix("/3/search/") {
                switch year {
                case "2015": body = #"{"results":[{"id":7,"title":"Home","release_date":"2015-03-20"}]}"#
                case "2014": body = #"{"results":[]}"#
                default: body = #"{"results":[{"id":5,"title":"Home","release_date":"2016-01-01"},{"id":6,"title":"Home","release_date":"2014-01-01"},{"id":7,"title":"Home","release_date":"2015-03-20"}]}"#
                }
            } else {
                body = #"{"id":\#(request.url!.lastPathComponent),"title":"Home","release_date":"2015-03-20"}"#
            }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let dated = try #require(AppleLibraryMetadataResolver.searchQueries(AppleLibraryTitleParser.parse(name: "Home.2015.mkv")).first)
        #expect(try await client.librarySearch(dated, configuration: .init(credential: "fixture"))?.mediaID == "tmdb:movie:7")
        let first = try #require(await log.urls.first)
        #expect(URLComponents(url: first, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "year" && $0.value == "2015" } == true)
        // Off by one: the filtered page is empty, the unfiltered retry decides.
        let offByOne = try #require(AppleLibraryMetadataResolver.searchQueries(AppleLibraryTitleParser.parse(name: "Home.2014.mkv")).first)
        #expect(try await client.librarySearch(offByOne, configuration: .init(credential: "fixture"))?.mediaID == "tmdb:movie:6")
        // Without the filter the same three-way name is ambiguous for 2015 → no guess.
        let unfiltered = AppleTMDBClient { request in
            let body = request.url!.path.hasPrefix("/3/search/")
                ? #"{"results":[{"id":5,"title":"Home","release_date":"2016-01-01"},{"id":6,"title":"Home","release_date":"2014-01-01"}]}"#
                : "{}"
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(try await unfiltered.librarySearch(dated, configuration: .init(credential: "fixture")) == nil)
    }

    /// D4: the Fix Match field accepts a name, a TMDB number or page link, an IMDb id or link, and a TVDB tag.
    @Test(arguments: [("603", "tmdb", "603"), ("https://www.themoviedb.org/movie/603-the-matrix", "tmdb", "603"),
                      ("tt0133093", "imdb", "tt0133093"), ("https://www.imdb.com/title/tt0133093/", "imdb", "tt0133093"),
                      ("tvdb-81189", "tvdb", "81189"), ("tvdbid=81189", "tvdb", "81189"), ("tmdb-603", "tmdb", "603")])
    func fixMatchAcceptsPastedIDs(_ value: (String, String, String)) {
        let title = AppleLibraryMetadataResolver.correctionTitle(query: value.0, year: nil, kind: .movie)
        #expect(title.explicitIDs[value.1] == value.2)
    }

    @Test func fixMatchNameSearchKeepsTheYear() {
        let title = AppleLibraryMetadataResolver.correctionTitle(query: "The Matrix", year: 1999, kind: .movie)
        #expect(title.title == "The Matrix")
        #expect(title.year == 1999)
        #expect(title.explicitIDs.isEmpty)
    }

    /// Fixture TMDB answers: `/movie/<id>` is "Unrelated Film", `/search/movie` finds "1917" (2019).
    private func digitQueryStubs() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let tmdb = root.appendingPathComponent("api.themoviedb.org/3")
        try FileManager.default.createDirectory(at: tmdb.appendingPathComponent("movie"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmdb.appendingPathComponent("search"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmdb.appendingPathComponent("find"), withIntermediateDirectories: true)
        for id in ["1917", "603"] {
            try Data(#"{"id":\#(id),"title":"Unrelated Film","release_date":"1990-01-01"}"#.utf8)
                .write(to: tmdb.appendingPathComponent("movie/\(id).json"))
        }
        try Data(#"{"id":278,"title":"The Shawshank Redemption","release_date":"1994-09-23","external_ids":{"imdb_id":"tt0111161"}}"#.utf8)
            .write(to: tmdb.appendingPathComponent("movie/278.json"))
        try Data(#"{"movie_results":[{"id":278}],"tv_results":[]}"#.utf8)
            .write(to: tmdb.appendingPathComponent("find/tt0111161.json"))
        try Data(#"{"results":[{"id":530915,"title":"1917","release_date":"2019-12-25"}]}"#.utf8)
            .write(to: tmdb.appendingPathComponent("search/movie.json"))
        return root
    }

    /// An all-digit Fix Match query is a TMDB id and also a name: "1917" finds the 2019 film.
    @Test func fixMatchDigitQueryAlsoSearchesTheName() async throws {
        let root = try digitQueryStubs()
        defer { try? FileManager.default.removeItem(at: root) }
        let results = try await AppleNetworkStub.$testRoot.withValue(root) {
            try await AppleLibraryMetadataResolver.correctionCandidates(query: "1917", year: nil,
                kind: .movie, sources: [], tmdbKey: "fixture", omdbKey: "")
        }
        #expect(results.contains { $0.name == "Unrelated Film" })
        #expect(results.contains { $0.name == "1917" && $0.releaseInfo?.hasPrefix("2019") == true })
        #expect(results.first?.name == "1917", "a year-like query lists the name match first")
    }

    /// Typed ids stay on the id path: no name search runs (the search fixture would add "1917").
    @Test(arguments: [("tt0111161", "The Shawshank Redemption"), ("tmdb-603", "Unrelated Film")])
    func fixMatchTypedIDSkipsTheNameSearch(_ value: (String, String)) async throws {
        let root = try digitQueryStubs()
        defer { try? FileManager.default.removeItem(at: root) }
        let results = try await AppleNetworkStub.$testRoot.withValue(root) {
            try await AppleLibraryMetadataResolver.correctionCandidates(query: value.0, year: nil,
                kind: .movie, sources: [], tmdbKey: "fixture", omdbKey: "")
        }
        #expect(results.map(\.name) == [value.1])
    }

    /// D7: OMDb's quota answer is an unavailable provider (backoff), not "no such film".
    @Test(arguments: [("Request limit reached!", true), ("Movie not found!", false)])
    func omdbQuotaIsProviderUnreachable(_ value: (String, Bool)) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("www.omdbapi.com")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"Response":"False","Error":"\#(value.0)"}"#.utf8).write(to: directory.appendingPathComponent("index.json"))
        let parsed = AppleLibraryTitleParser.parse(name: "Fixture.Film.2024.mkv")
        let outcome: Result<AppleCatalogItem?, Error> = await AppleNetworkStub.$testRoot.withValue(root) {
            do { return .success(try await AppleLibraryMetadataResolver.credentialLookup(parsed, key: "fixture", tmdb: false)) }
            catch { return .failure(error) }
        }
        switch outcome {
        case .success(let item):
            #expect(!value.1)
            #expect(item == nil)
        case .failure(let error):
            #expect(value.1)
            #expect(error as? AppleTMDBError == .requestFailed(429))
            #expect(AppleLibraryMetadataResolver.missReason(error) == .providerUnreachable)
        }
    }

    @Test func folderFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = AppleLibraryMetadataResolver(directory: root) { title, _, _, _ in
            title.title == "Correct Title" ? AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: title.title) : nil
        }
        #expect(try await resolver.resolve(file("Movies/Correct Title (2024)/Misleading.mkv"), sources: [], tmdbKey: "", omdbKey: "")?.name == "Correct Title")
    }

    @Test func missingTypedIDFallsThroughToAnotherTypedID() async throws {
        let client = AppleTMDBClient { request in
            let path = request.url!.path
            #expect(!path.contains("search"))
            let missing = path.hasSuffix("/movie/1")
            let body = missing ? "{}" : path.contains("find")
                ? #"{"movie_results":[{"id":123}],"tv_results":[]}"#
                : #"{"id":123,"title":"Correct Title","external_ids":{"imdb_id":"tt1234567"}}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: missing ? 404 : 200,
                httpVersion: nil, headerFields: nil)!)
        }
        var parsed = AppleLibraryTitleParser.parse(name: "Misleading.mkv")
        parsed.explicitIDs = ["tmdb": "1", "imdb": "tt1234567"]
        #expect(try await AppleLibraryMetadataResolver.directLookup(parsed, client: client,
            configuration: .init(credential: "fixture"))?.mediaID == "tt1234567")
    }

    @Test(arguments: ["tmdb", "catalog", "metadata"])
    func missingProviderRecordIsCachedAsNoMatch(_ provider: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = file("Missing.2024.mkv")
        let probe = CacheMissProbe()
        let resolver = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in try await probe.missingRecord(provider) }
        #expect(try await resolver.resolve(item, sources: [], tmdbKey: "fixture", omdbKey: "") == nil)
        #expect(try await resolver.resolve(item, sources: [], tmdbKey: "fixture", omdbKey: "") == nil)
        #expect(await probe.calls == 1)
        let path = root.appendingPathComponent(item.sourceID.uuidString)
            .appendingPathComponent(AppleLibraryMetadataResolver.cacheKey(item) + ".json")
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        #expect(object["reason"] as? String == "noMatch")
    }

    #if OPENSTREAM_ADDONS
    @Test func correctionTypedIDUsesFallbackWhenConfiguredProviderIsUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try #require(AppleStremioMetadataClient.defaultMetadataSource.url.host)
        let directory = root.appendingPathComponent(host).appendingPathComponent("meta/movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"meta":{"id":"tt1234567","type":"movie","name":"Correct Title"}}"#.utf8)
            .write(to: directory.appendingPathComponent("tt1234567.json"))
        let results = try await AppleNetworkStub.$testRoot.withValue(root) {
            try await AppleLibraryMetadataResolver.correctionCandidates(query: "tt1234567", year: nil,
                kind: .movie, sources: [], tmdbKey: "fixture", omdbKey: "")
        }
        #expect(results.map(\.mediaID) == ["tt1234567"])
    }

    @Test func correctionSearchUsesDefaultCatalogWithoutCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try #require(AppleStremioMetadataClient.defaultMetadataSource.url.host)
        let directory = root.appendingPathComponent(host).appendingPathComponent("catalog/movie/top")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"metas":[{"id":"tt1234567","type":"movie","name":"Fixture Film","releaseInfo":"2024"}]}"#.utf8)
            .write(to: directory.appendingPathComponent("search=Fixture Film.json"))
        let results = try await AppleNetworkStub.$testRoot.withValue(root) {
            try await AppleLibraryMetadataResolver.correctionCandidates(query: "Fixture Film", year: 2024,
                kind: .movie, sources: [], tmdbKey: "", omdbKey: "")
        }
        #expect(results.map(\.mediaID) == ["tt1234567"])
    }

    @Test func automaticIdentityDoesNotTrustAnUnverifiedFilenameID() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try #require(AppleStremioMetadataClient.defaultMetadataSource.url.host)
        let directory = root.appendingPathComponent(host).appendingPathComponent("meta/movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"meta":{"id":"tt1234567","type":"movie","name":"Correct Title"}}"#.utf8)
            .write(to: directory.appendingPathComponent("tt1234567.json"))
        let item = file("Wrong {tmdb-1} [imdbid-tt1234567].mkv")
        let resolver = AppleLibraryMetadataResolver(directory: root.appendingPathComponent("cache"))
        let result = try await AppleNetworkStub.$testRoot.withValue(root) {
            try await resolver.resolve(item, sources: [], tmdbKey: "", omdbKey: "")
        }
        #expect(result?.mediaID == "tt1234567")
        let identity = await resolver.strongMatchIDs(for: item)
        #expect(identity?.imdb == "tt1234567")
        #expect(identity?.tmdb == nil)
    }
    #endif

    @Test func cachePolicy() {
        let now = Date()
        #expect(AppleLibraryMetadataResolver.retryInterval(reason: .providerUnreachable, attempts: 1) == 30)
        #expect(AppleLibraryMetadataResolver.retryInterval(reason: .providerUnreachable, attempts: 9) == 900)
        #expect(AppleLibraryMetadataResolver.cacheIsFresh(value: nil, reason: .noMatch, checkedAt: now, attempts: 1, parserVersion: 0, configuration: "a", currentConfiguration: "a", now: now) == false)
        #expect(AppleLibraryMetadataResolver.cacheIsFresh(value: nil, reason: .noMatch, checkedAt: now, attempts: 1, parserVersion: AppleLibraryTitleParser.version, configuration: "a", currentConfiguration: "b", now: now) == false)
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Title")
        #expect(AppleLibraryMetadataResolver.cacheIsFresh(value: item, reason: nil, checkedAt: now.addingTimeInterval(-604801), attempts: 1, parserVersion: AppleLibraryTitleParser.version, configuration: "a", currentConfiguration: "a", now: now) == false)
    }

    @Test func negativeCacheRetainsReasonAndRetriesForConfigurationAndParserChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = file("Film.2024.mkv")
        let probe = CacheMissProbe()
        let resolver = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in try await probe.lookup() }
        #expect(try await resolver.resolve(item, sources: [], tmdbKey: "a", omdbKey: "") == nil)
        #expect(try await resolver.resolve(item, sources: [], tmdbKey: "a", omdbKey: "") == nil)
        #expect(await probe.calls == 1)
        let path = root.appendingPathComponent(item.sourceID.uuidString).appendingPathComponent(AppleLibraryMetadataResolver.cacheKey(item) + ".json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        #expect(object["reason"] as? String == "providerUnreachable")
        #expect(object["configuration"] as? String == AppleLibraryMetadataResolver.configurationDigest([], "a", ""))
        #expect(object["configuration"] as? String != AppleLibraryMetadataResolver.configurationDigest([], "b", ""))
        #expect(try await resolver.resolve(item, sources: [], tmdbKey: "b", omdbKey: "") == nil)
        #expect(await probe.calls == 2)
        object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        object["parserVersion"] = 0
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        #expect(try await resolver.resolve(item, sources: [], tmdbKey: "b", omdbKey: "") == nil)
        #expect(await probe.calls == 3)
    }

    /// D2: an old positive is shown at launch with no network, then revalidated.
    @Test func stalePositiveIsPublishedAtLaunchAndRevalidated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = file("Film.2024.mkv")
        let resolver = AppleLibraryMetadataResolver(directory: root) { title, _, _, _ in
            AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: title.title)
        }
        let original = try await resolver.resolve(item, sources: [], tmdbKey: "", omdbKey: "")
        let path = root.appendingPathComponent(item.sourceID.uuidString).appendingPathComponent(AppleLibraryMetadataResolver.cacheKey(item) + ".json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        object["checkedAt"] = Date().addingTimeInterval(-8 * 86400).timeIntervalSinceReferenceDate
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let probe = CacheMissProbe()
        let offline = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in try await probe.lookup() }
        let groups = AppleLibrarySeries.groups([item])
        #expect(await offline.cachedLookups(for: groups).metadata[groups[0].id] == original)
        #expect(await probe.calls == 0)
        // Ten days is past every entry's jittered deadline.
        object["checkedAt"] = Date().addingTimeInterval(-10 * 86400).timeIntervalSinceReferenceDate
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        #expect(await offline.cachedLookups(for: groups).metadata[groups[0].id] == original)
        #expect(await offline.needsRevalidation(item, sources: [], tmdbKey: "", omdbKey: ""))
        let changed = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in
            AppleCatalogItem(mediaID: "tt7654321", type: "movie", name: "Updated")
        }
        #expect(try await changed.resolve(item, sources: [], tmdbKey: "", omdbKey: "")?.name == "Updated")
    }

    @Test func revalidationDeadlineIsSpreadPerEntry() {
        let ages = (0..<200).map { AppleLibraryMetadataResolver.revalidationAge(for: "entry-\($0)") }
        #expect(ages.allSatisfy { $0 >= 604800 && $0 < 604800 + 172800 })
        #expect(Set(ages.map { Int($0 / 3600) }).count > 20)
        #expect(AppleLibraryMetadataResolver.revalidationAge(for: "same") == AppleLibraryMetadataResolver.revalidationAge(for: "same"))
        let now = Date()
        let item = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Title")
        #expect(AppleLibraryMetadataResolver.cacheIsFresh(value: item, reason: nil, checkedAt: now.addingTimeInterval(-6.9 * 86400), attempts: 1,
            parserVersion: AppleLibraryTitleParser.version, configuration: "a", currentConfiguration: "a", now: now,
            revalidateAfter: AppleLibraryMetadataResolver.revalidationAge(for: "x")))
    }

    /// A background revalidation that finds nothing keeps the match it had.
    @Test func revalidationNoMatchKeepsTheKnownPositive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = file("Film.2024.mkv")
        let candidate = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Film")
        _ = try await AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in candidate }
            .resolve(item, sources: [], tmdbKey: "", omdbKey: "")
        let path = root.appendingPathComponent(item.sourceID.uuidString).appendingPathComponent(AppleLibraryMetadataResolver.cacheKey(item) + ".json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        object["checkedAt"] = Date().addingTimeInterval(-10 * 86400).timeIntervalSinceReferenceDate
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let empty = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in nil }
        #expect(try await empty.resolve(item, sources: [], tmdbKey: "", omdbKey: "") == candidate)
        #expect(await !empty.needsRevalidation(item, sources: [], tmdbKey: "", omdbKey: ""))
        #expect(try await empty.resolve(item, sources: [], tmdbKey: "", omdbKey: "", refresh: true) == nil)
    }

    @Test func stalePositiveSurvivesOutageButRetriesSoon() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = file("Film.2024.mkv")
        let candidate = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Film")
        let resolver = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in candidate }
        _ = try await resolver.resolve(item, sources: [], tmdbKey: "", omdbKey: "")
        let path = root.appendingPathComponent(item.sourceID.uuidString).appendingPathComponent(AppleLibraryMetadataResolver.cacheKey(item) + ".json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        object["checkedAt"] = Date().addingTimeInterval(-10 * 86400).timeIntervalSinceReferenceDate
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let probe = CacheMissProbe()
        let offline = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in try await probe.lookup() }
        #expect(try await offline.resolve(item, sources: [], tmdbKey: "", omdbKey: "") == candidate)
        #expect(try await offline.resolve(item, sources: [], tmdbKey: "", omdbKey: "") == candidate)
        #expect(await probe.calls == 1)
        object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        #expect(object["reason"] as? String == "providerUnreachable")
        object["checkedAt"] = Date().addingTimeInterval(-31).timeIntervalSinceReferenceDate
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        #expect(await offline.needsRevalidation(item, sources: [], tmdbKey: "", omdbKey: ""))
    }

    /// Smoke test only: the fixture library is one group, so this cannot show
    /// a before/after match-count difference.
    @Test func e2eLibraryFixtureResolves() async throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let stubs = project.appendingPathComponent("Apps/TestPlans/Stubs")
        let source = AppleSource(kind: .library, name: "Fixture Library", url: stubs.appendingPathComponent("library"))
        let items = try await AppleLibraryScanner().scan(source: source)
        let groups = AppleLibrarySeries.groups(items)
        let catalog = AppleSource(kind: .stremio, name: "Fixture", url: URL(string: "https://fixture.example/manifest.json")!,
            resources: ["catalog", "meta"], catalogs: [.init(type: "movie", id: "top", supportsSearch: true)])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = AppleLibraryMetadataResolver(directory: root)
        var matched = 0
        try await AppleNetworkStub.$testRoot.withValue(stubs) {
            for group in groups {
                if let item = group.items.first,
                   try await resolver.resolve(item, sources: [catalog], tmdbKey: "", omdbKey: "") != nil { matched += 1 }
            }
        }
        #expect(groups.count == 1)
        #expect(matched == groups.count)
    }

    @Test func correctionSearchUsesOMDbWhenItIsTheConfiguredProvider() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("www.omdbapi.com")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"Title":"Fixture Film","Year":"2024","imdbID":"tt1234567","Response":"True"}"#.utf8)
            .write(to: directory.appendingPathComponent("index.json"))
        let results = try await AppleNetworkStub.$testRoot.withValue(root) {
            try await AppleLibraryMetadataResolver.correctionCandidates(query: "Fixture Film", year: 2024,
                kind: .movie, sources: [], tmdbKey: "", omdbKey: "fixture")
        }
        #expect(results.map(\.mediaID) == ["tt1234567"])
    }

    @Test(.timeLimit(.minutes(1))) func cancelledWaiterDoesNotCancelAnotherCardsLookup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = SuspendedMatchProbe()
        let resolver = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in await probe.lookup() }
        let item = file("Film.2024.mkv")
        let first = Task { try await resolver.resolve(item, sources: [], tmdbKey: "", omdbKey: "") }
        await probe.waitUntilStarted()
        let second = Task { try await resolver.resolve(item, sources: [], tmdbKey: "", omdbKey: "") }
        while await resolver.activeLookupWaiterCount < 2 { await Task.yield() }
        first.cancel()
        // The cancelled card returns while the shared lookup is still suspended.
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await probe.calls == 1)
        while await resolver.activeLookupWaiterCount > 1 { await Task.yield() }
        await probe.finish()
        #expect(try await second.value?.mediaID == "tt1234567")
        #expect(await probe.calls == 1)
    }

    @Test(.timeLimit(.minutes(1))) func duplicatesCoalesceAndCorrectionWins() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = SuspendedMatchProbe()
        let resolver = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in await probe.lookup() }
        let item = file("Movie.2024.mkv")
        let first = Task { try await resolver.resolve(item, sources: [], tmdbKey: "", omdbKey: "") }
        await probe.waitUntilStarted()
        let second = Task { try await resolver.resolve(item, sources: [], tmdbKey: "", omdbKey: "") }
        while await resolver.activeLookupWaiterCount < 2 { await Task.yield() }
        let correct = AppleCatalogItem(mediaID: "tt7654321", type: "movie", name: "Correct")
        try await resolver.correctMatch(for: item, candidate: correct, provider: "fixture")
        await probe.finish()
        #expect(try await first.value == correct)
        #expect(try await second.value == correct)
        #expect(await probe.calls == 1)
        let reopened = AppleLibraryMetadataResolver(directory: root) { _, _, _, _ in nil }
        #expect(try await reopened.resolve(item, sources: [], tmdbKey: "", omdbKey: "") == correct)
    }
}

private actor SuspendedMatchProbe {
    var calls = 0
    private var started: CheckedContinuation<Void, Never>?
    private var responses: [CheckedContinuation<AppleCatalogItem?, Never>] = []
    func lookup() async -> AppleCatalogItem? {
        calls += 1
        return await withCheckedContinuation { continuation in
            responses.append(continuation)
            started?.resume(); started = nil
        }
    }
    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() {
        for response in responses { response.resume(returning: .init(mediaID: "tt1234567", type: "movie", name: "Wrong")) }
        responses = []
    }
}

private actor RequestLog {
    var urls: [URL] = []
    func append(_ url: URL) { urls.append(url) }
}

private actor CacheMissProbe {
    var calls = 0
    func lookup() throws -> AppleCatalogItem? { calls += 1; throw URLError(.cannotConnectToHost) }
    func missingRecord(_ provider: String) throws -> AppleCatalogItem? {
        calls += 1
        switch provider {
        case "catalog": throw AppleStremioCatalogError.requestFailed(404)
        case "metadata": throw AppleStremioPlaybackError.requestFailed(404)
        default: throw AppleTMDBError.requestFailed(404)
        }
    }
}
