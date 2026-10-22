import AetherEngine
import Foundation
import Network
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

extension AppleStreamDeviceCapabilities {
    /// This device and display right now, for `playbackOrder`.
    ///
    /// HDR and Dolby Vision come from the engine's display snapshot, the one
    /// its own routing reads (`AetherEngine.displayCapabilities`), so the
    /// picker never prefers a stream the engine would then tone-map. Automatic
    /// follows the window's native display pixels, with a 1080p limit on a
    /// cellular or Low Data connection.
    @MainActor
    public static var current: AppleStreamDeviceCapabilities {
        let display = AetherEngine.displayCapabilities
        #if os(iOS)
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let pixels = window?.windowScene?.screen.nativeBounds.size ?? .zero
        let cap = automaticTierCap(nativePixelSize: pixels, isCostly: AppleNetworkCost.shared.isCostly)
        #else
        let cap: AppleStreamQualityTier = AppleNetworkCost.shared.isCostly ? .fullHD : .uhd
        #endif
        return AppleStreamDeviceCapabilities(
            supportsHDR: display.supportsHDR,
            supportsDolbyVision: display.supportsDolbyVision,
            automaticTierCap: cap)
    }
}

/// Whether the current connection is metered: cellular, a personal hotspot,
/// or Low Data Mode. Starts watching on first use.
final class AppleNetworkCost: Sendable {
    static let shared = AppleNetworkCost()

    private let monitor = NWPathMonitor()
    private let state = Mutex(false)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.state.withLock { $0 = path.isExpensive || path.isConstrained }
        }
        monitor.start(queue: DispatchQueue(label: "openstream.network-cost", qos: .utility))
    }

    var isCostly: Bool { state.withLock { $0 } }
}
