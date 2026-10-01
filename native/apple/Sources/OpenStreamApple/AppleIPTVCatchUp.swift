import Foundation

/// Catch-up (archive) playback for Xtream panels: a programme that already
/// aired on a channel whose panel reports `tv_archive`, played from the
/// panel's timeshift endpoint.
///
/// `GET /timeshift/<user>/<pass>/<minutes>/<YYYY-MM-DD:HH-MM>/<stream_id>.ts`
///
/// The URL is derived from the channel's own live URL
/// (`/live/<user>/<pass>/<stream_id>.<ext>`), so no credentials are stored or
/// passed anywhere new. Pure functions; the guide asks, the player plays.
public enum AppleIPTVCatchUp: Sendable {
    /// Days of archive from the panel's `tv_archive` / `tv_archive_duration`;
    /// nil when the channel has none.
    public static func archiveDays(tvArchive: String?, duration: String?) -> Int? {
        guard let flag = tvArchive?.trimmingCharacters(in: .whitespaces), flag == "1" || flag.lowercased() == "true",
              let days = duration.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), days > 0 else {
            return nil
        }
        return min(days, 30)
    }

    /// Whether `programme` on `channel` can be played from the archive at `now`:
    /// it has ended (a programme still airing is the live channel), and it
    /// started inside the panel's archive window.
    public static func isAvailable(
        _ programme: AppleIPTVProgramme,
        on channel: AppleIPTVChannel,
        now: Date = Date()
    ) -> Bool {
        guard let days = channel.catchUpDays, days > 0,
              timeshiftBase(for: channel.streamURL) != nil else { return false }
        guard programme.end <= now else { return false }
        return programme.start >= now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// The panel's timeshift URL for `programme`, or nil when the channel's
    /// URL is not an Xtream live URL.
    ///
    /// - Parameter timeZone: the panel's clock. Panels read the start time in
    ///   their own zone; UTC unless the account reports one.
    public static func timeshiftURL(
        for channel: AppleIPTVChannel,
        programme: AppleIPTVProgramme,
        timeZone: TimeZone = TimeZone(identifier: "UTC")!
    ) -> URL? {
        guard let base = timeshiftBase(for: channel.streamURL) else { return nil }
        let minutes = max(1, Int((programme.end.timeIntervalSince(programme.start) / 60).rounded(.up)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: programme.start)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute else { return nil }
        let start = String(format: "%04d-%02d-%02d:%02d-%02d", year, month, day, hour, minute)
        var components = base.components
        components.percentEncodedPath = "\(base.prefix)/timeshift/\(base.user)/\(base.password)/\(minutes)/\(start)/\(base.streamID).ts"
        return components.url
    }

    /// A playback request for the archived programme: on demand (it has a
    /// length and can be scrubbed), titled after the programme.
    public static func playbackRequest(
        for channel: AppleIPTVChannel,
        programme: AppleIPTVProgramme,
        timeZone: TimeZone = TimeZone(identifier: "UTC")!
    ) -> ApplePlaybackRequest? {
        guard let url = timeshiftURL(for: channel, programme: programme, timeZone: timeZone) else { return nil }
        var request = ApplePlaybackRequest(
            url: url,
            headers: channel.playbackHeaders,
            isLive: false,
            mediaID: "\(channel.id)#catchup-\(Int(programme.start.timeIntervalSince1970))",
            title: programme.title,
            sourceKind: .liveTV
        )
        request.artworkURL = channel.logoURL
        return request
    }

    private struct Base {
        var components: URLComponents
        var prefix: String
        var user: String
        var password: String
        var streamID: String
    }

    /// Splits `<prefix>/live/<user>/<pass>/<id>.<ext>` (percent-encoded parts
    /// kept as they are).
    private static func timeshiftBase(for streamURL: URL) -> Base? {
        guard var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) else { return nil }
        let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.count >= 5, segments[segments.count - 4] == "live" else { return nil }
        let file = segments[segments.count - 1]
        let streamID = file.split(separator: ".").first.map(String.init) ?? ""
        guard !streamID.isEmpty, streamID.allSatisfy(\.isNumber) else { return nil }
        let prefix = segments[0 ..< segments.count - 4].joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return Base(components: components, prefix: prefix,
                    user: segments[segments.count - 3], password: segments[segments.count - 2], streamID: streamID)
    }
}
