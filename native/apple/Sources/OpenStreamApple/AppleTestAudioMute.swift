import Foundation

/// Debug-only: `-OpenStreamMuteAudio YES` keeps every player silent, so
/// simulator test runs on the owner's Mac make no sound. Release builds
/// always answer `false`.
public enum AppleTestAudioMute {
    public static let isActive: Bool = {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "OpenStreamMuteAudio")
        #else
        false
        #endif
    }()
}
