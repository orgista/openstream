import Foundation

/// Whether a release name is for the title being played at all.
///
/// Owner, 2026-09-17, "episode 1 still loads the wrong show": Torrentio
/// answered `tt31091039:1:1` (The Secret Lives of Mormon Wives) with twelve
/// streams, seven of them for *other* shows — "Secret Lives of Gypsy Wives
/// S01E01", "Secret Sex Lives of Tyrants S01E01". Every one of them states
/// S01E01, so the episode rule cannot tell them apart, and the best-seeded
/// Gypsy Wives release won on quality. The fix is to read the title too.
///
/// Conservative like the episode rule: a name that says nothing recognisable
/// (a hash, two words) is not a contradiction; a real release name that lacks
/// the title's own words is. Titles with a colon are matched on their best
/// part, because releases of "Star Wars: Andor" are named "Andor".
public enum AppleStremioTitleMatch {
    static let stopwords: Set<String> = ["the", "a", "an", "of", "and", "in", "on", "at", "to", "for", "with", "vs", "by", "from", "part"]

    public static func normalize(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// The words that carry a title, per colon-separated part.
    static func significantParts(of title: String) -> [[String]] {
        title.split(separator: ":").map { part in
            normalize(String(part)).filter { !stopwords.contains($0) }
        }.filter { !$0.isEmpty }
    }

    /// True when `text` is a real release name (three or more alphabetic
    /// words) and no part of `title` is fully present in it.
    public static func contradicts(_ text: String, title: String) -> Bool {
        let words = normalize(text)
        guard words.filter({ $0.rangeOfCharacter(from: .letters) != nil }).count >= 3 else { return false }
        let parts = significantParts(of: title)
        guard !parts.isEmpty else { return false }
        let present = Set(words)
        return !parts.contains { part in part.allSatisfy(present.contains) }
    }

    // MARK: - Another edition of the same name

    /// Full test 2026-09-30: Saturday Night Live S1 E1 (1975) played
    /// "Saturday Night Live UK S01E01". Every word of the title is in that
    /// name, so `contradicts` passes it; what gives it away is the word right
    /// after the title. Country tags are how release names tell editions of a
    /// show apart ("The Office UK", "Shameless US").
    static let editionQualifiers: Set<String> = [
        "uk", "us", "usa", "au", "aus", "australia", "nz", "ca", "canada", "ie", "ireland",
    ]

    /// What a release name says straight after the title.
    enum Tail: Equatable {
        /// The title, then an episode, quality or other release tag.
        case bare
        /// The title, then a country tag the title itself does not carry.
        case qualifier(String)
        /// The title, then a year (not a daily show's date).
        case year(Int)
        /// The title was not found as a run of words, or nothing follows it.
        case unknown
    }

    static func tail(of text: String, title: String) -> Tail {
        let words = normalize(text)
        let full = normalize(title)
        let candidates = [full] + title.split(separator: ":").map { normalize(String($0)) }
        for titleWords in candidates where titleWords.count >= 1 && titleWords.joined().count >= 3 {
            guard let start = firstRun(of: titleWords, in: words) else { continue }
            let nextIndex = start + titleWords.count
            guard nextIndex < words.count else { return .unknown }
            let next = words[nextIndex]
            if editionQualifiers.contains(next), !full.contains(next) { return .qualifier(next) }
            if next.count == 4, let year = Int(next), (1900...2100).contains(year) {
                // "Show 2024 10 05" is a daily show's air date, not the show's year.
                let after = words.dropFirst(nextIndex + 1).prefix(2)
                if after.count == 2, after.allSatisfy({ $0.count <= 2 && Int($0) != nil }) { return .unknown }
                return .year(year)
            }
            return .bare
        }
        return .unknown
    }

    private static func firstRun(of run: [String], in words: [String]) -> Int? {
        guard !run.isEmpty, words.count >= run.count else { return nil }
        for start in 0...(words.count - run.count) where Array(words[start..<(start + run.count)]) == run {
            return start
        }
        return nil
    }

    /// Per release name, whether it is for something other than `title`
    /// (`year` when known):
    /// - `contradicts` — the title's words are missing;
    /// - a year straight after the title more than a year off `year`;
    /// - a country tag straight after the title, **but only when another
    ///   name has the title untagged** — with nothing to compare against
    ///   ("The Office UK" vs "The Office US") the tag says nothing about
    ///   which one was asked for, so nothing is demoted.
    public static func mismatches(_ texts: [String], title: String, year: Int? = nil) -> [Bool] {
        let tails = texts.map { tail(of: $0, title: title) }
        func yearConflicts(_ found: Int) -> Bool { year.map { abs($0 - found) > 1 } ?? false }
        let hasUntagged = tails.contains { tail in
            switch tail {
            case .bare: true
            case .year(let found): !yearConflicts(found)
            default: false
            }
        }
        return zip(texts, tails).map { text, tail in
            if contradicts(text, title: title) { return true }
            switch tail {
            case .qualifier: return hasUntagged
            case .year(let found): return yearConflicts(found)
            case .bare, .unknown: return false
            }
        }
    }
}
