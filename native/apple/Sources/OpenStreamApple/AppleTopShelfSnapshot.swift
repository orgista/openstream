import CryptoKit
import Foundation
import Observation

#if os(tvOS)
import TVServices
#endif

#if os(iOS) || os(visionOS)
import WidgetKit
#endif

public struct AppleTopShelfSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let kind: String
        public let artworkURL: URL?
        public let displayURL: URL
        public let playURL: URL?
        /// How far in, 0–1, for a title in Continue Watching; nil elsewhere.
        /// The Top Shelf draws it as the bar under the tile, as the Apple TV
        /// app does. Snapshots written before this field decode it as nil.
        public let progress: Double?
        /// The title's 16:9 backdrop — the art its Continue Watching card
        /// shows — so the Top Shelf can draw landscape tiles as the Apple TV
        /// app does. `artworkURL` stays the poster for a row that cannot go
        /// landscape. Snapshots written before this field decode it as nil.
        public let landscapeArtworkURL: URL?
        /// What the full-screen Top Shelf carousel writes under the title, as
        /// the Apple TV app does: the synopsis, the first genre, the year and
        /// the running time. Absent in older snapshots and when unknown.
        public let summary: String?
        public let genre: String?
        public let year: Int?
        public let durationSeconds: Double?
        /// The carousel page's picture the app drew (`AppleTopShelfArtworkStore`):
        /// a file name in the group's Library/Caches/topshelf-art. Nil keeps
        /// the remote backdrop.
        public let shelfImage: String?
        /// A public trailer file the carousel may play behind the page
        /// (`AppleTopShelfTrailerPolicy`).
        public let previewVideoURL: URL?
        /// The page's trailer the app saved from the user's server
        /// (`AppleTopShelfTrailerFiles`): a file name in the group's
        /// Library/Caches/topshelf-trailers. Its URL carries a token, so the
        /// file goes on the shelf and the URL never does.
        public let shelfVideo: String?

        public init(id: String, title: String, kind: String, artworkURL: URL?, displayURL: URL, playURL: URL?,
                    progress: Double? = nil, landscapeArtworkURL: URL? = nil,
                    summary: String? = nil, genre: String? = nil, year: Int? = nil, durationSeconds: Double? = nil,
                    shelfImage: String? = nil, previewVideoURL: URL? = nil, shelfVideo: String? = nil) {
            self.id = id
            self.title = title
            self.kind = kind
            self.artworkURL = artworkURL
            self.displayURL = displayURL
            self.playURL = playURL
            self.progress = progress
            self.landscapeArtworkURL = landscapeArtworkURL
            self.summary = summary.map { String($0.prefix(600)) }
            self.genre = genre.map { String($0.prefix(60)) }
            self.year = year
            self.durationSeconds = durationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            self.shelfImage = shelfImage
            self.previewVideoURL = AppleTopShelfTrailerPolicy.previewVideoURL(previewVideoURL)
            self.shelfVideo = AppleTopShelfTrailerPolicy.shelfVideo(shelfVideo)
        }

        public var remainingMinutes: Int? {
            guard let progress, progress.isFinite, (0...1).contains(progress),
                  let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 else { return nil }
            return Int(exactly: ceil((durationSeconds - durationSeconds * progress) / 60))
        }

        func withShelfImage(_ name: String?) -> Item {
            .init(id: id, title: title, kind: kind, artworkURL: artworkURL, displayURL: displayURL, playURL: playURL,
                  progress: progress, landscapeArtworkURL: landscapeArtworkURL, summary: summary, genre: genre,
                  year: year, durationSeconds: durationSeconds, shelfImage: name, previewVideoURL: previewVideoURL,
                  shelfVideo: shelfVideo)
        }

        func withShelfVideo(_ name: String?) -> Item {
            .init(id: id, title: title, kind: kind, artworkURL: artworkURL, displayURL: displayURL, playURL: playURL,
                  progress: progress, landscapeArtworkURL: landscapeArtworkURL, summary: summary, genre: genre,
                  year: year, durationSeconds: durationSeconds, shelfImage: shelfImage, previewVideoURL: previewVideoURL,
                  shelfVideo: name)
        }
    }

    public var widgetHero: AppleWidgetHeroArtwork?

    public let version: Int
    public let generatedAt: Date
    public let continueWatching: [Item]
    public let recentlyAdded: [Item]
    public let favorites: [Item]
    /// Up to 10 items from the first non-empty catalog shelf (e.g. Cinemeta
    /// Popular), shown on Top Shelf when the user has sources configured but
    /// nothing in progress. Defaults to empty so snapshots written before
    /// this field existed still decode.
    public let topPicks: [Item]
    public let favoriteChannels: [Item]
    public let recentChannels: [Item]
    /// The Home hero carousel's pages, in its order: the Top Shelf carousel
    /// shows the same titles (owner 2026-10-16). Empty in older snapshots and
    /// before Home has drawn.
    public let heroes: [Item]

    public init(
        version: Int,
        generatedAt: Date,
        continueWatching: [Item],
        recentlyAdded: [Item],
        favorites: [Item],
        topPicks: [Item] = [],
        favoriteChannels: [Item] = [],
        recentChannels: [Item] = [],
        heroes: [Item] = [],
        widgetHero: AppleWidgetHeroArtwork? = nil
    ) {
        self.widgetHero = widgetHero
        self.version = version
        self.generatedAt = generatedAt
        self.continueWatching = continueWatching
        self.recentlyAdded = recentlyAdded
        self.favorites = favorites
        self.topPicks = topPicks
        self.favoriteChannels = favoriteChannels
        self.recentChannels = recentChannels
        self.heroes = heroes
    }

    private enum CodingKeys: String, CodingKey {
        case version, generatedAt, continueWatching, recentlyAdded, favorites, topPicks, favoriteChannels, recentChannels,
             heroes, widgetHero
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgetHero = try container.decodeIfPresent(AppleWidgetHeroArtwork.self, forKey: .widgetHero)
        version = try container.decode(Int.self, forKey: .version)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        continueWatching = try container.decode([Item].self, forKey: .continueWatching)
        recentlyAdded = try container.decode([Item].self, forKey: .recentlyAdded)
        favorites = try container.decode([Item].self, forKey: .favorites)
        favoriteChannels = try container.decodeIfPresent([Item].self, forKey: .favoriteChannels) ?? []
        recentChannels = try container.decodeIfPresent([Item].self, forKey: .recentChannels) ?? []
        topPicks = try container.decodeIfPresent([Item].self, forKey: .topPicks) ?? []
        heroes = try container.decodeIfPresent([Item].self, forKey: .heroes) ?? []
    }

    /// The same snapshot with each listed item's carousel picture, by item id.
    func withShelfImages(_ names: [String: String]) -> AppleTopShelfSnapshot {
        carouselPages { $0.withShelfImage(names[$0.id]) }
    }

    /// The same snapshot with each carousel page's saved trailer, by item id.
    func withShelfVideos(_ names: [String: String]) -> AppleTopShelfSnapshot {
        carouselPages { $0.withShelfVideo(names[$0.id]) }
    }

    private func carouselPages(_ change: (Item) -> Item) -> AppleTopShelfSnapshot {
        AppleTopShelfSnapshot(version: version, generatedAt: generatedAt, continueWatching: continueWatching.map(change),
                              recentlyAdded: recentlyAdded, favorites: favorites, topPicks: topPicks.map(change),
                              favoriteChannels: favoriteChannels, recentChannels: recentChannels,
                              heroes: heroes.map(change), widgetHero: widgetHero)
    }
}

/// Which trailer the full-screen carousel may play behind a page: a direct
/// video file over https, never a YouTube page (the system player cannot
/// open one), or the copy the app saved of the title's trailer on the
/// user's server (`AppleTopShelfTrailerFiles`): a server URL carries the
/// user's token, so only the file reaches the shelf.
enum AppleTopShelfTrailerPolicy {
    static let fileExtensions: Set<String> = ["mp4", "m4v", "mov", "m3u8"]
    static let savedExtensions: Set<String> = ["mp4", "m4v", "mov"]
    static let directoryName = "topshelf-trailers"

    static func directory(in root: URL) -> URL {
        root.appending(path: "Library/Caches", directoryHint: .isDirectory)
            .appending(path: directoryName, directoryHint: .isDirectory)
    }

    /// A saved trailer's name: a bare file name with a video extension.
    static func shelfVideo(_ name: String?) -> String? {
        guard let name, !name.isEmpty, !name.contains("/"), !name.hasPrefix("."),
              savedExtensions.contains((name as NSString).pathExtension.lowercased()) else { return nil }
        return name
    }

    /// One name per title, from nothing secret: the server's URL (and its
    /// token) is not part of it.
    static func fileName(mediaID: String, trailer: AppleServerTrailer) -> String {
        let ext = trailer.url.pathExtension.lowercased()
        return "\(stem(mediaID: mediaID)).\(savedExtensions.contains(ext) ? ext : "mp4")"
    }

    /// The title's saved trailer in `directory`, whatever its extension.
    static func savedFile(mediaID: String, in directory: URL) -> String? {
        let stem = stem(mediaID: mediaID)
        return savedExtensions.sorted().map { "\(stem).\($0)" }
            .first { FileManager.default.fileExists(atPath: directory.appending(path: $0).path) }
    }

    private static func stem(mediaID: String) -> String {
        SHA256.hash(data: Data(mediaID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func previewVideoURL(_ url: URL?) -> URL? {
        guard let url = AppleSystemArtworkPolicy.publicURL(url),
              let host = url.host?.lowercased(),
              !["youtube.com", "youtu.be", "youtube-nocookie.com"].contains(where: { host == $0 || host.hasSuffix(".\($0)") }),
              fileExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }
}

/// One page of the Home hero carousel as the Top Shelf mirrors it: the item
/// it publishes, plus the art the billboard draws, which only the app
/// fetches (for the page's picture) and which never enters the snapshot.
public struct AppleTopShelfHero: Equatable, Sendable {
    public let item: AppleTopShelfSnapshot.Item
    public let backdropURL: URL?
    public let wordmarkURL: URL?
    /// What finds the page's trailer on the user's server.
    let trailerQuery: AppleServerTrailerQuery?

    init(item: AppleTopShelfSnapshot.Item, backdropURL: URL?, wordmarkURL: URL?, trailerQuery: AppleServerTrailerQuery? = nil) {
        self.item = item
        self.backdropURL = backdropURL
        self.wordmarkURL = wordmarkURL
        self.trailerQuery = trailerQuery
    }

    /// The hero page for a title the billboard shows: `item` already carries
    /// the billboard's textless backdrop and wordmark when they have arrived.
    public static func page(record: AppleMediaRecord, item: AppleCatalogItem, wordmark: URL?) -> AppleTopShelfHero {
        AppleTopShelfHero(item: AppleTopShelfSnapshotWriter.catalogItem(id: record.id, title: record.title,
                                                                        kind: record.kind.rawValue, item: item),
                          backdropURL: item.backgroundURL, wordmarkURL: wordmark,
                          trailerQuery: AppleServerTrailerQuery(item: item))
    }
}

/// Where Home hands its hero pages to the Top Shelf publisher. Home decides
/// the pages (`AppleDiscoverView`); the root view republishes when they move.
@MainActor
@Observable
public final class AppleTopShelfHeroFeed {
    public static let shared = AppleTopShelfHeroFeed()
    public private(set) var heroes: [AppleTopShelfHero] = []

    public func update(_ heroes: [AppleTopShelfHero]) {
        if heroes != self.heroes { self.heroes = heroes }
    }
}

/// Plain, TVServices-free mirror of the section list `TopShelfProvider`
/// renders. Kept here so the ordering/emptiness rules are covered by
/// `swift test` — TVServices is unavailable outside tvOS, so the provider
/// extension cannot be unit tested directly. `TopShelfProvider` mirrors this
/// logic when it builds `TVTopShelfSectionedContent`; keep the two in sync.
public struct AppleTopShelfSection: Equatable, Sendable {
    public enum ImageShape: Equatable, Sendable { case poster, hdtv }

    public let title: String
    public let items: [AppleTopShelfSnapshot.Item]

    /// One shape per row, as the system draws it: 16:9 only when every tile
    /// has landscape art, since a poster stretched into a 16:9 tile is worse
    /// than a row of posters.
    public var imageShape: ImageShape {
        items.allSatisfy { $0.landscapeArtworkURL != nil } ? .hdtv : .poster
    }

    /// The picture a tile shows in this row's shape.
    public func imageURL(for item: AppleTopShelfSnapshot.Item) -> URL? {
        switch imageShape {
        case .hdtv: item.landscapeArtworkURL
        case .poster: item.artworkURL ?? item.landscapeArtworkURL
        }
    }
}

/// One page of the full-screen Top Shelf carousel, the Apple TV app's shelf:
/// the 16:9 picture edge to edge with the title's wordmark in it, the context
/// ("Continue Watching") over the title, the details under it, Play and More
/// Info. No progress bar (owner 2026-10-15). Plain mirror of the
/// `TVTopShelfCarouselItem` `TopShelfProvider` builds; keep the two in sync.
public struct AppleTopShelfCarouselItem: Equatable, Sendable {
    /// Nil for a hero page that is not a resume: the Home hero names none.
    public let contextTitle: String?
    public let item: AppleTopShelfSnapshot.Item

    /// The remote backdrop, never a poster stretched to 16:9; the page shows
    /// `item.shelfImage` instead once the app has drawn it.
    public var imageURL: URL? { item.landscapeArtworkURL }
}

public enum AppleTopShelfContentBuilder {
    /// The carousel holds this many pages at most.
    public static let carouselLimit = 12
    static let continueWatchingTitle = "Continue Watching"

    /// The Home hero's pages in its order, then Continue Watching (owner
    /// 2026-10-16: "sync through heros"); before Home has drawn, Continue
    /// Watching then Top Picks. Each title once, only titles with a backdrop
    /// to fill the screen. Empty when no title has one: the provider then
    /// serves the rows (`sections(for:)`).
    public static func carouselItems(for snapshot: AppleTopShelfSnapshot) -> [AppleTopShelfCarouselItem] {
        var seen = Set<String>()
        let resumed = Set(snapshot.continueWatching.map(\.id))
        let continued = snapshot.continueWatching.map { AppleTopShelfCarouselItem(contextTitle: continueWatchingTitle, item: $0) }
        let pages = snapshot.heroes.isEmpty
            ? continued + snapshot.topPicks.map { AppleTopShelfCarouselItem(contextTitle: "Top Picks", item: $0) }
            : snapshot.heroes.map {
                AppleTopShelfCarouselItem(contextTitle: resumed.contains($0.id) ? continueWatchingTitle : nil, item: $0)
            } + continued
        return Array(pages.filter { $0.imageURL != nil && seen.insert($0.item.id).inserted }.prefix(carouselLimit))
    }

    /// Continue Watching first (when non-empty), then Top Picks. Returns an
    /// empty array when there is nothing to show at all — the provider
    /// should return `nil` for that result.
    public static func sections(for snapshot: AppleTopShelfSnapshot) -> [AppleTopShelfSection] {
        [
            snapshot.continueWatching.isEmpty ? nil : AppleTopShelfSection(
                title: "Continue Watching", items: snapshot.continueWatching
            ),
            snapshot.favoriteChannels.isEmpty ? nil : AppleTopShelfSection(
                title: "Favorite channels", items: snapshot.favoriteChannels
            ),
            snapshot.topPicks.isEmpty ? nil : AppleTopShelfSection(
                title: "Top Picks", items: snapshot.topPicks
            ),
        ].compactMap { $0 }
    }
}

/// Only system-owned projections receive remote URLs from this narrow list.
/// Arbitrary add-on artwork may carry credentials in its path or query, so it
/// remains available in-app but is never handed to Spotlight or Top Shelf.
/// Which artwork URLs may be handed to a system surface — the Top Shelf and
/// the widgets, which fetch them from their own processes.
///
/// This used to be a two-host allowlist (`image.tmdb.org`,
/// `images.metahub.space`). That silently emptied the shelf: add-ons serve
/// posters from whatever CDN they like, and on the owner's library the
/// in-progress titles came from `images.justwatch.com` and
/// `api.ratingposterdb.com`, so **every** Continue Watching tile published
/// without artwork while Top Picks — which happen to come from Cinemeta, i.e.
/// metahub — looked fine. A fixed allowlist cannot track what add-ons use, so
/// the rule is now about what is *safe* to hand to another process rather than
/// who is serving it.
///
/// A private host is still refused: a NAS or `.local` poster is unreachable
/// from the extension anyway, and publishing one would leak an internal
/// hostname into a system surface.
enum AppleSystemArtworkPolicy {
    /// Hosts that never belong in a system surface.
    private static func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".internal") {
            return true
        }
        // An IP literal is either a private address or a host with no name to
        // verify; neither belongs on the shelf.
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return true }
        if host.contains(":") { return true }   // IPv6 literal
        // A bare name with no dot is a LAN name, not a public CDN.
        return !host.contains(".")
    }

    static func publicURL(_ value: URL?) -> URL? {
        guard let value,
              value.scheme?.lowercased() == "https",
              value.user == nil,
              value.password == nil,
              // A poster URL carrying a token must not reach a system surface,
              // and no add-on CDN seen in the wild needs one to serve an image.
              value.query == nil,
              value.fragment == nil,
              let host = value.host?.lowercased(),
              !host.isEmpty,
              !isPrivateHost(host) else {
            return nil
        }
        return value
    }
}

/// Reads the snapshot the app writes into the shared app group.
///
/// The Top Shelf provider and the iOS/iPadOS widgets are separate processes
/// with no access to the app's own container, so this file is the only thing
/// they can see. Kept beside the writer so the two cannot drift.
public struct AppleTopShelfSnapshotReader: Sendable {
    private let containerProvider: @Sendable () -> URL?

    public init(containerProvider: @escaping @Sendable () -> URL? = {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppleTopShelfSnapshotWriter.appGroup
        )
    }) {
        self.containerProvider = containerProvider
    }

    /// The snapshot, or nil when the app has not written one yet, the group
    /// container is unavailable, or the file is unreadable. A widget draws its
    /// empty state from nil rather than failing.
    public func read() -> AppleTopShelfSnapshot? {
        guard let root = containerProvider() else { return nil }
        let url = AppleTopShelfSnapshotWriter.snapshotURL(in: root)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppleTopShelfSnapshot.self, from: data)
    }
}

public actor AppleTopShelfSnapshotWriter {
    public enum WriteError: Error, Sendable {
        case containerUnavailable
    }

    public static let shared = AppleTopShelfSnapshotWriter()
    /// The shared container every system surface reads through.
    ///
    /// macOS needs the team-id prefix and the other platforms must not have
    /// it. On iOS and tvOS an app group is a bare `group.…` identifier; a
    /// sandboxed Mac app's group container is named
    /// `<TeamID>.group.…` and `containerURL(forSecurityApplicationGroupIdentifier:)`
    /// hands back a path under `~/Library/Group Containers/` that only that
    /// exact string resolves to. Asking for the unprefixed form returned a URL
    /// that then failed every read and write with EPERM — `NSCocoaErrorDomain
    /// 513` on write, `257` on a directory listing (measured inside the
    /// sandboxed app, 2026-09-21), which is why the `guard let root` at the
    /// call sites never caught it.
    ///
    /// The prefix is written out here rather than read from the build: this is
    /// a package constant with no `$(TeamIdentifierPrefix)` to expand, and the
    /// entitlement that grants it (`Apps/Shared/OpenStreamMacOS.entitlements`)
    /// does use the build setting, so the two cannot disagree silently — a
    /// mismatch fails to launch.
    public static let appGroup: String = {
        #if os(macOS)
        "2VQ74PD5YG.group.com.orgista.openstream"
        #else
        "group.com.orgista.openstream"
        #endif
    }()
    public static let filename = "topshelf-v1.json"

    /// Where the snapshot lives inside the group container. Apple TV hardware
    /// refuses writes to the container's top level (NSCocoaErrorDomain 513 on
    /// OfficePlus, 2026-10-13; the simulator allows it), so on tvOS it goes in
    /// the container's Library/Caches, which the Top Shelf extension reads too.
    public static func snapshotURL(in root: URL) -> URL {
        #if os(tvOS)
        root.appending(path: "Library/Caches", directoryHint: .isDirectory).appending(path: filename)
        #else
        root.appending(path: filename)
        #endif
    }

    private let containerProvider: @Sendable () -> URL?
    private let snapshotLocation: @Sendable (URL) -> URL
    /// Draws the carousel pages' pictures; only the Apple TV has a Top Shelf.
    private let artwork: AppleTopShelfArtworkStore?
    /// Saves the hero pages' server trailers; only the Apple TV has a Top Shelf.
    private let trailerFiles: AppleTopShelfTrailerFiles?
    private let trailerDownloads: AppleTopShelfTrailerDownloads
    private let widgetArtwork = AppleWidgetHeroArtworkStore()
    private let didChange: @Sendable () -> Void

    public init(containerProvider: @escaping @Sendable () -> URL? = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }, snapshotLocation: @escaping @Sendable (URL) -> URL = { snapshotURL(in: $0) },
       artwork: AppleTopShelfArtworkStore? = defaultArtwork) {
        self.init(containerProvider: containerProvider, snapshotLocation: snapshotLocation, artwork: artwork,
                  trailerFiles: Self.defaultTrailerFiles)
    }

    init(containerProvider: @escaping @Sendable () -> URL?, snapshotLocation: @escaping @Sendable (URL) -> URL,
         artwork: AppleTopShelfArtworkStore?, trailerFiles: AppleTopShelfTrailerFiles?,
         trailerDownloads: AppleTopShelfTrailerDownloads = .shared,
         didChange: @escaping @Sendable () -> Void = { AppleTopShelfSnapshotWriter.notify() }) {
        self.containerProvider = containerProvider
        self.snapshotLocation = snapshotLocation
        self.artwork = artwork
        self.trailerFiles = trailerFiles
        self.trailerDownloads = trailerDownloads
        self.didChange = didChange
    }

    static var defaultTrailerFiles: AppleTopShelfTrailerFiles? {
        #if os(tvOS)
        AppleTopShelfTrailerFiles()
        #else
        nil
        #endif
    }

    public static var defaultArtwork: AppleTopShelfArtworkStore? {
        #if os(tvOS)
        AppleTopShelfArtworkStore()
        #else
        nil
        #endif
    }

    func snapshotExists() -> Bool {
        guard let root = containerProvider() else { return false }
        return FileManager.default.fileExists(atPath: snapshotLocation(root).path)
    }

    /// - Parameters:
    ///   - sources: When given, Continue Watching lists only what Discover's
    ///     row lists (`AppleContinueWatchingResolver`): a catalog title nothing
    ///     can open is left out. Nil treats every record as openable.
    ///   - watchedAt: When each record was last watched, by record id —
    ///     Continue Watching is most recent first, as on Discover. A record
    ///     missing here falls back to its `lastVerified`.
    ///   - savedProgress: The playback store's entry for each record, by
    ///     record id; the bar follows it as Discover's does
    ///     (`AppleContinueWatchingResolver.progress`). Nil keeps each
    ///     record's own `progress`.
    public func write(
        records: [AppleMediaRecord],
        sections: [AppleCatalogSection] = [],
        sources: [AppleSource]? = nil,
        watchedAt: [String: Date] = [:],
        savedProgress: [String: ApplePlaybackProgress]? = nil,
        activity: [String: ApplePlaybackProgress] = [:],
        successorAvailable: Set<String> = [],
        removedAt: [String: Date] = [:],
        favoriteChannels: [AppleTopShelfSnapshot.Item] = [],
        recentChannels: [AppleTopShelfSnapshot.Item] = [],
        heroes: [AppleTopShelfHero] = [],
        enabled: Bool
    ) async throws {
        guard let root = containerProvider() else { throw WriteError.containerUnavailable }
        let url = snapshotLocation(root)
        #if os(tvOS)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #endif
        guard enabled else {
            AppleWidgetHeroArtworkStore.removeAll(in: root)
            await trailerDownloads.cancel()
            try? FileManager.default.removeItem(at: AppleTopShelfArtworkStore.directory(in: root))
            try? FileManager.default.removeItem(at: AppleTopShelfTrailerPolicy.directory(in: root))
            // The extension can still read a snapshot left by older builds at the root.
            for location in Set([url, root.appending(path: Self.filename)]) {
                do {
                    try FileManager.default.removeItem(at: location)
                } catch let error as CocoaError where error.code == .fileNoSuchFile {
                    // An already absent snapshot is a completed opt-out.
                }
            }
            didChange()
            return
        }

        let eligible = records.filter { !$0.availability.isEmpty && !$0.isPrivate }
        let continued = AppleContinueWatchingResolver.inProgress(eligible,
            saved: { savedProgress?[$0.id] }, activity: { activity[$0.id] },
            successorAvailable: { successorAvailable.contains($0.id) }, removedAt: { removedAt[$0.id] }) {
                activity[$0.id]?.updatedAt ?? watchedAt[$0.id] ?? $0.lastVerified
            }
        let favorites = eligible.filter(\.isFavorite).sorted { $0.title < $1.title }
        let recent = eligible.sorted { $0.lastVerified > $1.lastVerified }
        let shownContinued = Array(Self.openable(continued, sections: sections, sources: sources)
            .prefix(AppleContinueWatchingResolver.maximumCount))
        let listed = Self.listedItems(for: Set(shownContinued.map(\.record.id)), in: sections)
        var snapshot = AppleTopShelfSnapshot(
            version: 1,
            generatedAt: .now,
            continueWatching: shownContinued.map { entry in
                let listedItem = listed[entry.record.id] ?? Self.matchedItem(for: entry)
                return Self.item(entry.record, progress: savedProgress.map {
                    AppleContinueWatchingResolver.progress(isSeries: entry.record.kind == .series,
                        saved: $0[entry.record.id], recordProgress: entry.record.progress)
                } ?? entry.record.progress,
                          landscapeArtworkURL: listed[entry.record.id].flatMap { Self.landscapeURL(for: $0) }
                              ?? Self.landscapeURL(for: entry),
                          catalogItem: listedItem)
            },
            recentlyAdded: Array(recent.prefix(20)).map { Self.item($0) },
            favorites: Array(favorites.prefix(12)).map { Self.item($0) },
            topPicks: Self.topPicks(from: sections),
            favoriteChannels: favoriteChannels, recentChannels: recentChannels,
            heroes: heroes.map(\.item)
        )
        #if os(iOS)
        let previous = (try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode(AppleTopShelfSnapshot.self, from: $0)
        }
        if let hero = previous?.widgetHero, hero.itemID == snapshot.continueWatching.first?.id {
            snapshot.widgetHero = hero
        }
        try Task.checkCancellation()
        try save(snapshot, to: url, notify: false)
        if let first = snapshot.continueWatching.first,
           let continued = shownContinued.first {
            let item = listed[continued.record.id] ?? Self.matchedItem(for: continued)
            let hero = heroes.first { $0.item.id == first.id }
            let cached: AppleHeroArtworkUpgrade.Artwork?
            if let item { cached = await AppleHeroArtworkUpgrade.shared.cachedArtwork(for: item) }
            else { cached = nil }
            let wordmark = await Self.wordmark(for: item)
            snapshot.widgetHero = await widgetArtwork.prepare(itemID: first.id,
                backdrop: hero?.backdropURL ?? cached?.backdropURL ?? first.landscapeArtworkURL,
                wordmark: hero?.wordmarkURL ?? cached?.logoURL ?? wordmark, in: root)
            try Task.checkCancellation()
            // A newer publish or opt-out may have replaced the snapshot during the fetch.
            guard let current = try? JSONDecoder().decode(AppleTopShelfSnapshot.self, from: Data(contentsOf: url)),
                  current.generatedAt == snapshot.generatedAt else { return }
            if let widgetHero = snapshot.widgetHero { widgetArtwork.removeUnused(in: root, keeping: widgetHero) }
        } else {
            AppleWidgetHeroArtworkStore.removeAll(in: root)
        }
        #endif
        if let artwork {
            // Each carousel page's art: the hero's as the billboard draws it,
            // else the backdrop and the wordmark its listed item carries.
            var art: [String: (backdrop: URL?, wordmark: URL?)] = [:]
            for entry in shownContinued {
                let item = listed[entry.record.id] ?? Self.matchedItem(for: entry)
                art[entry.record.id] = (nil, await Self.wordmark(for: item))
            }
            for hero in heroes { art[hero.item.id] = (hero.backdropURL, hero.wordmarkURL) }
            let pages = AppleTopShelfContentBuilder.carouselItems(for: snapshot)
                .compactMap { page -> (id: String, backdrop: URL, wordmark: URL?)? in
                    let source = art[page.item.id]
                    guard let backdrop = source?.backdrop ?? page.imageURL else { return nil }
                    return (page.item.id, backdrop, source.flatMap(\.wordmark))
                }
            let directory = AppleTopShelfArtworkStore.directory(in: root)
            let names = await artwork.pictures(for: pages, in: directory)
            // A newer publish is already on its way and will draw the rest.
            try Task.checkCancellation()
            artwork.removeAll(in: directory, except: Set(names.values))
            snapshot = snapshot.withShelfImages(names)
        }
        // The trailers already saved go out with this snapshot; the rest are
        // fetched apart from it (`AppleTopShelfTrailerDownloads`) and added to
        // whatever snapshot is current when they land.
        guard let trailerFiles else { return try save(snapshot, to: url) }
        let shown = Set(AppleTopShelfContentBuilder.carouselItems(for: snapshot).map(\.item.id))
        let pages = heroes.compactMap { hero in
            hero.trailerQuery.flatMap { shown.contains(hero.item.id) ? (id: hero.item.id, query: $0) : nil }
        }
        let trailerDirectory = AppleTopShelfTrailerPolicy.directory(in: root)
        let plan = await trailerFiles.plan(for: pages, in: trailerDirectory)
        try Task.checkCancellation()
        trailerFiles.removeAll(in: trailerDirectory, except: plan.wanted)
        try save(snapshot.withShelfVideos(plan.saved), to: url)
        await trailerDownloads.fetch(plan, with: trailerFiles, in: trailerDirectory) { [self] fetched in
            try? await addShelfVideos(fetched, at: url)
        }
    }

    /// Adds newly saved trailers to the snapshot on disk, for the pages it
    /// still shows.
    private func addShelfVideos(_ names: [String: String], at url: URL) throws {
        let current = try JSONDecoder().decode(AppleTopShelfSnapshot.self, from: Data(contentsOf: url))
        let videos = Dictionary((current.heroes + current.continueWatching + current.topPicks).compactMap { item in
            item.shelfVideo.map { (item.id, $0) }
        }, uniquingKeysWith: { first, _ in first }).merging(names) { $1 }
        try save(current.withShelfVideos(videos), to: url)
    }

    func save(_ snapshot: AppleTopShelfSnapshot, to url: URL, notify: Bool = true) throws {
        let data = try JSONEncoder().encode(snapshot)
        #if os(iOS) || os(visionOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        // The tvOS extension opens the file separately, including while the app is inactive.
        try data.write(to: url, options: .atomic)
        #endif
        if notify { didChange() }
    }

    /// The in-progress records Continue Watching can open, resolved as on
    /// Discover; hidden ones are logged once. Without sources, every record.
    private static func openable(
        _ records: [AppleMediaRecord],
        sections: [AppleCatalogSection],
        sources: [AppleSource]?
    ) -> [AppleContinueWatchingResolver.Entry] {
        guard let sources else {
            return records.map { .init(record: $0, resolution: .notCatalog) }
        }
        let lookup = AppleCatalogSearchLookup(sections: sections, sources: sources)
        let entries = AppleContinueWatchingResolver.entries(records, in: [lookup])
        AppleContinueWatchingResolver.logHidden(entries)
        return entries.filter(\.resolution.isAvailable)
    }

    /// A record's landscape art when no shelf carries it under its own id:
    /// the listed item a merged source names, else the backdrop saved with
    /// the record. Never a rebuilt item's image-service fallback — its URL
    /// carries the IMDb id, which the snapshot deliberately never contains.
    private static func landscapeURL(for entry: AppleContinueWatchingResolver.Entry) -> URL? {
        if case .listed(let match) = entry.resolution, let url = landscapeURL(for: match.item) { return url }
        return AppleSystemArtworkPolicy.publicURL(entry.record.backdropURL)
    }

    /// The listed item a merged source names, for its genre and running time.
    private static func matchedItem(for entry: AppleContinueWatchingResolver.Entry) -> AppleCatalogItem? {
        if case .listed(let match) = entry.resolution { return match.item }
        return nil
    }

    /// The first non-empty catalog shelf, e.g. Cinemeta Popular for a fresh
    /// Stremio source. Ids are derived the same way `AppleMediaIngestion`
    /// would ingest the item, so the deep link resolves once the app has
    /// indexed the catalog.
    private static func topPicks(from sections: [AppleCatalogSection]) -> [AppleTopShelfSnapshot.Item] {
        guard let shelf = sections.first(where: { !$0.items.isEmpty }) else { return [] }
        return shelf.items.prefix(10).map { topPickItem(sourceID: shelf.sourceID, item: $0) }
    }

    private static func topPickItem(sourceID: AppleSource.ID, item: AppleCatalogItem) -> AppleTopShelfSnapshot.Item {
        let record = AppleMediaIngestion.catalogRecord(instanceID: sourceID, item: item)
        return catalogItem(id: record.id, title: record.title, kind: record.kind.rawValue, item: item)
    }

    /// A catalog title's page, for Top Picks and the Home hero.
    static func catalogItem(id: String, title: String, kind: String, item: AppleCatalogItem) -> AppleTopShelfSnapshot.Item {
        let display = URL(string: "openstream://media/\(id)?action=display")!
        let play = URL(string: "openstream://media/\(id)?action=play")
        return .init(
            id: id,
            title: title,
            kind: kind,
            artworkURL: AppleSystemArtworkPolicy.publicURL(item.posterURL)
                ?? AppleSystemArtworkPolicy.publicURL(item.backgroundURL),
            displayURL: display,
            playURL: play,
            landscapeArtworkURL: landscapeURL(for: item),
            summary: item.summary,
            genre: item.genres?.first,
            year: year(of: item),
            durationSeconds: item.runtimeMinutes.map { Double($0 * 60) }
        )
    }

    /// The wordmark the title page would draw: the listed item's own, else
    /// what the preview-assets cache already knows. Cache only, never a fetch.
    private static func wordmark(for item: AppleCatalogItem?) async -> URL? {
        guard let item else { return nil }
        if let logo = item.logoURL { return logo }
        let key = AppleStremioPreviewAssetsCache.key(type: item.type, mediaID: item.mediaID)
        return await AppleStremioPreviewAssetsCache.shared.entry(for: key)?.assets?.logoURL
    }

    private static func year(of item: AppleCatalogItem) -> Int? {
        item.year ?? item.releaseInfo.flatMap { Int($0.prefix(4)) }
    }

    /// The catalog item each Continue Watching record's card shows on
    /// Discover, for its backdrop and details: the item the record was
    /// ingested from, matched by record id as `AppleCatalogSearchLookup`
    /// does. Stops once every wanted id is found.
    private static func listedItems(for recordIDs: Set<String>,
                                    in sections: [AppleCatalogSection]) -> [String: AppleCatalogItem] {
        var found: [String: AppleCatalogItem] = [:]
        var remaining = recordIDs
        for section in sections where !remaining.isEmpty {
            for item in section.items where !remaining.isEmpty {
                let id = AppleMediaIngestion.catalogRecord(instanceID: section.sourceID, item: item).id
                // Only a match with a backdrop settles the id: the same record
                // can appear in a later shelf that has one (review of 3217b67).
                guard remaining.contains(id), landscapeURL(for: item) != nil else { continue }
                remaining.remove(id)
                found[id] = item
            }
        }
        return found
    }

    /// The card's landscape art (`AppleCatalogArtworkPolicy`, landscape):
    /// the title's backdrop. An episode still would win over it, as on the
    /// title page (`AppleEpisodeStillPolicy`), but a snapshot record is a
    /// title, never an episode, so there is no still to offer. The Cinemeta
    /// image-service fallback the card also tries is left out: its URL
    /// carries the IMDb id, which the snapshot deliberately never contains.
    private static func landscapeURL(for item: AppleCatalogItem) -> URL? {
        AppleSystemArtworkPolicy.publicURL(item.backgroundURL)
    }

    private static func item(_ record: AppleMediaRecord, progress: Double? = nil,
                             landscapeArtworkURL: URL? = nil,
                             catalogItem: AppleCatalogItem? = nil) -> AppleTopShelfSnapshot.Item {
        let display = URL(string: "openstream://media/\(record.id)?action=display")!
        let play = record.availability.count == 1
            ? URL(string: "openstream://media/\(record.id)?action=play")
            : nil
        return .init(
            id: record.id,
            title: record.title,
            kind: record.kind.rawValue,
            artworkURL: AppleSystemArtworkPolicy.publicURL(record.artworkURL),
            displayURL: display,
            playURL: play,
            progress: progress.map { min(max($0, 0), 1) },
            landscapeArtworkURL: landscapeArtworkURL,
            summary: record.summary ?? catalogItem?.summary,
            genre: catalogItem?.genres?.first,
            year: record.year ?? catalogItem.flatMap(year(of:)),
            durationSeconds: record.kind == .series ? nil : catalogItem?.runtimeMinutes.map { Double($0 * 60) }
        )
    }

    static func notify() {
        #if os(tvOS)
        TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
        #if os(iOS)
        // The same snapshot backs the iOS/iPadOS widgets, so a write has to
        // wake their timelines too. Without this a widget shows whatever it
        // rendered last until the system happens to refresh it.
        WidgetCenter.shared.reloadAllTimelines()
        #elseif os(visionOS)
        // `WidgetCenter` arrived on visionOS in 26.0 and this target deploys to
        // 2.0, so the unguarded call did not compile — which is why the whole
        // visionOS target had been failing to build (found 2026-09-17, the first
        // time anything in this audit built it). Gated rather than dropped, so
        // the reload still happens on a visionOS that has widgets.
        if #available(visionOS 26.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
}

/// What a Continue Watching widget should say when it has nothing to draw.
///
/// The two empty cases are not the same thing and used to read identically:
/// the widget said "Nothing in progress" whether the viewer had genuinely
/// finished everything *or* the app had never published a snapshot at all —
/// which on iPhone it never did, because the writers were `#if os(tvOS)` and
/// because publishing is opt-in under Privacy › Apple Services. Telling
/// someone with four half-watched shows that nothing is in progress is simply
/// untrue, and it hides the one setting that would fix it.
public enum AppleWidgetEmptyState: Equatable, Sendable {
    /// A snapshot exists and really is empty.
    case nothingInProgress
    /// No snapshot at all: not published, or the group container is unreadable.
    case notPublished

    public static func state(hasSnapshot: Bool) -> AppleWidgetEmptyState {
        hasSnapshot ? .nothingInProgress : .notPublished
    }

    /// Short enough for the small widget, and true in both cases.
    public var message: String {
        switch self {
        case .nothingInProgress: "Nothing in progress"
        case .notPublished: "Off in Settings › Privacy"
        }
    }
}
