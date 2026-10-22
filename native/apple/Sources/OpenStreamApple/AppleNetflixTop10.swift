import Foundation

public struct AppleNetflixTop10Entry: Codable, Sendable, Equatable {
    public let rank: Int
    public let title: String
    public let seasonTitle: String?
    public let category: String

    public init(rank: Int, title: String, seasonTitle: String?, category: String) {
        self.rank = rank
        self.title = title
        self.seasonTitle = seasonTitle
        self.category = category
    }
}

public struct AppleNetflixTop10Week: Codable, Sendable, Equatable {
    public let week: Date
    public let films: [AppleNetflixTop10Entry]
    public let tv: [AppleNetflixTop10Entry]

    public init(week: Date, films: [AppleNetflixTop10Entry], tv: [AppleNetflixTop10Entry]) {
        self.week = week
        self.films = films
        self.tv = tv
    }
}

/// Netflix publishes the chart once a week as one file of every week and country (tens of MB).
/// One shared client keeps the parsed week on disk and asks again at most once a day, with the
/// file's validators, so a launch draws the rows from disk instead of re-reading the whole file.
public actor AppleNetflixTop10Client {
    static let shared = AppleNetflixTop10Client(session: .shared, fileURL: FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "OpenStream", directoryHint: .isDirectory).appending(path: "netflix-top10-v1.json"))
    static let refreshInterval: TimeInterval = 86_400

    private struct Stored: Codable {
        let country: String
        let week: AppleNetflixTop10Week
        let fetchedAt: Date
        let entityTag: String?
        let lastModified: String?
    }

    private let session: URLSession
    private let country: String
    private let fileURL: URL?
    private var stored: Stored?
    private var didReadDisk = false
    /// Discover asks again when it remounts or the setting flips; a second
    /// caller waits for the download already running instead of parsing the
    /// file twice. The download is unstructured, so it runs to the end even
    /// when a caller is cancelled.
    private var inFlight: Task<AppleNetflixTop10Week, Error>?

    public init(session: URLSession, country: String = "US", fileURL: URL? = nil) {
        self.session = session
        self.country = country.uppercased()
        self.fileURL = fileURL
    }

    /// The week kept on disk by an earlier launch, without asking the network, so the rows can draw at launch while
    /// `latestWeek` waits.
    func storedWeek() -> AppleNetflixTop10Week? {
        readDiskOnce()
        return stored?.week
    }

    public func latestWeek(now: Date = .now) async throws -> AppleNetflixTop10Week {
        readDiskOnce()
        if let stored, now.timeIntervalSince(stored.fetchedAt) < Self.refreshInterval {
            return stored.week
        }
        if let inFlight { return try await inFlight.value }
        let task = Task { try await download(now: now) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func readDiskOnce() {
        guard !didReadDisk else { return }
        didReadDisk = true
        stored = fileURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
            .flatMap { $0.country == country ? $0 : nil }
    }

    private func download(now: Date) async throws -> AppleNetflixTop10Week {
        guard let url = URL(string: "https://www.netflix.com/tudum/top10/data/all-weeks-countries.tsv") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        request.setValue("OpenStream/\(version) (+https://orgista.com/support)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.netflix.com/tudum/top10/", forHTTPHeaderField: "Referer")
        if let stored {
            request.setValue(stored.entityTag, forHTTPHeaderField: "If-None-Match")
            request.setValue(stored.lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode == 304, let previous = stored {
                save(Stored(country: country, week: previous.week, fetchedAt: now,
                            entityTag: previous.entityTag, lastModified: previous.lastModified))
                return previous.week
            }
            guard (200...299).contains(response.statusCode) else { throw URLError(.badServerResponse) }
            var parser = AppleNetflixTop10Parser(country: country)
            var line: [UInt8] = []
            line.reserveCapacity(1024)
            var received = 0
            for try await byte in bytes {
                received += 1
                guard received <= 64 * 1024 * 1024, line.count < 32 * 1024 else {
                    throw URLError(.dataLengthExceedsMaximum)
                }
                if byte == 10 {
                    if !parser.isOtherCountry(line) { try parser.consume(String(decoding: line, as: UTF8.self)) }
                    line.removeAll(keepingCapacity: true)
                } else { line.append(byte) }
            }
            if !line.isEmpty { try parser.consume(String(decoding: line, as: UTF8.self)) }
            let week = try parser.finish()
            save(Stored(country: country, week: week, fetchedAt: now,
                        entityTag: response.value(forHTTPHeaderField: "ETag"),
                        lastModified: response.value(forHTTPHeaderField: "Last-Modified")))
            return week
        } catch {
            // The last good week stays on screen; the failure only goes to the trace.
            if let stored {
                AppleInteractionTrace.record(.network, "top 10 refresh failed \(appleErrorLabel(error)), kept week of \(stored.fetchedAt.formatted(.iso8601))")
                return stored.week
            }
            throw error
        }
    }

    private func save(_ value: Stored) {
        stored = value
        guard let fileURL, let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Keeps only the newest country's twenty ranked entries while reading a TSV.
/// The feed is not assumed to be sorted by week or country.
struct AppleNetflixTop10Parser {
    private var columns: [String: Int] = [:]
    private var newestWeek = ""
    private var films: [Int: AppleNetflixTop10Entry] = [:]
    private var shows: [Int: AppleNetflixTop10Entry] = [:]
    let country: String

    private let countryCode: [UInt8]

    init(country: String) {
        self.country = country
        countryCode = Array(country.uppercased().utf8)
    }

    /// Most rows are other countries; reading the country cell from the raw
    /// bytes skips them without building a String per cell (the full parse was
    /// ~1.5 s of CPU on an Apple TV 4K, 2026-10-16).
    func isOtherCountry(_ line: [UInt8]) -> Bool {
        guard let index = columns["country_iso2"] else { return false }
        var cell = 0, start = 0, end = line.count
        for position in line.indices where line[position] == 9 {
            if cell == index { end = position; break }
            cell += 1
            start = position + 1
        }
        guard cell == index else { return false }
        return !line[start..<end].lazy.map { (97...122).contains($0) ? $0 - 32 : $0 }.elementsEqual(countryCode)
    }

    mutating func consume(_ line: String) throws {
        guard !line.isEmpty else { return }
        let cells = line.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
        if columns.isEmpty {
            for (index, name) in cells.enumerated() { columns[name] = index }
            guard ["country_iso2", "week", "category", "weekly_rank", "show_title", "season_title"]
                .allSatisfy({ columns[$0] != nil }) else { throw URLError(.cannotParseResponse) }
            return
        }
        func value(_ key: String) -> String {
            guard let index = columns[key], cells.indices.contains(index) else { return "" }
            return cells[index]
        }
        guard value("country_iso2").uppercased() == country.uppercased() else { return }
        let week = value("week")
        guard week.count == 10, week >= newestWeek,
              let rank = Int(value("weekly_rank")), (1...10).contains(rank),
              ["Films", "TV"].contains(value("category")) else { return }
        let title = value("show_title").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        if week > newestWeek { newestWeek = week; films = [:]; shows = [:] }
        let season = value("season_title").trimmingCharacters(in: .whitespaces)
        let isMovie = value("category") == "Films"
        let entry = AppleNetflixTop10Entry(rank: rank, title: title,
            seasonTitle: season.isEmpty || season == "N/A" ? nil : season,
            category: isMovie ? "movie" : "series")
        if isMovie { if films[rank] == nil { films[rank] = entry } }
        else if shows[rank] == nil { shows[rank] = entry }
    }

    func finish() throws -> AppleNetflixTop10Week {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let week = formatter.date(from: newestWeek), formatter.string(from: week) == newestWeek else {
            throw URLError(.cannotParseResponse)
        }
        return AppleNetflixTop10Week(week: week,
            films: (1...10).compactMap { films[$0] }, tv: (1...10).compactMap { shows[$0] })
    }
}
