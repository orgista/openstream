import Foundation

/// Subtitle auto-selection and the full manual track menu.
///
/// Language matching tolerates MKV codes such as `eng`, `en`, `en-US`, and
/// `English`. Explicit Settings choices constrain auto-selection only; the
/// manual menu always offers every distinct non-forced track.
public enum AppleSubtitleTrackFilter: Sendable {
    /// The single auto-select candidate, preserving the owner's Settings rule.
    /// Explicit languages never fall back to another known language; unlabelled
    /// captions and add-ons remain eligible when no language matches. Guessed
    /// device preferences may fall back to the best available track.
    public static func visible(
        _ tracks: [ApplePlaybackTrack],
        preferredLanguages: [String],
        isExplicitChoice: Bool = false
    ) -> [ApplePlaybackTrack] {
        let wanted = preferredLanguages.map(normalized).filter { !$0.isEmpty }
        
        var matchedLanguageTracks: [ApplePlaybackTrack] = []
        for language in wanted {
            let matches = tracks.filter { normalized($0.language ?? "") == language }
            if !matches.isEmpty {
                matchedLanguageTracks = matches
                break
            }
        }
        
        if matchedLanguageTracks.isEmpty {
            if !wanted.isEmpty && isExplicitChoice {
                // Missing language metadata does not mean the track is in a
                // different language. Keep synthetic 608 and unlabelled add-ons.
                matchedLanguageTracks = tracks.filter {
                    $0.language == nil && ($0.codec?.lowercased() == "eia_608"
                        || $0.codec?.lowercased() == "cc" || $0.id >= 1_000_000)
                }
            } else {
                // Empty preferences or guessed with no match -> single best of all
                matchedLanguageTracks = tracks
            }
        }
        
        guard let best = matchedLanguageTracks.min(by: { a, b in
            if a.isDefault != b.isDefault { return a.isDefault }
            let aIsCC = a.codec?.lowercased() == "cc"
            let bIsCC = b.codec?.lowercased() == "cc"
            if aIsCC != bIsCC { return !aIsCC }
            let aBad = a.title.lowercased().contains("forced") || a.title.lowercased().contains("sdh") || a.title.lowercased().contains("commentary")
            let bBad = b.title.lowercased().contains("forced") || b.title.lowercased().contains("sdh") || b.title.lowercased().contains("commentary")
            if aBad != bBad { return !aBad }
            return a.id < b.id
        }) else { return [] }
        
        return [best]
    }

    /// All non-forced choices, ordered by language preference, default, then ID.
    /// Duplicate language/title pairs keep the highest-ranked track, while
    /// differently titled variants (such as English SDH) remain selectable.
    public static func menu(
        _ tracks: [ApplePlaybackTrack],
        preferredLanguages: [String],
        activeTrackID: Int? = nil
    ) -> [ApplePlaybackTrack] {
        let wanted = preferredLanguages.map(normalized).filter { !$0.isEmpty }
        let ranked = tracks.filter { !$0.isForced }.sorted { a, b in
            let aRank = wanted.firstIndex(of: normalized(a.language ?? "")) ?? wanted.count
            let bRank = wanted.firstIndex(of: normalized(b.language ?? "")) ?? wanted.count
            if aRank != bRank { return aRank < bRank }
            if a.isDefault != b.isDefault { return a.isDefault }
            return a.id < b.id
        }
        let active = ranked.first { $0.id == activeTrackID }
        var titlesByLanguage: [String: Set<String>] = [:]
        return ranked.filter { track in
            let language = normalized(track.language ?? "")
            let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Preserve the rendered identity when equivalent menu labels are
            // coalesced. Otherwise an auto-selected duplicate has no checked row.
            if let active, track.id != active.id,
               normalized(active.language ?? "") == language,
               active.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == title {
                return false
            }
            return titlesByLanguage[language, default: []].insert(title).inserted
        }
    }

    /// `eng`, `en`, `en-US`, `en_US` and `English` all reduce to `en`.
    static func normalized(_ value: String) -> String {
        let lower = value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !lower.isEmpty else { return "" }
        let base = lower.split(separator: "-").first.map(String.init) ?? lower
        if base.count == 2 { return base }
        if let alpha2 = Locale.LanguageCode(base).identifier(.alpha2), alpha2.count == 2 {
            return alpha2.lowercased()
        }
        // A spelled-out name ("English"), matched against the picker's table.
        if let code = AppleSubtitleLanguages.names.first(where: { $0.value.lowercased() == base })?.key,
           let alpha2 = Locale.LanguageCode(code).identifier(.alpha2), alpha2.count == 2 {
            return alpha2.lowercased()
        }
        return base
    }

    public static func menuLabel(for track: ApplePlaybackTrack) -> String {
        let code = normalized(track.language ?? "")
        if !code.isEmpty, let loc = Locale.current.localizedString(forLanguageCode: code), !loc.isEmpty {
            return loc.capitalized
        }
        var cleanTitle = track.title
        var changed = true
        while changed {
            changed = false
            if let range = cleanTitle.range(of: "\\s+\\d+$", options: .regularExpression) {
                cleanTitle.replaceSubrange(range, with: "")
                changed = true
            }
            if let range = cleanTitle.range(of: "\\s*\\([a-zA-Z\\-]+\\)$", options: .regularExpression) {
                cleanTitle.replaceSubrange(range, with: "")
                changed = true
            }
        }
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanTitle.isEmpty ? "Subtitles" : cleanTitle
    }
}
