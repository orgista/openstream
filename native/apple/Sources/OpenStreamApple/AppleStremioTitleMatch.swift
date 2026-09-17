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
}
