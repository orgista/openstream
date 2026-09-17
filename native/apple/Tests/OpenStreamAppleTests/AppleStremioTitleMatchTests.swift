import Foundation
import Testing
@testable import OpenStreamApple

/// Names are the real Torrentio answer for tt31091039:1:1 on 2026-09-17.
@Suite struct AppleStremioTitleMatchTests {
    let title = "The Secret Lives of Mormon Wives"

    @Test func otherShowsThatShareWordsContradict() {
        #expect(AppleStremioTitleMatch.contradicts("Secret Lives of Gypsy Wives S01E01 1080p HDTV H264-DARKFLiX", title: title))
        #expect(AppleStremioTitleMatch.contradicts("Secret Sex Lives of Tyrants S01E01 1080p WEB h264-EDITH", title: title))
    }

    @Test func theRightShowInAnyReleaseSpellingDoesNot() {
        #expect(!AppleStremioTitleMatch.contradicts("The.Secret.Lives.of.Mormon.Wives.S01.COMPLETE.1080p.WEB.h264-EDITH[TGx]", title: title))
        #expect(!AppleStremioTitleMatch.contradicts("The Secret Lives of Mormon Wives S01E01 1080p WEB h264-EDITH", title: title))
        #expect(!AppleStremioTitleMatch.contradicts("the_secret_lives_of_mormon_wives_s01e01.mkv", title: title))
    }

    @Test func silenceAndSubtitledTitlesAreNotContradictions() {
        #expect(!AppleStremioTitleMatch.contradicts("a1b2c3d4.mkv", title: title))
        #expect(!AppleStremioTitleMatch.contradicts("Andor.S01E01.1080p.WEB.h264-CAKES", title: "Star Wars: Andor"))
        #expect(AppleStremioTitleMatch.contradicts("The.Mandalorian.S01E01.1080p.WEB.h264-CAKES", title: "Star Wars: Andor"))
        #expect(!AppleStremioTitleMatch.contradicts("9-11.One.Day.in.America.S01E01.1080p", title: "9/11: One Day in America"))
    }

    @Test func rankingPutsTheRightShowFirstEvenAtLowerQuality() {
        let gypsy = AppleStremioHTTPPlaybackCandidate(
            title: "Secret Lives of Gypsy Wives S01E01 1080p HDTV H264-DARKFLiX",
            sourceURL: URL(string: "https://fixture.example/gypsy.mkv")!)
        let tyrants = AppleStremioHTTPPlaybackCandidate(
            title: "Secret Sex Lives Of Tyrants S01E01 720p WEB H264-JFF",
            sourceURL: URL(string: "https://fixture.example/tyrants.mkv")!)
        let mormon720 = AppleStremioHTTPPlaybackCandidate(
            title: "The.Secret.Lives.of.Mormon.Wives.S01.COMPLETE.720p.WEBRip.x264-GalaxyTV",
            sourceURL: URL(string: "https://fixture.example/mormon.mkv")!,
            filename: "The.Secret.Lives.of.Mormon.Wives.S01E01.720p.WEBRip.x264-GalaxyTV.mkv")
        let ranked = AppleStremioCandidateRanking.rankForAutomaticPlayback(
            [gypsy, tyrants, mormon720], episode: (season: 1, episode: 1), title: "The Secret Lives of Mormon Wives")
        #expect(ranked.first?.sourceURL == mormon720.sourceURL, "another show's S01E01 still won")
        #expect(ranked.map(\.sourceURL.lastPathComponent) == ["mormon.mkv", "gypsy.mkv", "tyrants.mkv"])
    }

    @Test func withoutATitleTheOldOrderStands() {
        let gypsy = AppleStremioHTTPPlaybackCandidate(title: "Secret Lives of Gypsy Wives S01E01 1080p", sourceURL: URL(string: "https://fixture.example/g.mkv")!)
        let mormon = AppleStremioHTTPPlaybackCandidate(title: "The Secret Lives of Mormon Wives S01E01 720p", sourceURL: URL(string: "https://fixture.example/m.mkv")!)
        #expect(AppleStremioCandidateRanking.rankForAutomaticPlayback([gypsy, mormon], episode: (1, 1)).first?.sourceURL == gypsy.sourceURL)
    }
}
