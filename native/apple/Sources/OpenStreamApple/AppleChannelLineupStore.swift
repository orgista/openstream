import Foundation
import Synchronization
import UniformTypeIdentifiers

public extension UTType {
    static let openStreamLineup = UTType(exportedAs: "com.orgista.openstream.lineup", conformingTo: .json)
}

public final class AppleChannelLineupStore: Sendable {
    public static let shared = AppleChannelLineupStore()
    public static let didChange = Notification.Name("openstream.lineup.changed")

    private struct State {
        var file: AppleChannelLineupFile?
        var data: Data?
    }

    private let directory: URL
    private let state: Mutex<State>

    public init(directory: URL = AppleChannelLineupStore.defaultDirectory) {
        self.directory = directory
        let data = try? Data(contentsOf: directory.appendingPathComponent("current.oslineup"))
        let file = data.flatMap { try? AppleChannelLineupFile.decode($0) }
        state = Mutex(State(file: file, data: file == nil ? nil : data))
    }

    public static var defaultDirectory: URL {
        let manager = FileManager.default
        return manager.containerURL(forSecurityApplicationGroupIdentifier: AppleTopShelfSnapshotWriter.appGroup)
            .map { $0.appendingPathComponent("Library/Application Support/Lineups", isDirectory: true) }
            ?? fallbackDirectory
    }

    static var fallbackDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenStream", isDirectory: true)
            .appendingPathComponent("Library/Application Support/Lineups", isDirectory: true)
    }

    public var current: AppleChannelLineupFile? { state.withLock { $0.file } }
    public var data: Data? { state.withLock { $0.data } }

    func discardAfterReset() {
        state.withLock { $0 = State(file: nil, data: nil) }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    public func importData(_ data: Data) throws {
        let file = try AppleChannelLineupFile.decode(data)
        let encoded = try JSONEncoder().encode(file)
        guard encoded.count <= AppleChannelLineupFile.maximumBytes else { throw AppleChannelLineupError.tooLarge }
        let changed = try state.withLock { state in
            let url = directory.appendingPathComponent("current.oslineup")
            guard state.file != file || !FileManager.default.fileExists(atPath: url.path) else { return false }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try encoded.write(to: url, options: .atomic)
            } catch { throw AppleChannelLineupError.couldNotSave }
            state = State(file: file, data: encoded)
            return true
        }
        if changed { NotificationCenter.default.post(name: Self.didChange, object: self) }
    }

    public func importFile(_ url: URL) throws {
        let access = AppleSecurityScopedAccess(url: url)
        defer { withExtendedLifetime(access) {} }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= AppleChannelLineupFile.maximumBytes else { throw AppleChannelLineupError.tooLarge }
        try importData(Data(contentsOf: url))
    }

    public func importURL(_ url: URL) async throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { throw AppleChannelLineupError.couldNotDownload }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await AppleBoundedHTTPDataLoader.load(request,
                maximumBytes: AppleChannelLineupFile.maximumBytes, redirectPolicy: .secureHTTPOnly)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw AppleChannelLineupError.couldNotDownload
            }
            try Task.checkCancellation()
            try importData(data)
        } catch AppleBoundedHTTPError.responseTooLarge { throw AppleChannelLineupError.tooLarge }
        catch let error as AppleChannelLineupError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            throw AppleChannelLineupError.couldNotDownload
        }
    }
}
