#if os(iOS) || os(tvOS)
import AVFoundation
import Foundation
#if os(iOS)
import AVKit
#endif

public enum AppleAudioRenderingMode: String, Equatable, Sendable {
    case notApplicable
    case monoStereo
    case surround
    case spatialAudio
    case dolbyAudio
    case dolbyAtmos
    case unknown
}

public struct AppleAudioOutputRoute: Equatable, Sendable {
    public let name: String
    public let portType: String
    public let channelCount: Int
    public let spatialAudioEnabled: Bool

    public init(name: String, portType: String, channelCount: Int, spatialAudioEnabled: Bool) {
        self.name = name
        self.portType = portType
        self.channelCount = channelCount
        self.spatialAudioEnabled = spatialAudioEnabled
    }
}

public struct AppleAudioRouteState: Equatable, Sendable {
    public let outputs: [AppleAudioOutputRoute]
    public let supportsMultichannelContent: Bool
    public let maximumOutputChannelCount: Int
    public let supportedOutputChannelCounts: [Int]
    public let spatialAudioEnabled: Bool
    public let renderingMode: AppleAudioRenderingMode
    public let lastRouteChangeReasonRawValue: UInt?

    public init(
        outputs: [AppleAudioOutputRoute],
        supportsMultichannelContent: Bool,
        maximumOutputChannelCount: Int,
        supportedOutputChannelCounts: [Int],
        spatialAudioEnabled: Bool,
        renderingMode: AppleAudioRenderingMode,
        lastRouteChangeReasonRawValue: UInt?
    ) {
        self.outputs = outputs
        self.supportsMultichannelContent = supportsMultichannelContent
        self.maximumOutputChannelCount = maximumOutputChannelCount
        self.supportedOutputChannelCounts = supportedOutputChannelCounts
        self.spatialAudioEnabled = spatialAudioEnabled
        self.renderingMode = renderingMode
        self.lastRouteChangeReasonRawValue = lastRouteChangeReasonRawValue
    }
}

#if os(iOS)
public enum ApplePreparedRouteSelection: String, Equatable, Sendable {
    case none
    case local
    case external
    case unknown
}

public struct AppleRoutePreparation: Equatable, Sendable {
    public let shouldStartPlayback: Bool
    public let selection: ApplePreparedRouteSelection

    public init(shouldStartPlayback: Bool, selection: ApplePreparedRouteSelection) {
        self.shouldStartPlayback = shouldStartPlayback
        self.selection = selection
    }
}
#endif

/// Configures long-form movie playback while leaving route selection,
/// headphone personalization, head tracking, and Control Center overrides to
/// the system. State refreshes when routes or spatial capabilities change.
@MainActor
public final class AppleAudioSessionCoordinator: NSObject {
    public private(set) var state: AppleAudioRouteState
    public var onStateChange: (@MainActor @Sendable (AppleAudioRouteState) -> Void)?

    private let session: AVAudioSession

    public init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
        state = Self.makeState(session: session, lastRouteChangeReasonRawValue: nil)
        super.init()

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(routeDidChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(spatialCapabilitiesDidChange(_:)),
            name: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(spatialCapabilitiesDidChange(_:)),
            name: AVAudioSession.renderingModeChangeNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(spatialCapabilitiesDidChange(_:)),
            name: AVAudioSession.renderingCapabilitiesChangeNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(mediaServicesWereReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: session
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Configures and activates the shared session immediately before movie
    /// playback. iOS uses the long-form-video sharing policy so system route
    /// selection keeps audio and video together; tvOS manages that policy.
    public func prepareForPlayback() throws {
        #if os(iOS)
        try session.setCategory(
            .playback,
            mode: .moviePlayback,
            policy: .longFormVideo,
            options: []
        )
        #else
        try session.setCategory(.playback, mode: .moviePlayback, options: [])
        #endif
        try session.setSupportsMultichannelContent(true)
        try session.setActive(true)
        refreshState()
    }

    public func deactivate() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
        refreshState()
    }

    #if os(iOS)
    public func prepareRouteSelectionForPlayback() async -> AppleRoutePreparation {
        await withCheckedContinuation { continuation in
            session.prepareRouteSelectionForPlayback { shouldStartPlayback, selection in
                continuation.resume(returning: AppleRoutePreparation(
                    shouldStartPlayback: shouldStartPlayback,
                    selection: Self.preparedSelection(selection)
                ))
            }
        }
    }
    #endif

    public func refreshState() {
        refreshState(lastRouteChangeReasonRawValue: state.lastRouteChangeReasonRawValue)
    }

    @objc
    private func routeDidChange(_ notification: Notification) {
        let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
        refreshState(lastRouteChangeReasonRawValue: reason)
    }

    @objc
    private func spatialCapabilitiesDidChange(_: Notification) {
        refreshState()
    }

    @objc
    private func mediaServicesWereReset(_: Notification) {
        do {
            try prepareForPlayback()
        } catch {
            refreshState()
        }
    }

    private func refreshState(lastRouteChangeReasonRawValue: UInt?) {
        state = Self.makeState(
            session: session,
            lastRouteChangeReasonRawValue: lastRouteChangeReasonRawValue
        )
        onStateChange?(state)
    }

    private static func makeState(
        session: AVAudioSession,
        lastRouteChangeReasonRawValue: UInt?
    ) -> AppleAudioRouteState {
        let outputs = session.currentRoute.outputs.map { output in
            AppleAudioOutputRoute(
                name: output.portName,
                portType: output.portType.rawValue,
                channelCount: output.channels?.count ?? 0,
                spatialAudioEnabled: output.isSpatialAudioEnabled
            )
        }
        return AppleAudioRouteState(
            outputs: outputs,
            supportsMultichannelContent: session.supportsMultichannelContent,
            maximumOutputChannelCount: session.maximumOutputNumberOfChannels,
            supportedOutputChannelCounts: session.supportedOutputChannelLayouts
                .map { Int($0.channelCount) }
                .sorted(),
            spatialAudioEnabled: outputs.contains(where: \.spatialAudioEnabled),
            renderingMode: renderingMode(session.renderingMode),
            lastRouteChangeReasonRawValue: lastRouteChangeReasonRawValue
        )
    }

    private static func renderingMode(_ value: AVAudioSession.RenderingMode) -> AppleAudioRenderingMode {
        switch value {
        case .notApplicable: .notApplicable
        case .monoStereo: .monoStereo
        case .surround: .surround
        case .spatialAudio: .spatialAudio
        case .dolbyAudio: .dolbyAudio
        case .dolbyAtmos: .dolbyAtmos
        @unknown default: .unknown
        }
    }

    #if os(iOS)
    nonisolated private static func preparedSelection(
        _ value: AVAudioSession.RouteSelection
    ) -> ApplePreparedRouteSelection {
        switch value {
        case .none: .none
        case .local: .local
        case .external: .external
        @unknown default: .unknown
        }
    }
    #endif
}
#endif
