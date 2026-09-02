import AVFoundation
import Foundation

#if os(iOS)
import AVKit

@MainActor
@available(iOS 18.0, *)
public final class OpenStreamMobilePlayerController {
    public let viewController: AVPlayerViewController
    public let playerSession: ApplePlayerSession
    public let audioSessionCoordinator: AppleAudioSessionCoordinator

    public init(
        url: URL,
        resumeAt seconds: Double = 0,
        mediaID: String? = nil,
        progressStore: ApplePlaybackStore? = nil,
        requestHeaders: [String: String] = [:],
        audioSessionCoordinator: AppleAudioSessionCoordinator = .init()
    ) {
        let session = ApplePlayerSession(
            url: url,
            resumeAt: seconds,
            mediaID: mediaID,
            progressStore: progressStore,
            requestHeaders: requestHeaders
        )
        let controller = AVPlayerViewController()
        controller.player = session.player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true

        playerSession = session
        self.audioSessionCoordinator = audioSessionCoordinator
        viewController = controller
    }

    public func prepareForPlayback() async throws -> AppleRoutePreparation {
        try audioSessionCoordinator.prepareForPlayback()
        return await audioSessionCoordinator.prepareRouteSelectionForPlayback()
    }

    public func stop(saveProgress: Bool = true) throws {
        playerSession.stop(saveProgress: saveProgress)
        try audioSessionCoordinator.deactivate()
    }
}
#endif

#if os(tvOS)
import AVKit

@MainActor
@available(tvOS 18.0, *)
public final class OpenStreamTVPlayerController {
    public let viewController: AVPlayerViewController
    public let playerSession: ApplePlayerSession
    public let audioSessionCoordinator: AppleAudioSessionCoordinator

    public init(
        url: URL,
        resumeAt seconds: Double = 0,
        mediaID: String? = nil,
        progressStore: ApplePlaybackStore? = nil,
        requestHeaders: [String: String] = [:],
        audioSessionCoordinator: AppleAudioSessionCoordinator = .init()
    ) {
        let session = ApplePlayerSession(
            url: url,
            resumeAt: seconds,
            mediaID: mediaID,
            progressStore: progressStore,
            requestHeaders: requestHeaders
        )
        let controller = AVPlayerViewController()
        controller.player = session.player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.appliesPreferredDisplayCriteriaAutomatically = true

        playerSession = session
        self.audioSessionCoordinator = audioSessionCoordinator
        viewController = controller
    }

    public func prepareForPlayback() throws {
        try audioSessionCoordinator.prepareForPlayback()
    }

    public func stop(saveProgress: Bool = true) throws {
        playerSession.stop(saveProgress: saveProgress)
        try audioSessionCoordinator.deactivate()
    }
}
#endif

#if os(visionOS)
import AVKit

/// visionOS 2 through 25 receives the standard AVKit player. visionOS 26 adds
/// an opt-in immersive experience without changing the baseline controller.
@MainActor
@available(visionOS 2.0, *)
public final class OpenStreamVisionPlayerController {
    public let viewController: AVPlayerViewController
    public let playerSession: ApplePlayerSession

    public init(
        url: URL,
        resumeAt seconds: Double = 0,
        mediaID: String? = nil,
        progressStore: ApplePlaybackStore? = nil,
        requestHeaders: [String: String] = [:]
    ) {
        let session = ApplePlayerSession(
            url: url,
            resumeAt: seconds,
            mediaID: mediaID,
            progressStore: progressStore,
            requestHeaders: requestHeaders
        )
        let controller = AVPlayerViewController()
        controller.player = session.player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true

        if #available(visionOS 26.0, *) {
            var configuration = controller.experienceController.configuration
            configuration.expanded.automaticTransitionToImmersive = .none
            controller.experienceController.configuration = configuration
            controller.experienceController.allowedExperiences = .recommended(
                including: [AVExperienceController.Experience.immersive]
            )
        }

        playerSession = session
        viewController = controller
    }

    public var supportsImmersiveExperience: Bool {
        if #available(visionOS 26.0, *) {
            viewController.experienceController.availableExperiences.contains(.immersive)
        } else {
            false
        }
    }

    @available(visionOS 26.0, *)
    @discardableResult
    public func enterImmersive() async -> Bool {
        let controller = viewController.experienceController
        guard controller.availableExperiences.contains(.immersive) else { return false }
        return await controller.transition(to: .immersive) == .completed
    }

    @available(visionOS 26.0, *)
    public func leaveImmersive() async {
        _ = await viewController.experienceController.transition(to: .expanded)
    }

    public func stop(saveProgress: Bool = true) {
        playerSession.stop(saveProgress: saveProgress)
    }
}
#endif

#if os(macOS)
import AVKit

@MainActor
@available(macOS 15.0, *)
public final class OpenStreamMacPlayerHost {
    public let playerView: AVPlayerView
    public let playerSession: ApplePlayerSession

    public init(
        url: URL,
        resumeAt seconds: Double = 0,
        mediaID: String? = nil,
        progressStore: ApplePlaybackStore? = nil,
        requestHeaders: [String: String] = [:]
    ) {
        let session = ApplePlayerSession(
            url: url,
            resumeAt: seconds,
            mediaID: mediaID,
            progressStore: progressStore,
            requestHeaders: requestHeaders
        )
        let playerView = AVPlayerView()
        playerView.player = session.player
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        playerView.allowsPictureInPicturePlayback = true

        playerSession = session
        self.playerView = playerView
    }

    public func stop(saveProgress: Bool = true) {
        playerSession.stop(saveProgress: saveProgress)
    }
}
#endif
