import Foundation
import Testing
@testable import OpenStreamApple

/// N32 extra: "Monster: The Lizzie Borden Story" stayed a grey title tile in
/// Top 10 Shows because Netflix names an anthology's season after its subtitle.
@Suite("Top 10 tiles Netflix names differently")
struct AppleTop10MissingArtTests {
    @Test("Only a series title with a subtitle has an anthology name", arguments: [
        ("Monster: The Lizzie Borden Story", "series", "Monster"),
        ("Love Is Blind: Ohio", "series", "Love Is Blind"),
        ("Monster", "series", nil),
        (": Untitled", "series", nil),
        ("Mission: Impossible", "movie", nil),
    ] as [(String, String, String?)])
    func anthologyName(title: String, type: String, expected: String?) {
        #expect(AppleTop10ArtworkLookup.anthologySeries(of: title, type: type) == expected)
    }
}
