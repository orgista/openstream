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

    @Test(arguments: ["eia_608", "cc"])
    func explicitSpanishKeepsNilLanguageCaptions(codec: String) {
        let tracks = [track(99_608, nil, "Closed Captions", codec: codec)]
        let visible = AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["es"], isExplicitChoice: true)
        #expect(visible.map(\.id) == [99_608])
    }

    @Test(arguments: [0, 1_000_000])
    func explicitSpanishStillRejectsEnglishOnly(id: Int) {
        let tracks = [track(id, "en", "English")]
        let visible = AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["es"], isExplicitChoice: true)
        #expect(visible.isEmpty)
    }

    @Test func explicitChoiceKeepsTheBestNilLanguageAddOn() {
        let tracks = [
            track(1_000_000, nil, "Add-on 1"),
            track(1_000_001, nil, "Add-on 2", isDefault: true)
        ]
        let visible = AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["es"], isExplicitChoice: true)
        #expect(visible.map(\.id) == [1_000_001])
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

    @Test func menuOrdersPreferredLanguagesThenDefaultThenID() {
        let tracks = [
            track(9, "de", "German"),
            track(8, "en", "English SDH"),
            track(7, "fr", "French", isDefault: true),
            track(6, "eng", "English", isDefault: true),
            track(5, "spa", "Spanish"),
            track(4, "it", "Italian"),
        ]
        let menu = AppleSubtitleTrackFilter.menu(tracks, preferredLanguages: ["English", "es-MX"])
        #expect(menu.map(\.id) == [6, 8, 5, 7, 4, 9])
        // English SDH sits under English, the language it belongs to.
        #expect(AppleSubtitleTrackFilter.menu(tracks, preferredLanguages: []).map(\.id) == [6, 8, 7, 4, 5, 9])
        #expect(AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["en"], isExplicitChoice: true).map(\.id) == [6])
        #expect(AppleSubtitleTrackFilter.visible(tracks, preferredLanguages: ["ja"], isExplicitChoice: true).isEmpty)
    }

    /// A forced track is its own row only beside a full one of its language;
    /// alone, a variant is simply that language.
    @Test func forcedIsItsOwnRowOnlyBesideAFullTrack() {
        let forced = ApplePlaybackTrack(id: 0, title: "English", language: "en", isDefault: true, isForced: true)
        let tracks = [forced, track(1, "es", "Spanish"), track(2, "en", "English SDH")]
        let choices = AppleSubtitleTrackFilter.menuChoices(tracks, preferredLanguages: ["en"])
        #expect(choices.map(\.track.id) == [2, 0, 1])
        #expect(choices.map(\.title) == ["English", "English (Forced)", "Spanish"])
        #expect(AppleSubtitleTrackFilter.menuChoices([forced], preferredLanguages: []).map(\.title) == ["English"])
        #expect(AppleSubtitleTrackFilter.menu([], preferredLanguages: []).isEmpty)
    }

    @Test func menuDeduplicatesLanguageAndTitleWhileKeepingVariants() {
        let tracks = [
            track(0, "eng", "English"),
            track(4, "EN-us", " english ", isDefault: true),
            track(2, "en", "English SDH"),
            track(3, "es", "English"),
            track(5, "English", "English SDH"),
            track(6, nil, "Unlabelled"),
            track(7, nil, "Unlabelled"),
        ]
        #expect(AppleSubtitleTrackFilter.menu(tracks, preferredLanguages: ["en"]).map(\.id) == [4, 2, 3, 6])
        #expect(AppleSubtitleTrackFilter.menu(tracks.reversed(), preferredLanguages: ["en"]).map(\.id) == [4, 2, 3, 6])
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
