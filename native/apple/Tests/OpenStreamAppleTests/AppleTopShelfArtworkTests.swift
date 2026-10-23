import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import OpenStreamApple

/// Top Shelf round 2 (owner 2026-10-16): the carousel follows the Home hero,
/// and each page's picture is drawn by the app with the title's wordmark in it.
@Suite("Top Shelf artwork")
struct AppleTopShelfArtworkTests {
    private func item(_ id: String, backdrop: Bool = true) -> AppleTopShelfSnapshot.Item {
        .init(id: id, title: id.uppercased(), kind: "movie", artworkURL: nil,
              displayURL: URL(string: "openstream://media/\(id)?action=display")!,
              playURL: URL(string: "openstream://media/\(id)?action=play"),
              landscapeArtworkURL: backdrop ? URL(string: "https://fixture.example/art/\(id).jpg") : nil)
    }

    private static func png(width: Int, height: Int, opaque: CGRect? = nil) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(opaque ?? CGRect(x: 0, y: 0, width: width, height: height))
        let buffer = NSMutableData()
        let destination = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return buffer as Data
    }

    @Test("Hero pages come first in the hero's order, then Continue Watching, each title once")
    func heroOrder() {
        let snapshot = AppleTopShelfSnapshot(version: 1, generatedAt: .now,
            continueWatching: [item("resume"), item("other")], recentlyAdded: [], favorites: [],
            topPicks: [item("pick")], heroes: [item("lead"), item("resume"), item("bare", backdrop: false)])
        let pages = AppleTopShelfContentBuilder.carouselItems(for: snapshot)
        #expect(pages.map(\.item.id) == ["lead", "resume", "other"])
        #expect(pages.map(\.contextTitle) == [nil, "Continue Watching", "Continue Watching"])
    }

    @Test("The backdrop covers the 16:9 canvas and the wordmark sits in its box, leading")
    func layout() {
        let square = AppleTopShelfArtworkLayout.fillRect(for: CGSize(width: 1000, height: 1000))
        #expect(square.width == 1920 && square.height == 1920 && square.minY == -420)
        let wide = AppleTopShelfArtworkLayout.wordmarkRect(for: CGSize(width: 2000, height: 400))
        #expect(wide.minX == AppleTopShelfArtworkLayout.leadingInset)
        #expect(wide.width == AppleTopShelfArtworkLayout.wordmarkBox.width && wide.height == 120)
        let tall = AppleTopShelfArtworkLayout.wordmarkRect(for: CGSize(width: 300, height: 300))
        #expect(tall.height == AppleTopShelfArtworkLayout.wordmarkBox.height && tall.width == tall.height)
    }

    @Test("File names change with the wordmark")
    func names() {
        let backdrop = URL(string: "https://fixture.example/art/a.jpg")!
        let logo = URL(string: "https://fixture.example/art/a.png")!
        let plain = AppleTopShelfArtworkLayout.fileName(backdrop: backdrop, wordmark: nil)
        #expect(plain == AppleTopShelfArtworkLayout.fileName(backdrop: backdrop, wordmark: nil))
        #expect(plain != AppleTopShelfArtworkLayout.fileName(backdrop: backdrop, wordmark: logo))
        #expect(plain.hasSuffix(".jpg") && !plain.contains("/"))
    }

    @Test("The writer draws a 1920×1080 picture per page, keeps the wordmark's absence honest and clears old files")
    func writerDrawsPictures() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "openstream-topshelf-art-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backdropData = Self.png(width: 1280, height: 720)
        let logoData = Self.png(width: 800, height: 400, opaque: CGRect(x: 100, y: 100, width: 600, height: 200))
        let store = AppleTopShelfArtworkStore { url in
            if url.path.hasSuffix("missing.png") { throw URLError(.timedOut) }
            return url.pathExtension == "png" ? logoData : backdropData
        }
        let directory = AppleTopShelfArtworkStore.directory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: directory.appending(path: "stale.jpg"))

        let backdrop = URL(string: "https://fixture.example/art/hero-textless.jpg")!
        let logo = URL(string: "https://fixture.example/art/hero.png")!
        let missing = URL(string: "https://fixture.example/art/missing.png")!
        let heroes = [
            AppleTopShelfHero(item: item("lead"), backdropURL: backdrop, wordmarkURL: logo),
            AppleTopShelfHero(item: item("second"), backdropURL: backdrop, wordmarkURL: missing),
        ]
        let writer = AppleTopShelfSnapshotWriter(containerProvider: { root }, artwork: store)
        try await writer.write(records: [], heroes: heroes, enabled: true)
        let written = try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read())

        #expect(written.heroes.map(\.id) == ["lead", "second"])
        #expect(written.heroes[0].shelfImage == AppleTopShelfArtworkLayout.fileName(backdrop: backdrop, wordmark: logo))
        #expect(written.heroes[1].shelfImage == AppleTopShelfArtworkLayout.fileName(backdrop: backdrop, wordmark: nil))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(Set(files) == Set(written.heroes.compactMap(\.shelfImage)))
        let picture = try Data(contentsOf: directory.appending(path: try #require(written.heroes[0].shelfImage)))
        let size = try #require(AppleWidgetArtworkThumbnail.pixelSize(ofEncoded: picture))
        #expect(size.width == 1920 && size.height == 1080)

        try await writer.write(records: [], enabled: false)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// A server-only Apple TV with nothing in progress still gets a shelf:
    /// the servers' recently added titles, with the posters the app saved
    /// from the server over plain http; the snapshot names files, never the
    /// server's address.
    @Test("Recently Added fills the shelf from media servers, with the app's copies of LAN art")
    func recentlyAddedFromAServerOverHTTP() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "openstream-topshelf-recent-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = AppleSource(kind: .mediaServer, name: "Fixture Jellyfin", url: URL(string: "http://192.168.1.20:8096")!)
        let share = AppleSource(kind: .nas, name: "Share", url: URL(string: "smb://fixture.example/share")!)
        let posterData = Self.png(width: 400, height: 600)
        let store = AppleTopShelfArtworkStore { url in
            guard url.host == "192.168.1.20" else { throw URLError(.cannotFindHost) }
            return posterData
        }
        let movie = AppleCatalogItem(mediaID: "jf:movie-1", type: "movie", name: "Fixture Movie",
                                     posterURL: URL(string: "http://192.168.1.20:8096/Items/movie-1/Images/Primary"),
                                     backgroundURL: URL(string: "http://192.168.1.20:8096/Items/movie-1/Images/Backdrop"))
        let fromServer = AppleMediaIngestion.catalogRecord(instanceID: server.id, item: movie)
        let fromShare = AppleMediaIngestion.catalogRecord(instanceID: share.id,
            item: AppleCatalogItem(mediaID: "share-1", type: "movie", name: "Share Movie"))
        let writer = AppleTopShelfSnapshotWriter(containerProvider: { root }, artwork: store)

        try await writer.write(records: [fromServer, fromShare], sources: [server, share], enabled: true)

        let written = try #require(AppleTopShelfSnapshotReader(containerProvider: { root }).read())
        #expect(written.continueWatching.isEmpty)
        let row = try #require(AppleTopShelfContentBuilder.sections(for: written).first)
        #expect(row.title == "Recently Added")
        #expect(row.items.map(\.id) == [fromServer.id])
        let directory = AppleTopShelfArtworkStore.directory(in: root)
        let poster = try #require(row.imageURL(for: row.items[0], art: directory))
        #expect(poster.isFileURL)
        #expect(FileManager.default.fileExists(atPath: poster.path))
        let page = try #require(AppleTopShelfContentBuilder.carouselItems(for: written).first)
        #expect(page.item.id == fromServer.id && page.contextTitle == "Recently Added")
        let picture = try #require(page.item.shelfImage)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: picture).path))
        let json = String(decoding: try JSONEncoder().encode(written), as: UTF8.self)
        #expect(!json.contains("192.168.1.20"))
    }

    /// The shelf is written before any server art is fetched, so a slow or
    /// offline server delays only its own pictures.
    @Test("The snapshot is on disk before the server's art is fetched")
    func snapshotBeforeServerArt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "openstream-topshelf-first-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = AppleSource(kind: .mediaServer, name: "Fixture Jellyfin", url: URL(string: "http://192.168.1.20:8096")!)
        let movie = AppleCatalogItem(mediaID: "jf:movie-1", type: "movie", name: "Fixture Movie",
                                     posterURL: URL(string: "http://192.168.1.20:8096/Items/movie-1/Images/Primary"))
        let record = AppleMediaIngestion.catalogRecord(instanceID: server.id, item: movie)
        let reader = AppleTopShelfSnapshotReader(containerProvider: { root })
        let posterData = Self.png(width: 400, height: 600)
        let shownWhileFetching = Mutex<[String]?>(nil)
        let store = AppleTopShelfArtworkStore { _ in
            shownWhileFetching.withLock { $0 = reader.read()?.topPicks.map(\.id) }
            return posterData
        }
        let writer = AppleTopShelfSnapshotWriter(containerProvider: { root }, artwork: store)

        try await writer.write(records: [record], sources: [server], enabled: true)

        #expect(shownWhileFetching.withLock { $0 } == [record.id])
        #expect(try #require(reader.read()).topPicks.first?.shelfPoster != nil)
    }

    @Test("A trailer is a direct https video file, never YouTube")
    func trailers() {
        #expect(AppleTopShelfTrailerPolicy.previewVideoURL(URL(string: "https://cdn.example.com/t/a.mp4")) != nil)
        #expect(AppleTopShelfTrailerPolicy.previewVideoURL(URL(string: "https://cdn.example.com/t/a.m3u8")) != nil)
        #expect(AppleTopShelfTrailerPolicy.previewVideoURL(URL(string: "http://cdn.example.com/t/a.mp4")) == nil)
        #expect(AppleTopShelfTrailerPolicy.previewVideoURL(URL(string: "https://www.youtube.com/watch.mp4")) == nil)
        #expect(AppleTopShelfTrailerPolicy.previewVideoURL(URL(string: "https://cdn.example.com/t/a.mp4?token=1")) == nil)
        #expect(AppleTopShelfTrailerPolicy.previewVideoURL(URL(string: "https://cdn.example.com/watch?v=abc")) == nil)
    }
}
