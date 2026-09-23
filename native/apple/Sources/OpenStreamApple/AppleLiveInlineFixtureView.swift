#if DEBUG && !os(tvOS)
import SwiftUI

/// Local-only proof of the production inline player, without loading saved
/// sources or writing a channel/history entry on a review simulator.
public struct AppleLiveInlineFixtureView: View {
    @State private var coordinator: ApplePlaybackCoordinator
    private let request: ApplePlaybackRequest?

    public init() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "OpenStreamVisionPlaybackIsLive"),
           let raw = defaults.string(forKey: "OpenStreamVisionPlaybackURL"),
           let url = URL(string: raw), url.scheme == "http", url.host == "127.0.0.1" {
            request = AppleIPTVChannel(id: "inline-caption-fixture", sourceID: UUID(),
                                      name: "Caption fixture", streamURL: url).playbackRequest()
        } else {
            request = nil
        }
        let (engine, _) = ApplePlaybackEngineFactory.make(preferred: .openStream)
        let languages = defaults.stringArray(forKey: AppleSubtitleLanguages.defaultsKey)
        let preference = defaults.string(forKey: "openstream.settings.captions.preference.v1")
            .flatMap(AppleCaptionsPreference.init(rawValue:)) ?? .always
        engine.applyCaptionPreferences(preference: preference, languages: languages ?? [],
                                       languagesAreExplicit: languages != nil)
        _coordinator = State(initialValue: ApplePlaybackCoordinator(engine: engine))
    }

    public var body: some View {
        TabView {
            Tab("Live", systemImage: "dot.radiowaves.left.and.right") {
                NavigationStack {
                    VStack(spacing: 0) {
                        if let request {
                            AppleLiveInlinePlayer(request: request, coordinator: coordinator,
                                                  playbackRevision: 0, logoURL: nil, sharedChannel: nil)
                                .aspectRatio(16 / 9, contentMode: .fit)
                            Label("Caption fixture", systemImage: "tv")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        Spacer()
                    }
                    .navigationTitle("Live")
                }
            }
        }
        .tint(.primary)
    }
}
#endif
