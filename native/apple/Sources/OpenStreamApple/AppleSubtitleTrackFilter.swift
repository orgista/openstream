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

    /// One row of a captions menu: a human name and the track it plays.
    public struct MenuChoice: Equatable, Sendable {
        /// The track this row selects: the active one when it belongs to the
        /// row, so the check mark stays on what is drawn; otherwise the best.
        public let track: ApplePlaybackTrack
        /// "English", "English (SDH)", "Spanish" — never a number, a codec or
        /// a source name.
        public let title: String
        /// Every track the row stands for, the chosen one included.
        public let memberIDs: [Int]
    }

    /// What kind of subtitle a track is, for naming and merging. A row is
    /// one language and one kind.
    enum MenuKind: Int, Comparable {
        case full, sdh, closedCaptions, commentary, forced

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var suffix: String {
            switch self {
            case .full: ""
            case .sdh: "SDH"
            case .closedCaptions: "CC"
            case .commentary: "Commentary"
            case .forced: "Forced"
            }
        }
    }

    /// Every choice once, human-named (owner 2026-09-24: "captions also have
    /// English 1, 2 — it shouldn't have numbers or options").
    ///
    /// Tracks are grouped by language and kind, so three English files from
    /// three add-ons and the film's own English track are one "English" row.
    /// Within a row the best member plays: text over bitmap, the stream's own
    /// track over an add-on file, the container default, then the lower id.
    /// A variant gets its own row, named with its kind — "English (SDH)",
    /// "English (Forced)" — only when a plain track of that language exists
    /// too; alone, it simply is "English". Rows follow the viewer's language
    /// preference, then a language with a default track, then stream order.
    public static func menuChoices(
        _ tracks: [ApplePlaybackTrack],
        preferredLanguages: [String],
        activeTrackID: Int? = nil
    ) -> [MenuChoice] {
        let wanted = preferredLanguages.map(normalized).filter { !$0.isEmpty }
        struct Key: Hashable { let language: String; let kind: MenuKind }
        var order: [Key] = []
        var members: [Key: [ApplePlaybackTrack]] = [:]
        for track in tracks {
            let key = Key(language: languageKey(of: track), kind: kind(of: track))
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(track)
        }
        // A language with no plain row promotes its best variant to it.
        let languages = Set(order.map(\.language))
        var promoted: [String: MenuKind] = [:]
        for language in languages where !order.contains(Key(language: language, kind: .full)) {
            promoted[language] = order.filter { $0.language == language }.map(\.kind).min()
        }
        // Languages: preferred first, then one holding a default track, then
        // by lowest id — the order the stream lists them in.
        var hasDefault: [String: Bool] = [:]
        var lowestID: [String: Int] = [:]
        for track in tracks {
            let language = languageKey(of: track)
            hasDefault[language] = (hasDefault[language] ?? false) || track.isDefault
            lowestID[language] = min(lowestID[language] ?? .max, track.id)
        }
        let sorted = order.sorted { a, b in
            if a.language != b.language {
                let aRank = wanted.firstIndex(of: a.language) ?? wanted.count
                let bRank = wanted.firstIndex(of: b.language) ?? wanted.count
                if aRank != bRank { return aRank < bRank }
                let aDefault = hasDefault[a.language] ?? false, bDefault = hasDefault[b.language] ?? false
                if aDefault != bDefault { return aDefault }
                return lowestID[a.language, default: 0] < lowestID[b.language, default: 0]
            }
            return a.kind < b.kind
        }
        return sorted.compactMap { key in
            guard let group = members[key], let best = group.min(by: isBetter) else { return nil }
            let chosen = group.first { $0.id == activeTrackID } ?? best
            let name = languageName(key.language)
            let isPlain = key.kind == .full || promoted[key.language] == key.kind
            let title = isPlain || key.kind.suffix.isEmpty ? name : "\(name) (\(key.kind.suffix))"
            return MenuChoice(track: chosen, title: title, memberIDs: group.map(\.id))
        }
    }

    /// The representative tracks of `menuChoices`, in menu order.
    public static func menu(
        _ tracks: [ApplePlaybackTrack],
        preferredLanguages: [String],
        activeTrackID: Int? = nil
    ) -> [ApplePlaybackTrack] {
        menuChoices(tracks, preferredLanguages: preferredLanguages, activeTrackID: activeTrackID).map(\.track)
    }

    /// Text over bitmap, the stream's own over an add-on's, default, lower id.
    private static func isBetter(_ a: ApplePlaybackTrack, than b: ApplePlaybackTrack) -> Bool {
        let aBitmap = ApplePlayerSubtitleSelection.isBitmap(a), bBitmap = ApplePlayerSubtitleSelection.isBitmap(b)
        if aBitmap != bBitmap { return !aBitmap }
        let aAddon = a.id >= externalTrackIDBase, bAddon = b.id >= externalTrackIDBase
        if aAddon != bAddon { return !aAddon }
        if a.isDefault != b.isDefault { return a.isDefault }
        return a.id < b.id
    }

    /// Both engines number add-on subtitle files from here.
    static let externalTrackIDBase = 1_000_000

    static func kind(of track: ApplePlaybackTrack) -> MenuKind {
        let title = track.title.lowercased()
        func mentions(_ pattern: String) -> Bool {
            title.range(of: pattern, options: .regularExpression) != nil
        }
        if track.isForced || mentions(#"\bforced\b"#) { return .forced }
        if track.isHearingImpaired || mentions(#"\b(?:sdh|hi|hoh|hearing[ -]impaired|deaf)\b"#) { return .sdh }
        let codec = track.codec?.lowercased() ?? ""
        if ["eia_608", "eia_708", "cea608", "cea708", "cea_708", "cc"].contains(codec)
            || mentions(#"\b(?:cc|closed captions?)\b"#) { return .closedCaptions }
        if mentions(#"\bcommentary\b"#) { return .commentary }
        return .full
    }

    /// The track's language code, or one read off a title that names a
    /// language ("English", "Français") when the container gave none.
    static func languageKey(of track: ApplePlaybackTrack) -> String {
        let code = normalized(track.language ?? "")
        if !code.isEmpty, code != "und", code != "zxx" { return code }
        for word in track.title.split(whereSeparator: { !$0.isLetter }) {
            let candidate = String(word)
            guard candidate.count > 3 else { continue }
            if let named = AppleSubtitleLanguages.names.first(where: {
                $0.value.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            })?.key {
                let code = normalized(named)
                if !code.isEmpty { return code }
            }
        }
        return ""
    }

    /// "en" → "English". A code the system cannot name stays readable as
    /// the tracks' own word for it rather than a raw code.
    static func languageName(_ code: String) -> String {
        guard !code.isEmpty else { return "Subtitles" }
        if let name = Locale.current.localizedString(forLanguageCode: code), !name.isEmpty,
           name.lowercased() != code {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return code.uppercased()
    }

    /// `eng`, `en`, `en-US`, `en_US` and `English` all reduce to `en`.
    static func normalized(_ value: String) -> String {
        let lower = value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !lower.isEmpty else { return "" }
        let base = lower.split(separator: "-").first.map(String.init) ?? lower
        if base.count == 2 { return base }
        // Matroska writes ISO 639-2/B ("fre", "ger"), which Foundation does
        // not map; without these the menu read "FRE (srt)".
        if let terminology = bibliographicCodes[base] { return terminology }
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

    private static let bibliographicCodes: [String: String] = [
        "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "chi": "zh", "cze": "cs", "dut": "nl",
        "fre": "fr", "geo": "ka", "ger": "de", "gre": "el", "ice": "is", "mac": "mk", "mao": "mi",
        "may": "ms", "per": "fa", "rum": "ro", "slo": "sk", "tib": "bo", "wel": "cy",
    ]

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
