import AVKit
import SwiftUI

#if os(iOS)
extension OpenStreamMobilePlayerController {
    public convenience init(
        preparedPlayback: ApplePreparedPlayback,
        resumeAt seconds: Double = 0,
        mediaID: String? = nil,
        progressStore: ApplePlaybackStore? = nil,
        audioSessionCoordinator: AppleAudioSessionCoordinator = .init()
    ) {
        self.init(
            url: preparedPlayback.url,
            resumeAt: seconds,
            mediaID: mediaID,
            progressStore: progressStore,
            requestHeaders: preparedPlayback.requestHeaders,
            audioSessionCoordinator: audioSessionCoordinator
        )
    }
}
#elseif os(tvOS)
extension OpenStreamTVPlayerController {
    public convenience init(
        preparedPlayback: ApplePreparedPlayback,
        resumeAt seconds: Double = 0,
        mediaID: String? = nil,
        progressStore: ApplePlaybackStore? = nil,
        audioSessionCoordinator: AppleAudioSessionCoordinator = .init()
    ) {
        self.init(
            url: preparedPlayback.url,
            resumeAt: seconds,
            mediaID: mediaID,
            progressStore: progressStore,
            requestHeaders: preparedPlayback.requestHeaders,
            audioSessionCoordinator: audioSessionCoordinator
        )
    }
}
#elseif os(visionOS)
extension OpenStreamVisionPlayerController {
    public convenience init(
        preparedPlayback: ApplePreparedPlayback,
        resumeAt seconds: Double = 0,
        mediaID: String? = nil,
        progressStore: ApplePlaybackStore? = nil
    ) {
        self.init(
            url: preparedPlayback.url,
            resumeAt: seconds,
            mediaID: mediaID,
            progressStore: progressStore,
            requestHeaders: preparedPlayback.requestHeaders
        )
    }
}
#elseif os(macOS)
extension OpenStreamMacPlayerHost {
    public convenience init(
        preparedPlayback: ApplePreparedPlayback,
        resumeAt seconds: Double = 0,
        mediaID: String? = nil,
        progressStore: ApplePlaybackStore? = nil
    ) {
        self.init(
            url: preparedPlayback.url,
            resumeAt: seconds,
            mediaID: mediaID,
            progressStore: progressStore,
            requestHeaders: preparedPlayback.requestHeaders
        )
    }
}
#endif

struct AppleStremioPlayerPresentation: Identifiable {
    let id = UUID()
    let title: String
    let mediaID: String
    let playback: ApplePreparedPlayback
    let securityScopedURL: URL?

    init(
        title: String,
        mediaID: String,
        playback: ApplePreparedPlayback,
        securityScopedURL: URL? = nil
    ) {
        self.title = title
        self.mediaID = mediaID
        self.playback = playback
        self.securityScopedURL = securityScopedURL
    }
}

@MainActor
struct AppleStremioPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host: AppleStremioPlatformPlayerHost
    @State private var startError: String?
    @State private var securityAccess: AppleSecurityScopedAccess?

    private let title: String

    init(presentation: AppleStremioPlayerPresentation) {
        title = presentation.title
        _host = State(initialValue: AppleStremioPlatformPlayerHost(
            playback: presentation.playback,
            mediaID: presentation.mediaID
        ))
        _securityAccess = State(initialValue: presentation.securityScopedURL.map(AppleSecurityScopedAccess.init(url:)))
    }

    var body: some View {
        NavigationStack {
            platformPlayer
                .ignoresSafeArea()
                .navigationTitle(title)
                #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                #endif
        }
        #if os(tvOS) || os(macOS)
        .onExitCommand { dismiss() }
        #endif
        .task {
            do {
                try await host.start()
            } catch is CancellationError {
                return
            } catch {
                startError = error.localizedDescription
            }
        }
        .onDisappear {
            host.stop()
            securityAccess = nil
        }
        .alert("Playback Failed", isPresented: playbackErrorBinding) {
            Button("Close") { dismiss() }
        } message: {
            Text(startError ?? "Playback failed.")
        }
    }

    @ViewBuilder
    private var platformPlayer: some View {
        #if os(macOS)
        AppleStremioMacPlayerRepresentable(playerView: host.playerView)
        #else
        AppleStremioPlayerControllerRepresentable(viewController: host.viewController)
        #endif
    }

    private var playbackErrorBinding: Binding<Bool> {
        Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )
    }
}

@MainActor
private final class AppleStremioPlatformPlayerHost {
    #if os(iOS)
    private let host: OpenStreamMobilePlayerController
    #elseif os(tvOS)
    private let host: OpenStreamTVPlayerController
    #elseif os(visionOS)
    private let host: OpenStreamVisionPlayerController
    #elseif os(macOS)
    private let host: OpenStreamMacPlayerHost
    #endif

    init(playback: ApplePreparedPlayback, mediaID: String) {
        #if os(iOS)
        host = OpenStreamMobilePlayerController(preparedPlayback: playback, mediaID: mediaID)
        #elseif os(tvOS)
        host = OpenStreamTVPlayerController(preparedPlayback: playback, mediaID: mediaID)
        #elseif os(visionOS)
        host = OpenStreamVisionPlayerController(preparedPlayback: playback, mediaID: mediaID)
        #elseif os(macOS)
        host = OpenStreamMacPlayerHost(preparedPlayback: playback, mediaID: mediaID)
        #endif
    }

    #if os(macOS)
    var playerView: AVPlayerView { host.playerView }
    #else
    var viewController: AVPlayerViewController { host.viewController }
    #endif

    func start() async throws {
        #if os(iOS)
        _ = try await host.prepareForPlayback()
        #elseif os(tvOS)
        try host.prepareForPlayback()
        #endif
        host.playerSession.player.play()
    }

    func stop() {
        #if os(iOS) || os(tvOS)
        try? host.stop()
        #else
        host.stop()
        #endif
    }
}

#if os(macOS)
private struct AppleStremioMacPlayerRepresentable: NSViewRepresentable {
    let playerView: AVPlayerView

    func makeNSView(context: Context) -> AVPlayerView { playerView }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
#else
private struct AppleStremioPlayerControllerRepresentable: UIViewControllerRepresentable {
    let viewController: AVPlayerViewController

    func makeUIViewController(context: Context) -> AVPlayerViewController { viewController }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
#endif
