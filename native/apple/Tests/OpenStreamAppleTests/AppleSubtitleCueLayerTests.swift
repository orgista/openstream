import CoreGraphics
import Foundation
import Testing
@testable import OpenStreamApple

/// The OpenStream engine hands the stock player's captions to the app, and
/// nothing drew them: every MKV/TS subtitle and every live-TS caption played
/// blank on a device (Q4a8 paths 1 and 2).
@Suite("Subtitle cue layer")
@MainActor
struct AppleSubtitleCueLayerTests {
    // MARK: - Route → mounted

    @Test("Mounted over the stock player only for the OpenStream engine", arguments: [
        (ApplePlaybackEngineKind.openStream, ApplePlaybackPresentationRoute.avPlayer, true),
        (.openStream, .surface, false),
        (.openStream, .none, false),
        (.openStream, .audioOnly, false),
        (.native, .avPlayer, false),
        (.native, .surface, false),
    ])
    func mountDecision(engine: ApplePlaybackEngineKind, route: ApplePlaybackPresentationRoute, mounted: Bool) {
        #expect(AppleSubtitleCueLayerPolicy.mountsOverStockPlayer(engine: engine, route: route) == mounted)
    }

    // MARK: - Cue → content

    @Test func textCuesDrawTheirText() {
        let cue = AppleSubtitleCue(id: 1, startTime: 1, endTime: 3, body: .text("CC ONE AT 1S"))
        #expect(AppleSubtitleCueContent(cue) == .text("CC ONE AT 1S"))
    }

    @Test func richTextRunsAreFlattenedIntoOneLine() {
        let cue = AppleSubtitleCue(id: 1, startTime: 1, endTime: 3, body: .richText([
            AppleSubtitleTextRun(text: "Hello, ", isItalic: true),
            AppleSubtitleTextRun(text: "world", isBold: true),
        ]))
        #expect(AppleSubtitleCueContent(cue) == .text("Hello, world"))
    }

    @Test func bitmapCuesDrawTheSameImage() throws {
        let image = try #require(Self.pixel())
        let cue = AppleSubtitleCue(id: 1, startTime: 1, endTime: 3, body: .image(image))
        #expect(AppleSubtitleCueContent(cue) == .image(image))
        #expect(AppleSubtitleCueContent(cue) != .image(try #require(Self.pixel())))
    }

    // MARK: - Active cue

    @Test func theCueOverlappingThePositionIsActiveAndItsEndIsExclusive() {
        let cues = [
            AppleSubtitleCue(id: 1, startTime: 1, endTime: 3, body: .text("one")),
            AppleSubtitleCue(id: 2, startTime: 4, endTime: 6, body: .text("two")),
        ]
        #expect(AppleSubtitleCueLayerPolicy.activeCue(in: cues, at: 0.5) == nil)
        #expect(AppleSubtitleCueLayerPolicy.activeCue(in: cues, at: 1)?.id == 1)
        #expect(AppleSubtitleCueLayerPolicy.activeCue(in: cues, at: 3) == nil)
        #expect(AppleSubtitleCueLayerPolicy.activeCue(in: cues, at: 5.9)?.id == 2)
        #expect(AppleSubtitleCueLayerPolicy.activeCue(in: [], at: 2) == nil)
    }

    // MARK: - Menu

    @Test func theMenuIsOffThenTheVisibleTracksWithTheActiveOneTicked() {
        let tracks = [ApplePlaybackTrack(id: 2, title: "ENG (srt)", language: "eng", codec: "subrip", isDefault: true)]
        let entries = AppleSubtitleCueLayerPolicy.menuEntries(
            tracks: tracks, preferredLanguages: [], languagesAreExplicit: false, activeTrackID: 2)
        #expect(entries.map(\.trackID) == [nil, 2])
        #expect(entries.map(\.isSelected) == [false, true])
    }

    @Test func noTracksMeansNoMenu() {
        #expect(AppleSubtitleCueLayerPolicy.menuEntries(
            tracks: [], preferredLanguages: [], languagesAreExplicit: false, activeTrackID: nil).isEmpty)
    }

    // MARK: - Feed

    @Test func theFeedShowsTheCueAtThePositionAndSelectsThroughTheEngine() {
        let engine = FakePlaybackEngine()
        engine.subtitleCues = [AppleSubtitleCue(id: 7, startTime: 36005, endTime: 36008, body: .text("CC ONE"))]
        engine.position = 36006
        let subtitles = AppleStockPlayerSubtitles()
        subtitles.refresh(from: engine)
        #expect(subtitles.cue?.id == 7)

        // "Off": the engine drops its cues and the layer empties at once,
        // without waiting for a position tick that a paused player never sends.
        engine.subtitleCues = []
        subtitles.select(nil, on: engine)
        #expect(engine.selectedSubtitle == [nil])
        #expect(subtitles.cue == nil)
    }

    private static func pixel() -> CGImage? {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context?.makeImage()
    }
}
