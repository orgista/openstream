import Testing
@testable import OpenStreamApple

@Suite struct AppleSubtitleSelectionStateTests {
    @Test func startupAutoSelectionIsTheRenderedTrack() {
        #expect(AppleSubtitleSelectionState.renderedTrackID(
            engineTrackID: 7, appTrackID: nil, appOwnsRendering: false) == 7)
    }

    @Test func offClearsThePreviousTrack() {
        #expect(AppleSubtitleSelectionState.renderedTrackID(
            engineTrackID: nil, appTrackID: 7, appOwnsRendering: false) == nil)
    }

    @Test func engineEchoCannotClearAppRenderer() {
        #expect(AppleSubtitleSelectionState.renderedTrackID(
            engineTrackID: nil, appTrackID: 1_000_000, appOwnsRendering: true) == 1_000_000)
    }

    @Test func late608DiscoveryRetainsTheSelectedID() {
        let selected = AppleSubtitleSelectionState.renderedTrackID(
            engineTrackID: 99608, appTrackID: nil, appOwnsRendering: false)
        #expect(AppleSubtitleCueLayerPolicy.menuEntries(tracks: [], preferredLanguages: [],
            languagesAreExplicit: false, activeTrackID: selected).isEmpty)
        let entries = AppleSubtitleCueLayerPolicy.menuEntries(
            tracks: [ApplePlaybackTrack(id: 99608, title: "English", language: "en", codec: "eia_608")],
            preferredLanguages: ["en"], languagesAreExplicit: true, activeTrackID: selected)
        #expect(entries.filter(\.isSelected).map(\.trackID) == [99608])
        #expect(entries.first?.isSelected == false)
    }

    @Test func autoSelectedDuplicateKeepsItsCheckedMenuIdentity() {
        let entries = AppleSubtitleCueLayerPolicy.menuEntries(tracks: [
            ApplePlaybackTrack(id: 3, title: "English", language: "en", isDefault: true),
            ApplePlaybackTrack(id: 8, title: "English", language: "eng")
        ], preferredLanguages: ["en"], languagesAreExplicit: true, activeTrackID: 8)
        #expect(entries.map(\.trackID) == [nil, 8])
        #expect(entries.filter(\.isSelected).map(\.trackID) == [8])
    }

    @MainActor @Test func adapterPublishesAutoSelectionAndOffWithoutAnAppCommand() throws {
        let engine = try AetherPlaybackEngine()
        engine.captionsPreference = .off
        engine.applyEngineSubtitleSelection(99608)
        engine.applyEmbeddedSubtitleTracks([
            ApplePlaybackTrack(id: 99608, title: "English", language: "en", codec: "eia_608")])
        let stock = AppleStockPlayerSubtitles()
        stock.refresh(from: engine)
        #expect(engine.activeSubtitleTrackID == 99608)
        #expect(stock.menuEntries.filter(\.isSelected).map(\.trackID) == [99608])
        engine.applyEngineSubtitleSelection(nil)
        stock.refresh(from: engine)
        #expect(stock.menuEntries.first?.isSelected == true)
        #expect(stock.cues.isEmpty)
        engine.stop()
    }
}
