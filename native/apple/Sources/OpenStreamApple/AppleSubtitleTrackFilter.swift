import Foundation

/// Which subtitle tracks the captions menu lists.
///
/// A remux routinely carries fifteen or twenty subtitle tracks. The menu
/// listed every one of them even when the viewer had chosen a single language
/// in Settings — the preference was only ever handed to the engine for
/// auto-selection at load, never used to shorten the list (owner 2026-09-14:
/// "subtitles have too many tracks since I only selected one language").
///
/// Matching is on the language code, in the viewer's order of preference, and
/// tolerant about the form it takes: MKVs carry `eng`, `en`, `en-US` and
/// occasionally `English` for the same thing.
public enum AppleSubtitleTrackFilter: Sendable {
    /// The tracks to offer.
    ///
    /// `isExplicitChoice` is the difference between a language the viewer
    /// *picked* and one the app *guessed* from the device:
    ///
    /// - **Picked** (Settings → Playback → Subtitle Languages): that language
    ///   is the whole menu. Nil-language captions and add-on tracks remain
    ///   eligible when no language matches. Otherwise the menu is empty, and
    ///   that is the honest answer — the owner asked for "English can be
    ///   default, only option as well" (2026-09-15), and quietly listing
    ///   fifteen other languages is what made the menu unusable in the first
    ///   place. Also owner 2026-09-17: "subtitles picker has one option which is
    ///   the preferred language from settings — no English 1 or 2".
    /// - **Guessed** (device defaults, before the viewer has been to that
    ///   screen): fall back to the single best track of all tracks when nothing
    ///   matches, because an empty menu is worse than a long one when nobody
    ///   asked for anything.
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
