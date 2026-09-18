import Foundation
import Testing
@testable import OpenStreamApple

@Suite("Subtitle track filter")
struct AppleSubtitleTrackFilterTests {
    private func track(_ id: Int, _ language: String?, _ title: String = "Subtitle", codec: String? = nil, isDefault: Bool = false) -> ApplePlaybackTrack {
        ApplePlaybackTrack(id: id, title: title, language: language, codec: codec, isDefault: isDefault)
    }

    @Test func twoEnglishTracksReturnsExactlyTheDefaultOne() {
        let tracks = [
            track(0, "en", "English 1"),
            track(1, "en", "English 2", isDefault: true)
        ]
        let visible = AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["en"])
        #expect(visible.map(\.id) == [1])
    }

    @Test func preferredListWithOnlyEnglishPresentReturnsTheEnglishOne() {
        let tracks = [
            track(0, "spa", "Spanish"),
            track(1, "eng", "English")
        ]
        let visible = AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["fr", "en"])
        #expect(visible.map(\.id) == [1])
    }

    @Test func explicitChoiceWithNoMatchReturnsEmpty() {
        let tracks = [track(0, "spa", "Spanish")]
        let visible = AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["en"], isExplicitChoice: true)
        #expect(visible.isEmpty)
    }

    @Test func guessedWithNoMatchReturnsOneTrack() {
        let tracks = [
            track(0, "spa", "Spanish 1"),
            track(1, "spa", "Spanish 2", isDefault: true)
        ]
        let visible = AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["en"], isExplicitChoice: false)
        #expect(visible.map(\.id) == [1])
    }

    @Test func plainSubtitlesPreferredOverCC() {
        let tracks = [
            track(0, "en", "English CC", codec: "cc"),
            track(1, "en", "English Sub", codec: "subrip")
        ]
        let visible = AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["en"])
        #expect(visible.map(\.id) == [1])
    }

    @Test func forcedAndSDHDemoted() {
        let tracks = [
            track(0, "en", "English SDH"),
            track(1, "en", "English Forced"),
            track(2, "en", "English Commentary"),
            track(3, "en", "English")
        ]
        let visible = AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["en"])
        #expect(visible.map(\.id) == [3])
    }

    @Test func emptyPreferencesReturnsOneTrack() {
        let tracks = [
            track(0, "spa", "Spanish"),
            track(1, "eng", "English", isDefault: true)
        ]
        let visible = AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: [])
        #expect(visible.map(\.id) == [1])
    }

    @Test func menuLabelLanguageFormatting() {
        // menuLabel for language "eng" -> "English"
        #expect(AppleSubtitleTrackFilter.menuLabel(for: track(0, "eng")) == "English")
        
        // menuLabel for "en-US" -> "English"
        #expect(AppleSubtitleTrackFilter.menuLabel(for: track(0, "en-US")) == "English")
        
        // menuLabel for a track with no language and title "Subtitle 2" -> "Subtitle"
        #expect(AppleSubtitleTrackFilter.menuLabel(for: track(0, nil, "Subtitle 2")) == "Subtitle")
        
        // menuLabel title "English 1 (eng)" no language -> "English"
        #expect(AppleSubtitleTrackFilter.menuLabel(for: track(0, nil, "English 1 (eng)")) == "English")
    }

    @Test func normalisationReducesEveryFormToTheTwoLetterCode() {
        #expect(AppleSubtitleTrackFilter.normalized("eng") == "en")
        #expect(AppleSubtitleTrackFilter.normalized("EN-us") == "en")
        #expect(AppleSubtitleTrackFilter.normalized("English") == "en")
        #expect(AppleSubtitleTrackFilter.normalized("  spa ") == "es")
        #expect(AppleSubtitleTrackFilter.normalized("") == "")
    }
}
