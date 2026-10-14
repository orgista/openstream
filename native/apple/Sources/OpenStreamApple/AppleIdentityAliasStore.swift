import Foundation

/// Derived identity evidence; never changes the keys in playback or backup blobs.
struct AppleIdentityAliasTable: Codable, Equatable, Sendable {
    static let version = 1
    var classes: [String: [String]] = [:]

    private enum CodingKeys: String, CodingKey { case v, classes }

    init(classes: [String: [String]] = [:]) {
        self.classes = classes.mapValues { Array(Set($0)).sorted() }
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .v) == Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .v, in: values, debugDescription: "Unsupported alias version")
        }
        self.init(classes: try values.decode([String: [String]].self, forKey: .classes))
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.version, forKey: .v)
        try values.encode(classes.mapValues { Array(Set($0)).sorted() }, forKey: .classes)
    }

    func members(of storageKey: String) -> [String] {
        let index = connectedIndex()
        guard let id = index.classByMember[storageKey] else { return [storageKey] }
        return [storageKey] + (index.membersByClass[id] ?? []).filter { $0 != storageKey }
    }

    /// Overlapping evidence classes share one read component. The first sorted
    /// class label represents that component; persisted classes remain intact.
    func classID(of storageKey: String) -> String? { connectedIndex().classByMember[storageKey] }

    fileprivate func connectedIndex() -> (classByMember: [String: String], membersByClass: [String: [String]]) {
        var classesByMember: [String: [String]] = [:]
        for (id, members) in classes {
            for member in members { classesByMember[member, default: []].append(id) }
        }
        var visited = Set<String>()
        var classByMember: [String: String] = [:]
        var membersByClass: [String: [String]] = [:]
        for representative in classes.keys.sorted() where visited.insert(representative).inserted {
            var pending = [representative]
            var position = 0
            var members = Set<String>()
            while position < pending.count {
                let id = pending[position]
                position += 1
                for member in classes[id] ?? [] where members.insert(member).inserted {
                    classByMember[member] = representative
                    for linked in classesByMember[member] ?? [] where visited.insert(linked).inserted {
                        pending.append(linked)
                    }
                }
            }
            membersByClass[representative] = members.sorted()
        }
        return (classByMember, membersByClass)
    }

    @discardableResult mutating func record(classID: String, members: [String]) -> Bool {
        let combined = Array(Set((classes[classID] ?? []) + members)).sorted()
        guard combined != classes[classID], !combined.isEmpty else { return false }
        classes[classID] = combined
        return true
    }
}

enum AppleIdentityAliasResolution {
    static func progress(keys: [String], in map: [String: ApplePlaybackProgress]) -> ApplePlaybackProgress? {
        keys.compactMap { map[$0] }.reduce(nil) { result, value in
            result.map { ApplePlaybackConvergence.freshest($0, value) } ?? value
        }
    }

    static func history(keys: [String], watched: [String: Date], tombstones: [String: Date]) -> (watched: Date?, tombstone: Date?) {
        guard let asked = keys.first else { return (nil, nil) }
        var history = AppleWatchedHistory()
        for key in keys {
            history.merge(watched: watched[key].map { [asked: $0] } ?? [:],
                          tombstones: tombstones[key].map { [asked: $0] } ?? [:])
        }
        return (history.watched[asked], history.tombstones[asked])
    }

    static func terminals(keys: [String], in map: [String: ApplePlaybackTerminalEvents]) -> ApplePlaybackTerminalEvents? {
        keys.compactMap { map[$0] }.reduce(nil) { result, value in result.map { $0.merging(value) } ?? value }
    }

    static func latestDate(keys: [String], in map: [String: Date]) -> Date? {
        keys.compactMap { map[$0] }.max()
    }
}

@MainActor final class AppleIdentityAliasStore {
    static let enabledKey = "openstream.identity.aliases.enabled"
    private let defaults: UserDefaults
    private let blobs: ApplePlaybackBlobStorage
    private let key: String
    private var decodedData: Data?
    private var hasDecoded = false
    private var table = AppleIdentityAliasTable()
    private var classByMember: [String: String] = [:]
    private var membersByClass: [String: [String]] = [:]
    private var didTraceInvalidMember = false
    private var didTracePositionalConflict = false

    init(defaults: UserDefaults = .standard, namespace: String = AppleTasteNamespace.local, blobDirectory: URL? = nil) {
        self.defaults = defaults
        blobs = ApplePlaybackBlobStorage.storage(defaults: defaults, directory: blobDirectory)
        key = AppleTasteNamespace.key("openstream.identity.aliases.v1", namespace: namespace)
    }

    var isEnabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
    var blobData: Data? { blobs.data(forKey: key) }

    private func load() {
        let data = blobData
        guard !hasDecoded || data != decodedData else { return }
        hasDecoded = true
        decodedData = data
        table = data.flatMap { try? JSONDecoder().decode(AppleIdentityAliasTable.self, from: $0) } ?? .init()
        if table.classes.values.joined().contains(where: { !ApplePlaybackIdentity.isStorageKey($0) }) {
            traceInvalidMember()
            table.classes = table.classes.compactMapValues { members in
                let valid = members.filter { ApplePlaybackIdentity.isStorageKey($0) }
                return valid.isEmpty ? nil : valid
            }
        }
        let index = table.connectedIndex()
        classByMember = index.classByMember
        membersByClass = index.membersByClass
    }

    func members(of storageKey: String) -> [String] {
        guard isEnabled else { return [storageKey] }
        load()
        guard let id = classByMember[storageKey] else { return [storageKey] }
        return [storageKey] + (membersByClass[id] ?? []).filter { $0 != storageKey }
    }

    func record(classID: String, members: [String]) {
        record([(classID: classID, members: members)])
    }

    /// Apply the whole pass before encoding and persisting the derived table.
    func record(_ entries: [(classID: String, members: [String])]) {
        guard !entries.isEmpty else { return }
        load()
        // Index direct le: ownership once. A connected component's representative
        // can be a li: label after a rename; it must not hide positional ownership.
        var positionalOwners: [String: String] = [:]
        for id in table.classes.keys.sorted() where id.hasPrefix("le:") {
            let fileKey = ApplePlaybackIdentity.storageKey(for: String(id.dropFirst(3)))
            for member in table.classes[id] ?? [] where member != fileKey {
                positionalOwners[member] = positionalOwners[member] ?? id
            }
        }
        var changed = false
        for entry in entries {
            let fileKey = entry.classID.hasPrefix("le:")
                ? ApplePlaybackIdentity.storageKey(for: String(entry.classID.dropFirst(3))) : nil
            let valid = entry.members.filter { member in
                guard ApplePlaybackIdentity.isStorageKey(member) else {
                    traceInvalidMember()
                    return false
                }
                if entry.classID.hasPrefix("le:"), member != fileKey {
                    if let owner = positionalOwners[member], owner != entry.classID {
                        if !didTracePositionalConflict {
                            didTracePositionalConflict = true
                            AppleInteractionTrace.record(.failure, "Identity alias rejected shared positional episode key")
                        }
                        return false
                    }
                    positionalOwners[member] = entry.classID
                }
                return true
            }
            if table.record(classID: entry.classID, members: valid) { changed = true }
        }
        guard changed else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(table) else { return }
        blobs.set(data, forKey: key)
        // Rebuild the reverse map on the next lookup, once per distinct blob.
        hasDecoded = false
    }

    private func traceInvalidMember() {
        guard !didTraceInvalidMember else { return }
        didTraceInvalidMember = true
        AppleInteractionTrace.record(.failure, "Identity alias rejected invalid storage key")
    }
}
