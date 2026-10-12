import Foundation

public struct AppleLibraryTitle: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case movie, show, other }
    public let title: String
    public let year: Int?
    public let season: Int?
    public let episode: Int?
    public let kind: Kind
    public enum Role: String, Sendable { case feature, trailer, featurette, behindTheScenes, deletedScenes, sample }
    public var role: Role = .feature
    public var episodeEnd: Int? = nil
    /// ISO calendar date; no invented season/episode coordinates.
    public var airDate: String? = nil
    public var part: Int? = nil
    public var version: String? = nil
    public var confidence: Double = 0
    public var explicitIDs: [String: String] = [:]
    public var episodeNumbers: [Int] {
        guard role == .feature, let episode else { return [] }
        let end = episodeEnd ?? episode
        guard end >= episode, end - episode < 100 else { return [] }
        return Array(episode...end)
    }
}

public enum AppleLibraryTitleParser {
    public static func parse(name: String, parentPath: String = "") -> AppleLibraryTitle {
        let parents = parentPath.split(separator: "/").map(String.init)
        let stem = removingExtension(name)
        let full = (parents + [stem]).joined(separator: "/")
        let pair = captures(#"(?i)\bS(\d{1,3})[ ._-]*E(\d{1,4})\b|\b(\d{1,3})x(\d{1,4})\b"#, full)
        let season = pair.flatMap { Int($0[0]) ?? Int($0[2]) }
            ?? captures(#"(?i)\bSeason[ ._-]*(\d{1,3})\b"#, full).flatMap { Int($0[0]) }
        let episode = pair.flatMap { Int($0[1]) ?? Int($0[3]) }
            ?? captures(#"(?i)\bEpisode[ ._-]*(\d{1,4})\b"#, full).flatMap { Int($0[0]) }
        let rangeEnd = captures(#"(?i)\bS\d{1,3}[ ._-]*E\d{1,4}[ ._]*-[ ._]*(?:E)?(\d{1,4})\b"#, stem).flatMap { Int($0[0]) }
        let dateParts = captures(#"\b((?:19|20)\d{2})[._-](\d{2})[._-](\d{2})\b"#, stem)
        let airDate = dateParts.flatMap { values -> String? in
            guard let year = Int(values[0]), let month = Int(values[1]), let day = Int(values[2]) else { return nil }
            let calendar = Calendar(identifier: .gregorian)
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components),
                  calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
            return values.joined(separator: "-")
        }
        let role = fileRole(full)
        let isShow = airDate != nil || season != nil || episode != nil || parents.contains { $0.lowercased() == "shows" }
        let part = isShow ? nil : multipartMarker(stem)?.number
        var parsed = clean(stem)
        if prefersParent(stem) || (role != .feature && parents.contains { fileRole($0) != .feature }) { parsed = ("", nil) }
        if isShow {
            // Episode filenames may be “Pilot” or “Episode 2”; the series folder
            // keeps every local season on the same card.
            for parent in parents.reversed() {
                guard !["movies", "shows", "tv", "media"].contains(parent.lowercased()), !prefersParent(parent), !isDiscFolder(parent), fileRole(parent) == .feature else { continue }
                let candidate = clean(parent)
                if !candidate.0.isEmpty { parsed = candidate; break }
            }
        }
        if parsed.0.isEmpty || (prefersParent(stem) && !isShow) {
            parsed = ("", nil)
            for parent in parents.reversed() {
                guard !["movies", "shows", "tv", "media"].contains(parent.lowercased()), !prefersParent(parent), !isDiscFolder(parent), fileRole(parent) == .feature else { continue }
                let candidate = clean(parent)
                if !candidate.0.isEmpty { parsed = candidate; break }
            }
        }
        let success = !parsed.0.isEmpty
        var result = AppleLibraryTitle(title: success ? parsed.0 : String(name.prefix(24)) + (name.count > 24 ? "…" : ""),
            year: airDate == nil ? parsed.1 : nil, season: season, episode: episode, kind: success ? (isShow ? .show : .movie) : .other)
        result.episodeEnd = rangeEnd
        result.airDate = airDate
        result.role = role
        result.part = part
        result.version = captures(#"(?i)\b(\d{3,4}p|[48]K|(?:[a-z]+[ ._-]+)?edition)\b"#, stem)?.first?.lowercased()
        result.confidence = rangeEnd.map { $0 < (episode ?? 0) || $0 - (episode ?? 0) >= 100 } == true ? 0 : !success ? 0 : (episode != nil || airDate != nil ? 1 : (isShow ? 0.4 : (parsed.1 != nil ? 0.9 : 0.5)))
        if let id = captures(#"(?i)\b(tt\d{7,10})\b"#, full)?.first { result.explicitIDs["imdb"] = id.lowercased() }
        if let id = captures(#"(?i)\btmdb[ -](\d+)\b"#, full)?.first { result.explicitIDs["tmdb"] = id }
        return result
    }

    public static func parse(_ item: AppleLibraryItem) -> AppleLibraryTitle {
        parse(name: item.name, parentPath: (item.relativePath as NSString).deletingLastPathComponent)
    }

    private static func fileRole(_ text: String) -> AppleLibraryTitle.Role {
        let normalized = text.lowercased().replacingOccurrences(of: #"[._-]+"#, with: " ", options: .regularExpression)
        for (pattern, role) in [(#"\bbehind the scenes\b"#, AppleLibraryTitle.Role.behindTheScenes),
            (#"\bdeleted scenes\b"#, .deletedScenes), (#"\bfeaturettes?\b"#, .featurette),
            (#"\btrailers?\b"#, .trailer), (#"\bsamples?\b"#, .sample)] {
            if normalized.range(of: pattern + #"(?:/|$|\s+\d{3,4}p\b)"#, options: .regularExpression) != nil { return role }
        }
        return .feature
    }

    private static func removingExtension(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        return AppleLibraryScanner.supportedExtensions.contains(ext) ? (name as NSString).deletingPathExtension : name
    }

    private static func isHash(_ name: String) -> Bool {
        let value = removingExtension(name).replacingOccurrences(of: "-", with: "")
        return value.count >= 16 && value.allSatisfy { $0.isHexDigit }
    }

    /// A disc rip keeps the playlist's number as its filename — `00526.m2ts`
    /// beside `Fantastic Mr. Fox (2009)`, or `VTS_01_1.VOB` from a DVD. The
    /// number is not a title and the folder above it is, so these defer to the
    /// parent exactly like a hashed name does. A film whose *title* is a number
    /// (1992, 2073, 1917) is unaffected: its filename carries the year and the
    /// release tags too, so the stem is never digits alone.
    private static func isDiscPlaylist(_ name: String) -> Bool {
        // Not `removingExtension`: a disc rip may carry a container the
        // scanner does not list (`.VOB`), and the shape is what matters.
        let value = name.replacingOccurrences(of: #"\.[A-Za-z0-9]{2,4}$"#, with: "", options: .regularExpression)
        if value.count >= 2, value.allSatisfy(\.isNumber) { return true }
        return value.range(of: #"(?i)^(?:VTS[_ ]\d{1,3}[_ ]\d{1,3}|title[_ ]?t?\d{1,3})$"#,
                           options: .regularExpression) != nil
    }

    private static func prefersParent(_ name: String) -> Bool {
        isHash(name) || isDiscPlaylist(name)
    }

    private static func isDiscFolder(_ name: String) -> Bool {
        name.range(of: #"(?i)^(?:cd|disc|disk|part)[ ._-]*\d{1,2}$"#, options: .regularExpression) != nil
    }

    /// Compact tags are file parts. Separated “Part 1” / “Part.1” before
    /// a release year belongs to the title (for example Deathly Hallows).
    /// Separated part tags after a year remain explicit file parts.
    private static func multipartMarker(_ raw: String) -> (range: Range<String.Index>, number: Int)? {
        let pattern = #"(?i)\b(cd|disc|disk|part)([ ._-]*)(\d{1,2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for match in regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            guard let range = Range(match.range, in: raw),
                  let marker = Range(match.range(at: 1), in: raw),
                  let separator = Range(match.range(at: 2), in: raw),
                  let digits = Range(match.range(at: 3), in: raw),
                  let number = Int(raw[digits]), number > 0 else { continue }
            if raw[marker].lowercased() == "part", !raw[separator].isEmpty,
               String(raw[..<range.lowerBound]).range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) == nil {
                continue
            }
            return (range, number)
        }
        return nil
    }

    private static func clean(_ raw: String) -> (String, Int?) {
        let titleStem: String
        if let marker = multipartMarker(raw) { titleStem = raw.replacingCharacters(in: marker.range, with: " ") }
        else { titleStem = raw }
        var value = titleStem.replacingOccurrences(of: #"^(?:\s*\[[^\]]*\]\s*)+"#, with: "", options: .regularExpression)
        // Tracker stamps: "www.UIndex.org    -    Hey Arnold The Movie 2002…".
        // The mandatory " - " after the domain is what keeps this off real
        // titles — "W.A.R - The Movie" and "Dr.No.1962" do not match.
        value = value.replacingOccurrences(
            of: #"(?i)^\s*(?:www[._])?[a-z0-9-]+[._][a-z]{2,6}\s*-+\s*"#,
            with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[._]+"#, with: " ", options: .regularExpression)
        let year = captures(#"(?<=.)(?<!\d)\b((?:19|20)\d{2})\b"#, value).flatMap { Int($0[0]) }
        // Cut at release metadata, keeping ordinary title words such as “Atmosphere”.
        let boundary = #"(?i)\b(?:S\d{1,3}[ -]*E\d{1,4}|\d{1,3}x\d{1,4}|Season\s*\d+|Episode\s*\d+|(?:19|20)\d{2}|\d{3,4}p|[48]K|x26[45]|h[ -]?26[45]|HEVC|AVC|WEB[ -]?(?:DL|Rip)|Blu[ -]?Ray|BRRip|BDRip|HDR10\+?|HDR|DV|DOVI|Atmos|DTS|DDP|AAC|AC3|EAC3|REMUX|PROPER|REPACK|(?:[a-z]+[ -]+)?edition|(?:trailer|featurette|behind[ -]the[ -]scenes|deleted[ -]scenes|sample)(?=\s*$)|\{?(?:imdb|tmdb)[ -])\b"#
        if let range = value.range(of: boundary, options: .regularExpression) {
            // A numeric title (1917, 2001) is not a release year at the beginning.
            if range.lowerBound != value.startIndex || Int(value[range]) == nil {
                value = String(value[..<range.lowerBound])
            } else {
                let suffix = String(value[range.upperBound...])
                if let next = suffix.range(of: boundary, options: .regularExpression) {
                    value = String(value[range]) + String(suffix[..<next.lowerBound])
                }
            }
        }
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-()[]")))
        return (value, year == Int(value) ? nil : year)
    }

    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
