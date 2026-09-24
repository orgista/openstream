import Foundation

/// One person on a title page's Cast & Crew rail: who, what they did, and a
/// portrait when the metadata has one.
public struct AppleCreditPerson: Equatable, Hashable, Sendable, Identifiable {
    public let name: String
    /// "Walter White", "Director", "Creator". Nil when the source names the
    /// person and nothing else.
    public let role: String?
    public let portraitURL: URL?

    public var id: String { "\(name)|\(role ?? "")" }

    public init(name: String, role: String? = nil, portraitURL: URL? = nil) {
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let cleanRole = role?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.role = cleanRole.isEmpty ? nil : String(cleanRole.prefix(100))
        self.portraitURL = portraitURL.flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
    }

    /// "Bryan Cranston" → "BC", for a portrait that has no picture.
    public var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return String(letters).uppercased()
    }
}

/// The iPhone title page's words and sections, after the Apple TV app's
/// (INSPO-TEARDOWN §7, PDF pages 11–16). Everything here is read from the
/// title's own metadata, episode list and saved position; a section with
/// nothing real to say is `nil` or empty and is not drawn.
public enum AppleTitlePagePolicy {
    // MARK: - The one button

    public enum PrimaryAction: Equatable, Sendable {
        /// "Resume S4, E8", or "Resume" for a film.
        case resume(episode: String?)
        case play
        /// Nothing on the page can play, but a trailer can.
        case playTrailer

        public func displayTitle(hasCompletedDownload: Bool) -> String {
            self == .play && hasCompletedDownload ? "Play Offline" : title
        }

        public var title: String {
            switch self {
            case .resume(let episode?): "Resume \(episode)"
            case .resume(nil): "Resume"
            case .play: "Play"
            case .playTrailer: "Play Trailer"
            }
        }
    }

    /// Shared by title pages and every Discover hero. Metadata-only add-ons
    /// are not playback routes. Local media and completed downloads work even
    /// when the catalog has no episode list or streaming add-on.
    public static func hasPlaybackRoute(
        item: AppleCatalogItem,
        sources: [AppleSource],
        hasLocalGroup: Bool = false,
        hasCompletedDownload: Bool = false,
        episodesUnavailable: Bool = false
    ) -> Bool {
        if AppleMediaServerItemReference.parse(item.mediaID) != nil || hasLocalGroup { return true }
        if hasCompletedDownload { return true }
        if item.type == "series", episodesUnavailable { return false }
        return sources.contains { source in
            source.isEnabled && (source.kind != .stremio
                || source.resources.contains { $0.caseInsensitiveCompare("stream") == .orderedSame })
        }
    }

    /// The hero has no episode picker: resume the saved episode, otherwise
    /// use the title page's default. Media servers own their episode list and
    /// resume routing; retain their opaque saved part id for the same label.
    static func heroEpisode(item: AppleCatalogItem, progress: ApplePlaybackProgress?,
                            episodes: [AppleStremioEpisode], completedIDs: Set<String> = [],
                            localResumeEpisode: AppleStremioEpisode? = nil) -> AppleStremioEpisode? {
        if let saved = AppleStremioEpisodePolicy.savedEpisode(progress: progress, in: episodes) { return saved }
        if AppleMediaServerItemReference.parse(item.mediaID) != nil,
           let progress, progress.resumePosition != nil, let part = progress.partID {
            let identity = AppleStremioMetadataClient.episodeIdentity(part)
            return AppleStremioEpisode(id: part, title: "", season: identity?.season,
                                       episode: identity?.episode, releaseInfo: nil)
        }
        if let localResumeEpisode { return localResumeEpisode }
        return AppleStremioEpisodePolicy.nextUnwatched(
            in: AppleStremioEpisodePolicy.initialSeason(in: episodes), from: episodes, completedIDs: completedIDs
        )
    }

    /// The button's verb, derived from state rather than an error after the
    /// press (A8 UX note). `progress` is the title's saved position;
    /// `selectedEpisodeID` the episode Play would start. A series only says
    /// Resume when the saved position belongs to that episode, so choosing
    /// another season never leaves the button promising the old one.
    public static func primaryAction(
        type: String,
        progress: ApplePlaybackProgress?,
        selectedEpisode: AppleStremioEpisode?,
        isPlayable: Bool,
        hasTrailer: Bool
    ) -> PrimaryAction {
        guard isPlayable else { return hasTrailer ? .playTrailer : .play }
        guard let progress, progress.resumePosition != nil else { return .play }
        if type == "series" {
            guard let selectedEpisode, progress.partID == selectedEpisode.id else { return .play }
            return .resume(episode: episodeCode(selectedEpisode))
        }
        return .resume(episode: nil)
    }

    /// "S4, E8" — the Apple TV app's spelling. Nil without a season and number.
    public static func episodeCode(_ episode: AppleStremioEpisode) -> String? {
        guard let season = episode.season, let number = episode.episode else { return nil }
        return "S\(season), E\(number)"
    }

    /// "S4, E8 · Follow the Anger" over the next episode's synopsis.
    public static func nextEpisodeHeading(_ episode: AppleStremioEpisode) -> String? {
        let code = episodeCode(episode)
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (code, title.isEmpty) {
        case (let code?, false): return "\(code) · \(title)"
        case (let code?, true): return code
        case (nil, false): return title
        case (nil, true): return nil
        }
    }

    // MARK: - Schedule badge

    /// "New Episode Every Wednesday" when the show is airing weekly — its last
    /// three episodes of the current season came out seven days apart on the
    /// same weekday, and the newest aired in the last eight days or the next
    /// one is announced within eight. Otherwise the home hero's "New Season" /
    /// "New Episode" rule, and otherwise nothing.
    public static func scheduleBadge(
        type: String,
        episodes: [AppleHeroBadge.Episode],
        now: Date,
        calendar: Calendar = utcCalendar()
    ) -> String? {
        guard type.lowercased() == "series" else { return nil }
        let regular = episodes.filter { $0.season > 0 && $0.episode > 0 }
        let aired = regular.filter { $0.released <= now }
            .sorted { ($0.released, $0.season, $0.episode) < ($1.released, $1.season, $1.episode) }
        let upcoming = regular.filter { $0.released > now }.min { $0.released < $1.released }
        let week: TimeInterval = 7 * 24 * 60 * 60
        let slack: TimeInterval = 12 * 60 * 60
        if let latest = aired.last {
            let season = aired.filter { $0.season == latest.season }.suffix(3)
            let dates = season.map(\.released)
            let intervals = zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) }
            let weekdays = Set(dates.map { calendar.component(.weekday, from: $0) })
            let isWeekly = intervals.count >= 2
                && intervals.allSatisfy { abs($0 - week) <= slack }
                && weekdays.count == 1
            let isCurrent = now.timeIntervalSince(latest.released) <= week + 24 * 60 * 60
                || (upcoming.map { $0.released.timeIntervalSince(now) <= week + 24 * 60 * 60 } ?? false)
            if isWeekly, isCurrent, let weekday = weekdays.first {
                return "New Episode Every \(calendar.weekdaySymbols[weekday - 1])"
            }
        }
        return AppleHeroBadge.select(type: type, episodes: episodes, now: now)?.title
    }

    /// "EPISODE 8", or "EPISODE 8 · COMING WEDNESDAY" / "· COMING SEP 30" for
    /// one that has not aired — an appointment, not a greyed-out tile (A10).
    public static func episodeEyebrow(
        _ episode: AppleStremioEpisode,
        now: Date,
        calendar: Calendar = utcCalendar()
    ) -> String {
        var parts: [String] = []
        if let number = episode.episode {
            parts.append(episode.season == 0 ? "SPECIAL \(number)" : "EPISODE \(number)")
        } else {
            parts.append(episode.season == 0 ? "SPECIAL" : "EPISODE")
        }
        if let released = AppleHeroBadge.releaseDate(episode.releaseInfo), released > now {
            let days = released.timeIntervalSince(now) / (24 * 60 * 60)
            if days < 7 {
                parts.append("COMING \(calendar.weekdaySymbols[calendar.component(.weekday, from: released) - 1].uppercased())")
            } else {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.locale = calendar.locale ?? .current
                formatter.setLocalizedDateFormatFromTemplate("MMMd")
                parts.append("COMING \(formatter.string(from: released).uppercased())")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Released dates arrive as midnight UTC, so their weekday is read in UTC.
    public static func utcCalendar(locale: Locale = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = locale
        return calendar
    }

    // MARK: - Capability chips and what they mean

    /// "4K · HDR · CC · SDH · AD" from the title's own format badges, best
    /// first, unknown values dropped. The content rating is not a capability;
    /// it rides on the meta line.
    public static func capabilityChips(formatBadges: [String]) -> [String] {
        AppleTitleMetadataPresentation.orderedBadges(contentRating: nil, formatBadges: formatBadges, limit: 8)
            .filter { !AppleTitleMetadataPresentation.isContentRating($0) }
    }

    /// The accessibility chips shown in the hero, each spelled out (A13): the
    /// compressed badge and its meaning on the same page.
    public static func accessibilityGlossary(chips: [String]) -> [(badge: String, meaning: String)] {
        let meanings: [(String, String)] = [
            ("CC", "Closed captions (CC) are subtitles in the available language that also describe relevant sounds that aren’t dialogue."),
            ("SDH", "Subtitles for the deaf and hard of hearing (SDH) are subtitles in the original language that also describe relevant sounds that aren’t dialogue."),
            ("AD", "Audio descriptions (AD) are a narration track that describes what is happening on screen, for people who are blind or have low vision."),
        ]
        let present = Set(chips.map { $0.uppercased() })
        return meanings.filter { present.contains($0.0) }.map { (badge: $0.0, meaning: $0.1) }
    }

    /// The 16:9 still YouTube keeps for a video (no letterbox bars).
    public static func trailerThumbnailURL(for key: String?) -> URL? {
        guard let key = AppleTrailerPreviewPolicy.validYouTubeKey(key) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(key)/mqdefault.jpg")
    }

    // MARK: - Reference blocks

    public struct Fact: Equatable, Sendable, Identifiable {
        public let label: String
        public let value: String
        public var id: String { label }

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    /// Released · Rated · Region of Origin, each only when known.
    public static func information(
        year: Int?,
        releaseInfo: String?,
        contentRating: String?,
        countries: [String]
    ) -> [Fact] {
        var facts: [Fact] = []
        let release = year.map(String.init)
            ?? AppleTitleMetadataPresentation.formattedReleaseInfo(releaseInfo)
        if let release { facts.append(Fact(label: "Released", value: release)) }
        if let rating = AppleBillboardCopy.ratingBadge(contentRating) {
            facts.append(Fact(label: "Rated", value: rating))
        }
        let regions = cleanList(countries)
        if !regions.isEmpty {
            facts.append(Fact(label: regions.count == 1 ? "Region of Origin" : "Regions of Origin",
                              value: regions.joined(separator: ", ")))
        }
        return facts
    }

    /// Original Audio, then the other spoken languages. Subtitle languages
    /// are only known once a stream is open, so there is no row for them.
    public static func languages(originalLanguage: String?, spokenLanguages: [String]) -> [Fact] {
        var facts: [Fact] = []
        let original = originalLanguage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !original.isEmpty { facts.append(Fact(label: "Original Audio", value: original)) }
        let spoken = cleanList(spokenLanguages)
        if !spoken.isEmpty, spoken != [original] {
            facts.append(Fact(label: "Audio", value: spoken.joined(separator: ", ")))
        }
        return facts
    }

    /// The Cast & Crew rail: the detailed credits when the metadata has them
    /// (portraits, characters), otherwise the bare names — cast as "Actor",
    /// then the director and writers. One entry per person, at most 20.
    public static func credits(
        detailed: [AppleCreditPerson],
        cast: [String],
        director: String?,
        writers: [String]
    ) -> [AppleCreditPerson] {
        let people = !detailed.isEmpty
            ? detailed
            : cleanList(cast).map { AppleCreditPerson(name: $0, role: "Actor") }
                + cleanList([director].compactMap { $0 }).map { AppleCreditPerson(name: $0, role: "Director") }
                + cleanList(writers).map { AppleCreditPerson(name: $0, role: "Writer") }
        var seen = Set<String>()
        return people.filter { !$0.name.isEmpty && seen.insert($0.name.lowercased()).inserted }
            .prefix(20).map { $0 }
    }

    /// A display name for a language code ("en" → "English"), or the value
    /// itself when it is already a name.
    public static func languageName(_ value: String?, locale: Locale = .current) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.count <= 3, value.allSatisfy(\.isLetter),
           let name = locale.localizedString(forLanguageCode: value.lowercased()) {
            return name
        }
        return value
    }

    /// A display name for a region code ("GB" → "United Kingdom"), or the
    /// value itself when it is already a name. Cinemeta writes the two most
    /// common countries as "usa" and "uk".
    public static func regionName(_ value: String?, locale: Locale = .current) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        let aliases = ["USA": "US", "UK": "GB"]
        let code = aliases[value.uppercased()] ?? value.uppercased()
        if code.count == 2, code.allSatisfy(\.isLetter),
           let name = locale.localizedString(forRegionCode: code) {
            return name
        }
        return value.count <= 3 && value.allSatisfy(\.isLetter) ? value.uppercased() : value
    }

    private static func cleanList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
