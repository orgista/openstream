import SwiftUI

/// When a home hero's inline trailer may play: the Apple TV app's background
/// video rules (REA of the Mac TV app, `verification-artifacts/rea-mac-tv-2026-10-12/report.md` §1),
/// shared by the iPhone, iPad, Mac and Vision Pro heroes.
///
/// Autoplay needs the Auto-Play Trailers setting, Reduce Motion and Low Power
/// Mode off, the system's video autoplay on, the app active, at least half the
/// hero visible, nothing pushed or presented over it, and its still settled
/// first. A pressed Play Trailer skips only the setting, and may play over art
/// that failed to load (`AppleTrailerArtFirstPolicy.mayRequestTrailer`).
public enum AppleHeroTrailerGate {
    public struct Conditions: Equatable, Sendable {
        public var autoPlaySetting: Bool
        public var reduceMotion: Bool
        public var lowPower: Bool
        public var systemVideoAutoplay: Bool
        public var sceneIsActive: Bool
        /// At least half the hero is on screen (`onScrollVisibilityChange(threshold: 0.5)`).
        public var halfVisible: Bool
        /// The hero's page is on screen: not under a pushed title page, not
        /// on another tab.
        public var isPresented: Bool
        /// A sheet or full-screen cover is over it (`appleHeroIsCovered`).
        public var isCovered: Bool
        /// The Mac window is on screen and not fully covered; true elsewhere.
        public var windowIsVisible: Bool
        public var art: AppleTrailerArtFirstPolicy.Art
        /// The viewer pressed Play Trailer.
        public var pressed: Bool

        public init(autoPlaySetting: Bool = true, reduceMotion: Bool = false, lowPower: Bool = false,
                    systemVideoAutoplay: Bool = true, sceneIsActive: Bool = true, halfVisible: Bool = true,
                    isPresented: Bool = true, isCovered: Bool = false, windowIsVisible: Bool = true,
                    art: AppleTrailerArtFirstPolicy.Art = .loaded, pressed: Bool = false) {
            self.autoPlaySetting = autoPlaySetting
            self.reduceMotion = reduceMotion
            self.lowPower = lowPower
            self.systemVideoAutoplay = systemVideoAutoplay
            self.sceneIsActive = sceneIsActive
            self.halfVisible = halfVisible
            self.isPresented = isPresented
            self.isCovered = isCovered
            self.windowIsVisible = windowIsVisible
            self.art = art
            self.pressed = pressed
        }
    }

    /// Whether the trailer may be up. When this turns false the video is
    /// taken down and the still crossfades back; when it turns true again the
    /// trailer starts over.
    public static func plays(_ conditions: Conditions) -> Bool {
        guard !conditions.reduceMotion, !conditions.lowPower, conditions.systemVideoAutoplay else { return false }
        let onScreen = conditions.halfVisible && conditions.isPresented && !conditions.isCovered
            && conditions.windowIsVisible && conditions.sceneIsActive
        guard onScreen, AppleTrailerArtFirstPolicy.mayRequestTrailer(art: conditions.art, pressed: conditions.pressed)
        else { return false }
        return conditions.pressed || conditions.autoPlaySetting
    }
}

extension EnvironmentValues {
    /// A sheet or full-screen cover is up over the hero: its trailer stops
    /// (`AppleHeroTrailerGate`). A pushed page is seen by the hero itself.
    @Entry var appleHeroIsCovered = false
}
