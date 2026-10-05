import Foundation
import Observation

@MainActor
@Observable
public final class AppleIPTVGuideStore {
    private let loader: AppleIPTVGuideLoader
    private let diskCache: AppleIPTVGuideDiskCache
    public private(set) var channelNames: [String: [String: String]] = [:]
    public var channelDisplayNames: [String: String] = [:]
    public var manualChannelMapping: [String: String] = [:] {
        didSet {
            guard manualChannelMapping != oldValue else { return }
            restoredKeys.removeAll()
            caches.removeAll()
            revision &+= 1
        }
    }
    private var restoredKeys = Set<String>()

    private struct ChannelCache: Sendable {
        let programmes: [AppleIPTVProgramme]
        let fetchTime: Date
    }

    private enum Configuration: Equatable {
        case xmltv(URL, [String: String], Double, [String: Double], Double)
        case xtream(URL, String, String, Double)
    }

    private var caches: [String: ChannelCache] = [:]
    private var configurations: [String: Configuration] = [:]
    private var inFlight = Set<String>()
    private let expiry: TimeInterval = 15 * 60

    /// Bumped whenever the programme caches change. Views key their derived
    /// work (the Apple TV grid model) on it instead of diffing the guide.
    public private(set) var revision = 0

    /// `guide(for:)` is called from view bodies, which re-run for reasons that
    /// have nothing to do with the guide; grouping and sorting every programme
    /// each time made the Apple TV Live tab crawl. The last answer is kept and
    /// reused while neither the channel list nor `revision` has moved. Ignored
    /// by observation so filling it during a body pass notifies nobody.
    @ObservationIgnored private var guideCache: (ids: [String], revision: Int, guide: AppleIPTVGuide)?

    public init(loader: AppleIPTVGuideLoader = AppleIPTVGuideLoader(), diskCache: AppleIPTVGuideDiskCache = .shared) {
        self.loader = loader
        self.diskCache = diskCache
    }

    public func configure(xmltvURL: URL?, sourceID: UUID? = nil, channelMapping: [String: String] = [:], defaultOffsetHours: Double = 0, channelShifts: [String: Double] = [:], timeShiftHours: Double = 0) {
        setConfiguration(xmltvURL.map { .xmltv($0, channelMapping, defaultOffsetHours, channelShifts, timeShiftHours) }, key: sourceID?.uuidString ?? "")
    }

    public func configure(xtreamBase: URL, username: String, password: String, sourceID: UUID? = nil, timeShiftHours: Double = 0) {
        let key = sourceID?.uuidString ?? ""
        setConfiguration(.xtream(xtreamBase, username, password, timeShiftHours), key: key)
        channelNames[key] = Dictionary(uniqueKeysWithValues: channelDisplayNames.compactMap { id, name in
            guard key.isEmpty || id.hasPrefix(key + ":"),
                  let raw = AppleIPTVGuideMatching.xtreamID(id, sourceKey: key) else { return nil }
            return (String(raw), name)
        })
    }

    private func setConfiguration(_ value: Configuration?, key: String) {
        guard configurations[key] != value else { return }
        configurations[key] = value
        channelNames[key] = nil
        restoredKeys.remove(key)
        caches = caches.filter { cacheKey, _ in
            key.isEmpty ? cacheKey.contains(":") : !cacheKey.hasPrefix(key + ":")
        }
        revision &+= 1
    }

    public func retainSources(_ ids: Set<UUID>) {
        let keys = Set(ids.map(\.uuidString))
        configurations = configurations.filter { $0.key.isEmpty || keys.contains($0.key) }
        caches = caches.filter { key, _ in
            guard let prefix = key.split(separator: ":").first, UUID(uuidString: String(prefix)) != nil else { return true }
            return keys.contains(String(prefix))
        }
        revision &+= 1
    }

    /// Channel ids whose panel keeps an archive; their Xtream listings are
    /// read with the past included. Set by the Live tab from the lineup.
    public var archiveChannelIDs: Set<String> = []

    public func refreshVisible(channelIDs: Set<String>) async {
        let now = Date()
        for key in configurations.keys.sorted() {
            guard let configuration = configurations[key], restoredKeys.insert(key).inserted else { continue }
            let snapshot = await diskCache.snapshot(key: diskKey(key, configuration))
            let saved = snapshot.programmes
            guard configurations[key] == configuration, !Task.isCancelled else { continue }
            if case .xmltv = configuration { channelNames[key] = snapshot.channelNames }
            for (id, programmes) in Dictionary(grouping: saved, by: \.channelID) where caches[id] == nil {
                caches[id] = ChannelCache(programmes: programmes, fetchTime: now)
            }
            if !saved.isEmpty { revision &+= 1 }
        }
        let stale = channelIDs.filter { id in
            !inFlight.contains(id) && (caches[id].map { now.timeIntervalSince($0.fetchTime) >= expiry } ?? true)
        }
        let groups = Dictionary(grouping: stale) { id -> String in
            let prefix = String(id.split(separator: ":").first ?? "")
            return UUID(uuidString: prefix) == nil ? "" : prefix
        }
        for key in groups.keys.sorted() {
            guard !Task.isCancelled, let configuration = configurations[key] else { continue }
            let limit: Int
            if case .xmltv = configuration { limit = AppleIPTVClient.maximumChannels } else { limit = 50 }
            var requested = Set(groups[key] ?? [])
            if case .xmltv(_, let mapping, _, _, _) = configuration {
                requested.formUnion(mapping.keys)
                requested.formUnion(channelDisplayNames.keys.filter { key.isEmpty || $0.hasPrefix(key + ":") })
            }
            let ids = Array(requested.sorted().prefix(limit))
            inFlight.formUnion(ids)
            defer { inFlight.subtract(ids) }
            do {
                let guide: AppleIPTVGuide
                var providerIDs: [String: String] = [:]
                switch configuration {
                case .xmltv(let url, let mapping, let offset, _, _):
                    guide = try await loader.load(xmltvURL: url, defaultOffsetHours: offset)
                    guard !Task.isCancelled, configurations[key] == configuration else { continue }
                    channelNames[key] = guide.channelNames
                    for id in ids {
                        if let manual = manualChannelMapping[id] { providerIDs[id] = manual }
                        else if let exact = mapping[id], !guide.programmes(channelID: exact, in: DateInterval(start: .distantPast, end: .distantFuture)).isEmpty { providerIDs[id] = exact }
                        else { providerIDs[id] = guide.channelMatchIndex.match(id: mapping[id] ?? id,
                            name: channelDisplayNames[id] ?? id)?.channelID ?? mapping[id] ?? id }
                    }
                case .xtream(let base, let user, let pass, _):
                    for id in ids {
                        if let value = AppleIPTVGuideMatching.xtreamID(id, manualID: manualChannelMapping[id], sourceKey: key) {
                            providerIDs[id] = String(value)
                        }
                    }
                    guard !providerIDs.isEmpty else { continue }
                    let archive = Set(providerIDs.filter { archiveChannelIDs.contains($0.key) }.values.compactMap(Int.init))
                    guide = try await loader.load(xtreamBase: base, username: user, password: pass,
                        streamIDs: providerIDs.values.compactMap(Int.init).sorted(), archiveStreamIDs: archive)
                }
                guard !Task.isCancelled, configurations[key] == configuration else { continue }
                for (index, id) in ids.enumerated() {
                    if index.isMultiple(of: 100) {
                        if index > 0 { revision &+= 1 }
                        await Task.yield()
                        guard !Task.isCancelled, configurations[key] == configuration else { break }
                    }
                    let shift: Double
                    switch configuration {
                    case .xmltv(_, _, _, let shifts, let correction): shift = (shifts[id] ?? 0) + correction
                    case .xtream(_, _, _, let correction): shift = correction
                    }
                    guard let providerID = providerIDs[id] else { continue }
                    let programmes = guide.programmes(channelID: providerID,
                        in: DateInterval(start: .distantPast, end: .distantFuture)).map { programme in
                        AppleIPTVProgramme(id: "\(id):\(programme.id)", channelID: id, title: programme.title,
                            subtitle: programme.subtitle, description: programme.description, start: programme.start.addingTimeInterval(shift * 3600),
                            end: programme.end.addingTimeInterval(shift * 3600), category: programme.category, isLive: programme.isLive)
                    }
                    caches[id] = ChannelCache(programmes: programmes, fetchTime: now)
                }
                guard !Task.isCancelled, configurations[key] == configuration else { continue }
                revision &+= 1
                let sourceProgrammes = caches.filter { cacheKey, _ in
                    key.isEmpty ? !cacheKey.contains(":") : cacheKey.hasPrefix(key + ":")
                }.values.flatMap(\.programmes)
                await diskCache.store(sourceProgrammes, key: diskKey(key, configuration), channelNames: channelNames[key] ?? [:])
                let filled = ids.filter { !(caches[$0]?.programmes.isEmpty ?? true) }.count
                appleTrace("guide loaded: \(filled)/\(ids.count) visible channels have programmes")
            } catch {
                // Keep previous data, and allow the next visible refresh to retry.
                // Cancellation or a failed provider must not cache an empty guide.
                appleTrace("guide load failed for \(ids.count) channels: \(AppleDiagnosticRedactor.redact(String(describing: error)))")
            }
        }
    }

    private func diskKey(_ source: String, _ configuration: Configuration) -> String {
        switch configuration {
        case .xmltv(let url, let mapping, let offset, let shifts, let correction):
            return source + "|" + url.absoluteString + "|" + String(offset) + "|" + String(correction)
                + "|" + manualChannelMapping.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: "|")
                + "|" + mapping.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: "|")
                + "|" + shifts.sorted { $0.key < $1.key }.map { $0.key + "=" + String($0.value) }.joined(separator: "|")
        case .xtream(let url, let user, let password, let correction):
            return source + "|" + url.absoluteString + "|" + user + "|" + password + "|" + String(correction)
        }
    }

    public func nowAndNext(channelID: String, at time: Date = Date()) -> (now: AppleIPTVProgramme?, next: AppleIPTVProgramme?) {
        guide(for: [channelID]).nowAndNext(channelID: channelID, at: time)
    }

    public func programmes(channelID: String, in interval: DateInterval) -> [AppleIPTVProgramme] {
        guide(for: [channelID]).programmes(channelID: channelID, in: interval)
    }

    public func guide(for channelIDs: some Sequence<String>) -> AppleIPTVGuide {
        var seen = Set<String>()
        let ids = channelIDs.filter { seen.insert($0).inserted }
        let revision = revision
        if let cache = guideCache, cache.revision == revision, cache.ids == ids { return cache.guide }
        let guide = AppleIPTVGuide(programmes: ids.flatMap { caches[$0]?.programmes ?? [] })
        guideCache = (ids, revision, guide)
        return guide
    }
}
