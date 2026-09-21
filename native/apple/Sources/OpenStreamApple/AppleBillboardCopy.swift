import Foundation

/// The one-line "Drama · Sci-Fi · 2024" under a billboard's title lockup.
///
/// Both heroes draw it — the Apple TV billboard and the iPhone/iPad one — so
/// the rule for which parts appear, and what happens when a title has none of
/// them, lives here rather than being written twice.
public enum AppleBillboardCopy {
    public static let separator = " · "

    /// At most the first two genres, then the year (or the release text when
    /// there is no year). `nil` when nothing is known, so the copy block never
    /// shows a lonely separator or an empty line holding space.
    public static func metadataLine(genres: [String]?, year: Int?, releaseInfo: String?) -> String? {
        var parts: [String] = []
        if let genres {
            parts += genres
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(2)
        }
        if let year {
            parts.append(String(year))
        } else if let release = releaseInfo?.trimmingCharacters(in: .whitespacesAndNewlines), !release.isEmpty {
            parts.append(release)
        }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }
}
