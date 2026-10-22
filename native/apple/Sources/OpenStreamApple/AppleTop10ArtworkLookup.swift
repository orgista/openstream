import Foundation

enum AppleTop10ArtworkLookup {
    /// "Monster: The Lizzie Borden Story" → "Monster": Netflix names an
    /// anthology's season after its subtitle, metadata lists the series.
    /// Series only — a film's subtitle is part of its own name.
    nonisolated static func anthologySeries(of title: String, type: String) -> String? {
        guard type.caseInsensitiveCompare("series") == .orderedSame,
              let colon = title.firstIndex(of: ":") else { return nil }
        let name = title[..<colon].trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name.count == title.count ? nil : name
    }

    /// A chart title compared the way a person would: case, accents, punctuation and a leading
    /// article aside ("UNABOMBER" = "Unabomber", "The Widower" = "Widower").
    nonisolated static func chartKey(_ title: String) -> String {
        let words = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard let first = words.first, words.count > 1, ["the", "a", "an"].contains(first) else { return words.joined(separator: " ") }
        return words.dropFirst().joined(separator: " ")
    }
}
