import Foundation

/// The iPhone portrait Discover rows in the Apple TV app's style (N11: owner
/// Figma + inspo PDF A2–A4). Pure rules; the views are in
/// `AppleDiscoverPhoneRowViews.swift`.
enum AppleDiscoverPhoneRowMetrics {
    /// Continue Watching and the other still rails (A2, Figma 248 pt).
    static let stillWidth: CGFloat = 248
    /// Top 10: two tiles and a peek of the third across a 393 pt phone (A3/A4).
    static let rankedWidth: CGFloat = 200
    /// New Releases-style poster rails (Figma 148 pt, 2:3).
    static let posterWidth: CGFloat = 148
    static let cornerRadius: CGFloat = 12
    static let cardGap: CGFloat = 12
    static let progressHeight: CGFloat = 3
}

/// The copy under and on a Continue Watching still.
enum AppleContinueWatchingCaption {
    /// "57 MIN LEFT", "1 HR 5 MIN LEFT"; nil when the length is not known, so
    /// the pill is hidden rather than guessed (DESIGN-SPEC: real time only).
    static func remainingLabel(position: Double, duration: Double) -> String? {
        guard duration.isFinite, position.isFinite, duration > 0, position >= 0, position < duration else { return nil }
        let minutes = max(1, Int((duration - position) / 60 + 0.5))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(minutes) MIN LEFT" }
        return rest == 0 ? "\(hours) HR LEFT" : "\(hours) HR \(rest) MIN LEFT"
    }

    /// Season and episode from a series part id (`tt…:1:3` → 1, 3).
    static func episode(partID: String?) -> (season: Int, episode: Int)? {
        guard let parts = partID?.split(separator: ":"), parts.count >= 3,
              let season = Int(parts[parts.count - 2]), let episode = Int(parts[parts.count - 1]),
              season >= 0, episode > 0 else { return nil }
        return (season, episode)
    }

    /// "Continue · S1, E3" for an episode, "Movie" for a film, and "Continue"
    /// for a show whose episode is not known.
    static func subtitle(type: String, partID: String?) -> String {
        if type.caseInsensitiveCompare("movie") == .orderedSame { return "Movie" }
        guard let value = episode(partID: partID) else { return "Continue" }
        return "Continue · S\(value.season), E\(value.episode)"
    }
}

/// A4 rail rhythm: consecutive rails alternate stills and posters so the feed
/// never reads as one long list.
enum AppleDiscoverRailRhythm {
    enum Shape: Equatable, Sendable { case still, poster }

    /// Indices into `shapes`, reordered so that no two neighbours share a shape
    /// while both kinds remain. The first rail stays first (Continue Watching
    /// must peek under the hero), and rails of one shape keep their order.
    static func order(_ shapes: [Shape]) -> [Int] {
        guard let first = shapes.indices.first else { return [] }
        var stills = shapes.indices.filter { shapes[$0] == .still && $0 != first }
        var posters = shapes.indices.filter { shapes[$0] == .poster && $0 != first }
        var result = [first]
        var last = shapes[first]
        while !stills.isEmpty || !posters.isEmpty {
            let takeStill = last == .poster ? !stills.isEmpty : posters.isEmpty
            let next = takeStill ? stills.removeFirst() : posters.removeFirst()
            result.append(next)
            last = shapes[next]
        }
        return result
    }
}

/// A4 note: text under a tile is clamped at a word boundary, never mid-word.
enum AppleWordClamp {
    /// The full text, then ever-shorter word prefixes ending in "…". The view
    /// shows the first one that fits its line budget.
    static func candidates(_ text: String) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return [text] }
        var values = [text]
        for count in stride(from: words.count - 1, through: 1, by: -1) {
            var prefix = words.prefix(count).joined(separator: " ")
            while let last = prefix.last, ",;:-–—·".contains(last) { prefix.removeLast() }
            values.append(prefix + "…")
        }
        return values
    }
}
